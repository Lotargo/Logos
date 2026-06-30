;;; LSMA — Phase 1: JSONL/Neon Storage
;;; File: v9/src/lsma/storage.lisp
;;;
;;; Two-layer persistent storage for AST passports:
;;;   1. Local JSONL cache (always, fast, Lisp-readable plist format)
;;;   2. Neon PostgreSQL (logos_knowledge table, via Python telemetry bridge)
;;;
;;; Write-through: save always hits JSONL, optionally Neon.
;;; Read: JSONL first, Neon fallback.
;;;
;;; Package defined in package.lisp — this file assumes (in-package :lsma).
;;; Dependencies: lsma/passport.lisp, telemetry_helper.lisp

(in-package :lsma)

;; ————————————————————————————————————————————————————————————————————
;; Configuration
;; ————————————————————————————————————————————————————————————————————

(defvar *jsonl-cache-path*
  (or (ignore-errors (uiop:getenv "LOGOS_JSONL_CACHE"))
      "v9/telemetry/cache/logos_knowledge.jsonl")
  "Path to the JSONL cache file for passport storage.")

(defvar *python-executable*
  (or (uiop:getenv "LOGOS_PYTHON")
      #+win32 "C:/Users/etotm/AppData/Local/Programs/Python/Python312/python.exe"
      "python3")
  "Python interpreter path for the telemetry bridge.")

;; ————————————————————————————————————————————————————————————————————
;; JSONL cache helpers
;; ————————————————————————————————————————————————————————————————————

(defun %ensure-cache-dir ()
  (let ((dir (make-pathname :name nil :type nil :defaults *jsonl-cache-path*)))
    (ensure-directories-exist dir)))

