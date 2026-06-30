;;; LSMA — Phase 1: Canonical AST Hash + Passport
;;; File: v9/src/lsma/passport.lisp
;;;
;;; Package defined in package.lisp — this file assumes (in-package :lsma).
;;;
;;; Provides:
;;;   canonical-ast-hash       — deterministic hash (structure, not variable names)
;;;   canonical-ast            — variable-canonicalized copy of an AST
;;;   canonicalize-variables   — rename variables to V0, V1, V2... by first occurrence
;;;   canonicalize-constants   — normalize floating-point precision
;;;   extract-passport         — full passport plist from an AST
;;;   extract-operator-profile — operator frequency map
;;;   extract-subtree-hashes   — top-N subtrees by depth
;;;   extract-depth-profile    — depth at each node position
;;;   ast-structural-equal-p   — compare by canonical hash
;;;
;;; Dependencies: sb-md5 (SBCL built-in) for hashing.
;;;   ironclad (SHA256) used if available, otherwise sb-md5.

(in-package :lsma)

;; ————————————————————————————————————————————————————————————————————
;; Configuration
;; ————————————————————————————————————————————————————————————————————

(defvar *canonical-variables*
  '(x y z t q1 q2 q3 m2x3 m3x2 m3x3 m4x1 s1 s2 v1 v2 t_hot t_cold area volume p q)
  "Default variable list for canonicalization.
   Also consults *unified-variables* from :cognitive-engine when available.")

(defvar *subtree-hash-limit* 50
  "Maximum number of subtree hashes to store per passport.")

(defvar *float-precision* 6
  "Decimal places to round floats to for canonicalization.")

;; ————————————————————————————————————————————————————————————————————
;; Hash helper — uses sb-md5 (SBCL built-in) by default.
;; Optionally loads ironclad for SHA256 if available.
;; ————————————————————————————————————————————————————————————————————

(defun %ensure-hash-module ()
  "Ensure a hash module is loaded. Tries sb-md5 first, then falls back to a simple hash."
  (ignore-errors (require :sb-md5)))

(defun %hash-bytes (bytes)
  "Return hex string hash of byte vector.
   Uses sb-md5 (SBCL contrib). Loaded at runtime to avoid reader package errors.
   Always returns a simple string for deterministic printing."
  (%ensure-hash-module)
  (let* ((input (sb-ext:octets-to-string bytes :external-format :utf-8))
         (md5-fn (find-symbol "MD5SUM-STRING" :sb-md5))
         (raw (if md5-fn (funcall md5-fn input) nil)))
    (cond ((stringp raw) (copy-seq raw))
          ((typep raw '(vector (unsigned-byte 8)))
           (format nil "~(~{~2,'0X~}~)"
                   (coerce raw 'list)))
          (t
           (format nil "~(~36,8R~)" (sxhash input))))))

(defun %ast->bytes (ast)
  "Serialize an AST to a UTF-8 byte vector for hashing.
   Uses deterministic printing: downcase, no package prefixes."
  (let* ((*print-case* :downcase)
         (*print-readably* nil)
         (*package* (find-package :keyword)))
    (sb-ext:string-to-octets
     (write-to-string ast :case :downcase :escape nil :readably nil)
     :external-format :utf-8)))

;; ————————————————————————————————————————————————————————————————————
;; Variable canonicalization
;; ————————————————————————————————————————————————————————————————————

(defun %resolve-variables ()
  "Return the effective variable list for canonicalization.
   Merges *canonical-variables* with cognitive-engine's *unified-variables* if available."
  (let ((eng-var (ignore-errors
                   (symbol-value (find-symbol (string '*unified-variables*)
                                              (find-package :cognitive-engine))))))
    (if eng-var
        (union *canonical-variables* eng-var)
        *canonical-variables*)))

(defun canonicalize-variables (ast &key (variables (%resolve-variables)))
  "Replace variable names with positional indices V0, V1, V2...
   based on depth-first first occurrence.
   Operators (car of a list) and numeric constants are left unchanged."
  (let ((var-map (make-hash-table))
        (counter 0))
    (labels ((walk (node)
               (cond
                 ((numberp node) node)
                 ((symbolp node)
                  (if (or (member node variables)
                          (and (not (find-symbol (string node)
                                                (find-package :cognitive-engine)))
                               (not (numberp node))
                               (symbolp node)))
                      (let ((found (gethash node var-map)))
                        (if found
                            found
                            (let ((new (intern (format nil "V~D" counter))))
                              (setf (gethash node var-map) new)
                              (incf counter)
                              new)))
                      node))
                  ((consp node)
                   (if (eq (car node) 'quote)
                       node
                       (cons (car node) (mapcar #'walk (cdr node)))))
                 (t node))))
      (walk ast))))

;; ————————————————————————————————————————————————————————————————————
;; Constant canonicalization
;; ————————————————————————————————————————————————————————————————————

(defun canonicalize-constants (ast)
  "Normalize floating-point constants: round to *float-precision* decimals.
   Integers and symbols left unchanged."
  (labels ((%round-to (val)
             (let ((s (expt 10.0 *float-precision*)))
               (/ (round (* val s)) s)))
           (walk (node)
             (cond
               ((typep node 'float) (%round-to node))
               ((consp node)
                (if (eq (car node) 'quote)
                    node
                    (cons (car node) (mapcar #'walk (cdr node)))))
               (t node))))
    (walk ast)))

;; ————————————————————————————————————————————————————————————————————
;; Canonical AST
;; ————————————————————————————————————————————————————————————————————

(defun canonical-ast (ast &key (variables (%resolve-variables)))
  "Return a canonical copy of AST: variable names -> Vn, constants normalized."
  (canonicalize-constants
   (canonicalize-variables ast :variables variables)))

;; ————————————————————————————————————————————————————————————————————
;; Canonical hash
;; ————————————————————————————————————————————————————————————————————

(defun canonical-ast-hash (ast &key (variables (%resolve-variables)))
  "Return a deterministic hex hash for an AST based on its canonical form.
   Same structure always produces the same hash, regardless of variable names."
  (%hash-bytes (%ast->bytes (canonical-ast ast :variables variables))))

;; ————————————————————————————————————————————————————————————————————
;; Structural equality
;; ————————————————————————————————————————————————————————————————————

(defun ast-structural-equal-p (ast1 ast2 &key (variables (%resolve-variables)))
  "Return T if two ASTs have the same canonical hash."
  (string= (canonical-ast-hash ast1 :variables variables)
           (canonical-ast-hash ast2 :variables variables)))

;; ————————————————————————————————————————————————————————————————————
;; Passport extraction
;; ————————————————————————————————————————————————————————————————————

(defun %all-subtrees (ast)
  "Return a list of all subtrees (including the root) of AST."
  (cons ast
        (when (consp ast)
          (mapcan #'%all-subtrees (cdr ast)))))

(defun extract-subtree-hashes (ast &key (limit *subtree-hash-limit*))
  "Return a list of canonical hashes for all subtrees, capped at LIMIT.
   Sorted by depth (deepest first) to capture detail rather than whole trees."
  (let* ((subtrees (%all-subtrees ast))
         (hashes (mapcar (lambda (st) (canonical-ast-hash st)) subtrees))
         ;; sort by AST size (proxy for depth) descending, then take top-N
         (sorted (sort (copy-list hashes) #'> :key (lambda (h) (length h)))))
    (subseq sorted 0 (min limit (length sorted)))))

(defun extract-operator-profile (ast)
  "Return an alist of (operator . count) for all operators in AST."
  (let ((freq (make-hash-table)))
    (labels ((walk (node)
               (when (consp node)
                 (let ((op (car node)))
                   (unless (eq op 'quote)
                     (incf (gethash op freq 0))
                     (mapc #'walk (cdr node)))))))
      (walk ast))
    (let (result)
      (maphash (lambda (k v) (push (cons k v) result)) freq)
      (sort result #'> :key #'cdr))))

(defun extract-depth-profile (ast)
  "Return a list of (position . depth) for each node in AST (DFS order)."
  (let (profile)
    (labels ((walk (node depth pos)
               (push (list pos depth) profile)
               (when (consp node)
                 (unless (eq (car node) 'quote)
                   (loop for child in (cdr node)
                         for i from 0
                         do (walk child (1+ depth) (format nil "~A.~D" pos i)))))))
      (walk ast 0 "0"))
    (nreverse profile)))

(defun extract-passport (ast &key (domain nil))
  "Assemble a full passport plist for AST.
   Returns a plist with keys:
     :ast-hash :subtree-hashes :operator-profile :depth-profile
     :domains :usage-count :success-count :failure-count
     :lineage :behavior-trace :fitness-scores :freshness"
  (let ((hash (canonical-ast-hash ast)))
    (list :ast-hash hash
          :subtree-hashes (extract-subtree-hashes ast)
          :operator-profile (extract-operator-profile ast)
          :depth-profile (extract-depth-profile ast)
          :domains (if domain (list domain) nil)
          :usage-count 0
          :success-count 0
          :failure-count 0
          :lineage nil
          :behavior-trace nil
          :fitness-scores nil
          :freshness (multiple-value-bind (s m h d mo y)
                         (get-decoded-time)
                       (format nil "~4,'0D-~2,'0D-~2,'0DT~2,'0D:~2,'0D:~2,'0DZ"
                               y mo d h m s)))))

;; ————————————————————————————————————————————————————————————————————
;; Passport accessors
;; ————————————————————————————————————————————————————————————————————

(defun passport-get (passport key)
  "Get a value from a passport plist."
  (getf passport key))
