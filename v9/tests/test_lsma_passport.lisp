(require :asdf)
(defpackage :test-lsma (:use :cl))
(in-package :test-lsma)

(defvar *pass* 0)
(defvar *fail* 0)

(defmacro deftest (name &body body)
  `(progn
     (format t "  [TEST] ~A...~%" ,(string name))
     (let ((result (handler-case (progn ,@body)
                     (error (e) (format t "    ERROR: ~A~%" e) nil))))
       (if result
           (progn (incf *pass*) (format t "    PASS~%"))
           (progn (incf *fail*) (format t "    FAIL~%"))))))

(format t "~%=== LSMA Passport Tests ===~%~%")

;; Load LSMA modules directly (skip engine.lisp to avoid auto-running main())
(load "v9/src/lsma/package.lisp")
(load "v9/src/lsma/passport.lisp")

;; Create a minimal cognitive-engine package for tests that reference it
(unless (find-package :cognitive-engine)
  (defpackage :cognitive-engine (:use :cl)))
(setf (symbol-value (intern "*UNIFIED-VARIABLES*" :cognitive-engine))
      '(x y z t q1 q2 q3))

;; Load storage (needs cognitive-engine package defined above)
(load "v9/src/lsma/storage.lisp")

;; ————————————————————————————————————————————————————————————————————
;; Test 1: Variable canonicalization
;; ————————————————————————————————————————————————————————————————————
(deftest canonicalize-variables-renames-to-vn
  (let* ((ast '(+ x (* y z)))
         (canon (lsma:canonicalize-variables ast)))
    (equal canon '(+ V0 (* V1 V2)))))

(deftest canonicalize-variables-consistent
  (let* ((ast1 '(+ x y))
         (ast2 '(+ a b))
         (c1 (lsma:canonicalize-variables ast1))
         (c2 (lsma:canonicalize-variables ast2)))
    (equal c1 c2)))

(deftest canonicalize-variables-reuses-existing
  (let* ((ast '(+ x (* x y)))
         (canon (lsma:canonicalize-variables ast)))
    (equal canon '(+ V0 (* V0 V1)))))

(deftest canonicalize-variables-preserves-quote
  (let* ((ast (list '+ (list 'quote (list '+ 'x 'y)) (list '+ 'x 'y)))
         (canon (lsma:canonicalize-variables ast)))
    (and (equal (first canon) '+)
         (equal (second canon) (list 'quote (list '+ 'x 'y)))
         (equal (third canon) (list '+ 'v0 'v1)))))

;; ————————————————————————————————————————————————————————————————————
;; Test 2: Constant canonicalization
;; ————————————————————————————————————————————————————————————————————
(deftest canonicalize-constants-rounds-floats
  (let* ((ast '(+ 1.23456789 2.0))
         (canon (lsma:canonicalize-constants ast)))
    (equal canon '(+ 1.234568 2.0))))

;; ————————————————————————————————————————————————————————————————————
;; Test 3: Canonical AST (combined)
;; ————————————————————————————————————————————————————————————————————
(deftest canonical-ast-combined
  (let* ((ast '(+ x (* 1.23456789 y)))
         (canon (lsma:canonical-ast ast)))
    (equal canon '(+ V0 (* 1.234568 V1)))))

;; ————————————————————————————————————————————————————————————————————
;; Test 4: Canonical hash is deterministic
;; ————————————————————————————————————————————————————————————————————
(deftest canonical-hash-deterministic
  (let* ((ast '(+ x (* y z)))
         (h1 (lsma:canonical-ast-hash ast))
         (h2 (lsma:canonical-ast-hash ast)))
    (string= h1 h2)))

(deftest canonical-hash-structural-equality
  (let* ((ast1 '(+ x (* y z)))
         (ast2 '(+ a (* b c)))
         (h1 (lsma:canonical-ast-hash ast1))
         (h2 (lsma:canonical-ast-hash ast2)))
    (string= h1 h2)))

(deftest canonical-hash-different-structures-differ
  (let* ((ast1 '(+ x y))
         (ast2 '(* x y))
         (h1 (lsma:canonical-ast-hash ast1))
         (h2 (lsma:canonical-ast-hash ast2)))
    (not (string= h1 h2))))

;; ————————————————————————————————————————————————————————————————————
;; Test 5: AST structural equality
;; ————————————————————————————————————————————————————————————————————
(deftest ast-structural-equal-true
  (lsma:ast-structural-equal-p '(+ x y) '(+ a b)))

(deftest ast-structural-equal-false
  (not (lsma:ast-structural-equal-p '(+ x y) '(sin x))))

;; ————————————————————————————————————————————————————————————————————
;; Test 6: Operator profile
;; ————————————————————————————————————————————————————————————————————
(deftest operator-profile-counts
  (let* ((ast '(+ x (* y (+ z 1))))
         (profile (lsma:extract-operator-profile ast)))
    (and (= (cdr (assoc '+ profile)) 2)
         (= (cdr (assoc '* profile)) 1))))

;; ————————————————————————————————————————————————————————————————————
;; Test 7: Subtree hashes
;; ————————————————————————————————————————————————————————————————————
(deftest subtree-hashes-include-root
  (let* ((ast '(+ x y))
         (hashes (lsma:extract-subtree-hashes ast)))
    (not (null hashes))))

(deftest subtree-hashes-capped
  (let* ((ast '(+ (sin (mul x (cos (h y)))) (mul z (h y))))
         (hashes (lsma:extract-subtree-hashes ast :limit 5)))
    (<= (length hashes) 5)))

;; ————————————————————————————————————————————————————————————————————
;; Test 8: Depth profile
;; ————————————————————————————————————————————————————————————————————
(deftest depth-profile-root-is-0
  (let* ((ast '(+ x y))
         (profile (lsma:extract-depth-profile ast)))
    (string= "0" (car (first profile)))))

(deftest depth-profile-nesting
  (let* ((ast '(+ (* x y) z))
         (profile (lsma:extract-depth-profile ast)))
    (some (lambda (entry)
            (and (string= "0.0" (car entry)) (= 1 (cadr entry))))
          profile)))

;; ————————————————————————————————————————————————————————————————————
;; Test 9: Extract passport
;; ————————————————————————————————————————————————————————————————————
(deftest passport-has-all-keys
  (let* ((ast '(+ x (sin y)))
         (passport (lsma:extract-passport ast :domain :test)))
    (and (getf passport :ast-hash)
         (getf passport :subtree-hashes)
         (getf passport :operator-profile)
         (getf passport :depth-profile)
         (getf passport :domains)
         (getf passport :usage-count)
         (getf passport :freshness))))

(deftest passport-hash-matches
  (let* ((ast '(+ x y))
         (passport (lsma:extract-passport ast :domain :test))
         (direct-hash (lsma:canonical-ast-hash ast)))
    (string= (getf passport :ast-hash) direct-hash)))

;; ————————————————————————————————————————————————————————————————————
;; Test 10: JSONL cache round-trip
;; ————————————————————————————————————————————————————————————————————
(deftest jsonl-cache-round-trip
  (let* ((ast '(+ x 1))
         (passport (lsma:extract-passport ast :domain :test-domain))
         (hash (getf passport :ast-hash)))
    (setf (getf passport :ast-str) "(+ x 1)")
    ;; Write and read back
    (lsma::jsonl-cache-write passport)
    (let* ((loaded (car (lsma::jsonl-cache-read :hash hash))))
      (and loaded
           (string= (getf loaded :ast-hash) hash)))))

;; ————————————————————————————————————————————————————————————————————
;; Summary
;; ————————————————————————————————————————————————————————————————————
(format t "~%=== LSMA Passport Tests Complete ===~%")
(format t "  Passed: ~D  Failed: ~D  Total: ~D~%" *pass* *fail* (+ *pass* *fail*))
(if (> *fail* 0)
    (format t "  *** SOME TESTS FAILED ***~%")
    (format t "  All tests passed.~%"))