(defun %passport-plist->line (passport)
  "Serialize a passport plist to a single-line Lisp plist for JSONL.
   Uses *print-pretty* nil and *print-case* :downcase for deterministic output."
  (with-standard-io-syntax
    (let ((*print-pretty* nil)
          (*print-case* :downcase)
          (*print-readably* nil))
      (let ((line (format nil "~S~%"
                          (list :ast-hash (getf passport :ast-hash)
                                :ast-str (getf passport :ast-str "")
                                :operator-profile (getf passport :operator-profile)
                                :domains (getf passport :domains)
                                :subtree-hashes (getf passport :subtree-hashes)
                                :depth-profile (getf passport :depth-profile)
                                :usage-count (getf passport :usage-count 0)
                                :success-count (getf passport :success-count 0)
                                :failure-count (getf passport :failure-count 0)
                                :lineage (getf passport :lineage)
                                :fitness-scores (getf passport :fitness-scores)
                                :freshness (getf passport :freshness "")))))
        (remove #\Return line)))))

(defun %line->passport-plist (line)
  "Parse a single JSONL line back into a passport plist."
  (handler-case
      (let ((data (read-from-string line)))
        (list :ast-hash (getf data :ast-hash)
              :ast-str (getf data :ast-str "")
              :operator-profile (getf data :operator-profile)
              :domains (getf data :domains)
              :subtree-hashes (getf data :subtree-hashes)
              :depth-profile (getf data :depth-profile)
              :usage-count (getf data :usage-count 0)
              :success-count (getf data :success-count 0)
              :failure-count (getf data :failure-count 0)
              :lineage (getf data :lineage)
              :fitness-scores (getf data :fitness-scores)
              :freshness (getf data :freshness "")))
    (error () nil)))

(defun %hash-exists-in-cache-p (hash)
  "Return T if a passport with the given hash is already in the JSONL cache."
  (unless (probe-file *jsonl-cache-path*)
    (return-from %hash-exists-in-cache-p nil))
  (with-open-file (f *jsonl-cache-path* :direction :input :if-does-not-exist nil)
    (when f
      (loop for line = (read-line f nil nil)
            while line
            do (handler-case
                   (let ((data (read-from-string line)))
                     (when (string= (getf data :ast-hash) hash)
                       (return-from %hash-exists-in-cache-p t)))
                 (error ())))))
  nil)

(defun jsonl-cache-write (passport &key (dedup t))
  "Append a passport to the JSONL cache.
   When DEDUP is T (default), skips write if hash already exists."
  (%ensure-cache-dir)
  (let ((hash (getf passport :ast-hash)))
    (when (and hash dedup (%hash-exists-in-cache-p hash))
      (return-from jsonl-cache-write nil))
    (with-open-file (f *jsonl-cache-path*
                       :direction :output
                       :if-exists :append
                       :if-does-not-exist :create
                       :external-format :utf-8)
      (write-string (%passport-plist->line passport) f))
    t))

(defun jsonl-cache-read (&key (hash nil) (domain nil))
  "Read passports from JSONL cache. Filters by hash or domain when provided.
   Returns a list of passport plists."
  (unless (probe-file *jsonl-cache-path*)
    (return-from jsonl-cache-read nil))
  (let (results seen)
    (with-open-file (f *jsonl-cache-path*
                       :direction :input
                       :if-does-not-exist nil
                       :external-format :utf-8)
      (when f
        (loop for line = (read-line f nil nil)
              while line
              do (let ((plist (%line->passport-plist line)))
                   (when plist
                     (let ((h (getf plist :ast-hash)))
                       (when (and (or (null hash) (string= h hash))
                                  (or (null domain)
                                      (member domain (getf plist :domains)
                                              :test (lambda (d e)
                                                      (string-equal (string d) (string e))))))
                         (unless (member h seen :test #'string=)
                           (push h seen)
                           (push plist results)))))))))
    (nreverse results)))

(defun jsonl-cache-delete (hash)
  "Remove all lines matching hash from the JSONL cache.
   Rewrites the file excluding matching entries."
  (unless (probe-file *jsonl-cache-path*)
    (return-from jsonl-cache-delete nil))
  (let ((temp-path (format nil "~A.~A.tmp" *jsonl-cache-path* (get-internal-real-time)))
        (deleted 0))
    (with-open-file (in *jsonl-cache-path* :direction :input :external-format :utf-8)
      (with-open-file (out temp-path :direction :output :if-exists :supersede :external-format :utf-8)
        (loop for line = (read-line in nil nil)
              while line
              do (handler-case
                     (let ((data (read-from-string line)))
                       (if (string= (getf data :ast-hash) hash)
                           (incf deleted)
                           (write-string (format nil "~A~%" line) out)))
                   (error ()
                     (write-string (format nil "~A~%" line) out))))))
    (when (> deleted 0)
      (rename-file temp-path *jsonl-cache-path*))
    deleted))

;; ————————————————————————————————————————————————————————————————————
;; JSON helpers — value-to-json handles all types correctly
;; ————————————————————————————————————————————————————————————————————

(defun %json-escape (s)
  "Escape a string for JSON: wrap in quotes, escape internal quotes and backslashes."
  (format nil "\"~A\""
          (with-output-to-string (out)
            (loop for c across (princ-to-string s)
                  do (case c
                       (#\" (write-string "\\\"" out))
                       (#\\ (write-string "\\\\" out))
                       (#\newline (write-string "\\n" out))
                       (#\return (write-string "\\r" out))
                       (#\tab (write-string "\\t" out))
                       (t (write-char c out)))))))

(defun %value-to-json (val)
  "Convert any Lisp value to its JSON representation."
  (typecase val
    (null "null")
    (string (%json-escape val))
    (keyword (%json-escape (string-downcase (symbol-name val))))
    (integer (format nil "~D" val))
    (float (format nil "~A" val))
    (cons
     (if (keywordp (car val))
         ;; plist — alternating keywords and values
         (let (parts)
           (loop for (k v) on val by #'cddr
                 do (push (format nil "~S: ~A"
                                  (string-downcase (symbol-name k))
                                  (%value-to-json v))
                          parts))
           (format nil "{~{~A~^, ~}}" (nreverse parts)))
         ;; value list — JSON array (handle dotted pairs for alist entries)
         (if (listp (cdr val))
             (format nil "[~{~A~^, ~}]" (mapcar #'%value-to-json val))
             ;; dotted pair like (op . count)
             (format nil "[~A, ~A]" (%value-to-json (car val)) (%value-to-json (cdr val))))))
    (t (%json-escape (princ-to-string val)))))

(defun plist-to-json (plist)
  "Convert a plist to a JSON string. Wrapper around %value-to-json."
  (if (null plist)
      "{}"
      (%value-to-json plist)))

;; ————————————————————————————————————————————————————————————————————
;; Neon persistence (via Python bridge — stdin JSON, stdout s-expr)
;; ————————————————————————————————————————————————————————————————————

(defun %call-python (subcommand &rest args)
  "Call telemetry_logger.py with a subcommand and string args.
   Returns the stdout string, or NIL on error/timeout."
  (let ((cmd (list* *python-executable*
                    "v9/telemetry/telemetry_logger.py"
                    subcommand
                    (loop for (k v) on args by #'cddr
                          collect (format nil "--~A" (string-downcase (symbol-name k)))
                          collect (princ-to-string v)))))
    (handler-case
        (sb-ext:with-timeout 10.0
          (uiop:run-program cmd :output :string :ignore-error-status t))
      (sb-ext:timeout ()
        (format t "[LSMA STORAGE TIMEOUT] Python ~A hung within 10s~%" subcommand)
        nil)
      (error (e)
        (format t "[LSMA STORAGE ERROR] ~A~%" e)
        nil))))

(defun %call-python-with-stdin (subcommand stdin-json &rest args)
  "Call telemetry_logger.py, piping stdin-json via stdin.
   Avoids shell quoting issues for complex AST expressions."
  (let ((cmd (list* *python-executable*
                    "v9/telemetry/telemetry_logger.py"
                    subcommand
                    (loop for (k v) on args by #'cddr
                          collect (format nil "--~A" (string-downcase (symbol-name k)))
                          collect (princ-to-string v)))))
    (handler-case
        (sb-ext:with-timeout 10.0
          (uiop:run-program cmd :input stdin-json :output :string :ignore-error-status t))
      (sb-ext:timeout ()
        (format t "[LSMA STORAGE TIMEOUT] Python ~A hung within 10s~%" subcommand)
        nil)
      (error (e)
        (format t "[LSMA STORAGE ERROR] ~A~%" e)
        nil))))

(defun %s-expr->passport-plist (s-expr)
  "Parse a Lisp s-expression passport plist string into a plist."
  (handler-case
      (let ((data (read-from-string s-expr)))
        (when (listp data)
          (list :ast-hash (getf data :ast-hash)
                :ast-str (getf data :ast-str "")
                :adf-symbol (getf data :adf-symbol)
                :operator-profile (getf data :operator-profile)
                :domains (getf data :domains)
                :subtree-hashes (getf data :subtree-hashes)
                :depth-profile (getf data :depth-profile)
                :usage-count (getf data :usage-count 0)
                :success-count (getf data :success-count 0)
                :failure-count (getf data :failure-count 0)
                :lineage (getf data :lineage)
                :fitness-scores (getf data :fitness-scores)
                :freshness (getf data :freshness "")
                :created-at (getf data :created-at)
                :updated-at (getf data :updated-at))))
    (error () nil)))

(defun %s-expr->passport-list (s-expr)
  "Parse a Lisp s-expression containing a list of passport plists."
  (handler-case
      (let ((data (read-from-string s-expr)))
        (when (listp data)
          (mapcar #'%s-expr->passport-plist data)))
    (error () nil)))

(defun upsert-passport-to-neon (passport &key (adf-symbol nil))
  "UPSERT a passport into Neon logos_knowledge via stdin JSON.
   Passport is a plist; serialized to JSON and piped to Python."
  (let* ((hash (getf passport :ast-hash))
         (ast-str (or (getf passport :ast-str) ""))
         (passport-json (plist-to-json passport))
         ;; Build a JSON payload with ast as a proper JSON string value
         (payload (format nil "{\"ast\": ~A, \"passport\": ~A}"
                          (if (string= ast-str "")
                              "null"
                              (%json-escape ast-str))
                          passport-json))
         (output (%call-python-with-stdin "save-knowledge" payload
                                          :ast-hash hash
                                          :adf-symbol (or adf-symbol ""))))
    (and output (search "\"saved\"" output) t)))

(defun load-passport-by-hash-from-neon (hash)
  "Fetch a single passport by ast_hash from Neon. Returns plist or NIL."
  (let ((output (%call-python "fetch-knowledge-by-hash" :ast-hash hash)))
    (when (and output
               (not (string= (string-trim '(#\space #\tab #\newline) output) "nil")))
      (%s-expr->passport-plist output))))

(defun load-passports-by-domain-from-neon (domain)
  "Fetch all passports for a domain from Neon. Returns list of plists."
  (let ((output (%call-python "fetch-knowledge-by-domain" :domain domain)))
    (when output
      (%s-expr->passport-list output))))

(defun load-all-passports-from-neon (&key (limit nil))
  "Fetch all passports from Neon. Returns list of plists."
  (let* ((args (if limit (list :limit (princ-to-string limit)) nil))
         (output (apply #'%call-python "fetch-knowledge-all" args)))
    (when output
      (%s-expr->passport-list output))))

;; ————————————————————————————————————————————————————————————————————
;; High-level two-layer API
;; ————————————————————————————————————————————————————————————————————

(defun save-passport (passport &key (to-neon nil) (adf-symbol nil))
  "Save a passport plist.
   Always writes to JSONL cache. Optionally writes to Neon.
   When ADF-SYMBOL is provided, associates the passport with an ADF symbol."
  (jsonl-cache-write passport :dedup t)
  (when to-neon
    (upsert-passport-to-neon passport :adf-symbol adf-symbol))
  passport)

(defun load-passport-by-hash (hash &key (from-neon nil))
  "Load a single passport by ast_hash.
   JSONL cache first, Neon fallback (when from-neon is T)."
  (let ((cached (car (jsonl-cache-read :hash hash))))
    (or cached
        (when from-neon
          (load-passport-by-hash-from-neon hash)))))

(defun load-passports-by-domain (domain &key (from-neon nil))
  "Load all passports for a domain.
   JSONL cache first, merged with Neon if requested."
  (let ((results (jsonl-cache-read :domain domain)))
    (when from-neon
      (let ((neon-rows (load-passports-by-domain-from-neon domain)))
        (dolist (nr neon-rows)
          (let ((h (getf nr :ast-hash)))
            (unless (find h results :key (lambda (r) (getf r :ast-hash)) :test #'string=)
              (push nr results))))))
    results))

(defun load-all-passports (&key (from-neon nil))
  "Load all passports. From JSONL cache, optionally merged with Neon."
  (let ((results (jsonl-cache-read)))
    (when from-neon
      (let ((neon-rows (load-all-passports-from-neon)))
        (dolist (nr neon-rows)
          (let ((h (getf nr :ast-hash)))
            (unless (find h results :key (lambda (r) (getf r :ast-hash)) :test #'string=)
              (push nr results))))))
    results))

(defun count-passports (&key (from-neon nil))
  "Count total passports in storage."
  (if from-neon
      (length (load-all-passports-from-neon))
      (length (load-all-passports))))

;; ————————————————————————————————————————————————————————————————————
;; passport->adf — reconstruct ADF entry from storage row
;; ————————————————————————————————————————————————————————————————————

(defvar *adf-prefix* "ADF"
  "Default prefix for auto-generated ADF symbols.")

(defvar *adf-counter* 0
  "Global counter for auto-generated ADF symbols.")

(defun next-adf-symbol (&optional (prefix *adf-prefix*))
  "Generate the next unique ADF symbol: ADF-1, ADF-2, ..."
  (intern (format nil "~A-~D" prefix (incf *adf-counter*))))

(defun passport->adf (passport-plist)
  "Reconstruct an ADF entry (adf-symbol . ast) from a passport plist.
   Returns (values adf-symbol ast passport-plist).
   If passport has an :adf-symbol, uses it; otherwise generates a new one."
  (let* ((adf-sym (or (getf passport-plist :adf-symbol)
                      (next-adf-symbol)))
         (ast-str (getf passport-plist :ast-str ""))
         (ast (handler-case (read-from-string ast-str)
                (error () nil))))
    (when ast
      (values adf-sym ast passport-plist))))

(defun batch-passports->adfs (passport-plists)
  "Convert a list of passport plists into an alist of (adf-symbol . ast).
   Skips entries with unparseable ASTs."
  (let (results)
    (dolist (p passport-plists)
      (multiple-value-bind (sym ast)
          (passport->adf p)
        (when ast
          (push (cons sym ast) results))))
    (nreverse results)))

(defun register-passport-as-adf (passport &key (to-neon nil))
  "Save a passport and register it as an ADF in *adf-library*.
   Returns the ADF symbol, or NIL if AST could not be parsed."
  (let* ((sym (next-adf-symbol))
         (ast-str (getf passport :ast-str ""))
         (ast (handler-case (read-from-string ast-str)
                (error () nil))))
    (when ast
      (let ((augmented (list* :adf-symbol (symbol-name sym) passport)))
        (save-passport augmented :to-neon to-neon :adf-symbol (symbol-name sym))
        ;; Push into cognitive-engine's *adf-library*
        (let ((lib-sym (ignore-errors
                         (find-symbol (string '*adf-library*)
                                      (find-package :cognitive-engine)))))
          (when lib-sym
            (setf (symbol-value lib-sym)
                  (cons (cons sym ast) (symbol-value lib-sym)))))
        sym))))
