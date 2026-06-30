(require :asdf)
(defpackage :test-lsma-smoke (:use :cl))
(in-package :test-lsma-smoke)

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

(format t "~%=== LSMA Integration Smoke Tests ===~%~%")

;; ──────────────────────────────────────────────────────────────────
;; 1. Bootstrap: create minimal cognitive-engine environment
;; ──────────────────────────────────────────────────────────────────
(unless (find-package :cognitive-engine)
  (defpackage :cognitive-engine (:use :cl)))
(in-package :cognitive-engine)
(defvar *adf-library* nil
  "In-memory library of (adf-symbol . ast) pairs.")
(defvar *unified-variables* nil
  "Shared variable pool used by LSMA canonicalization.")
;; Use symbols in the test package so AST forms read in test-lsma-smoke match
(setf *unified-variables*
      (loop for s in '(x y z t q1 q2 q3)
            collect (intern (string s) :test-lsma-smoke)))
(in-package :test-lsma-smoke)

;; ──────────────────────────────────────────────────────────────────
;; 2. Load all LSMA modules (new load order with package.lisp)
;; ──────────────────────────────────────────────────────────────────
(format t "Loading LSMA modules...~%")
(load "v9/src/lsma/package.lisp")
(load "v9/src/lsma/passport.lisp")
(load "v9/src/lsma/storage.lisp")
(load "v9/src/lsma/selection.lisp")
(load "v9/src/lsma/eviction.lisp")
(format t "  done.~%~%")

(defvar *sample-ast* '(+ (* x y) (sin z)))
(defvar *sample-ast2* '(* (+ a b) (- c d)))
(defvar *sample-ast3* '(+ 1 2))

;; ──────────────────────────────────────────────────────────────────
;; 3. Passport core (basic sanity — full tests in test_lsma_passport)
;; ──────────────────────────────────────────────────────────────────
(deftest passport-extraction-works
  (let ((p (lsma:extract-passport *sample-ast* :domain :math)))
    (and (getf p :ast-hash)
         (getf p :operator-profile)
         (getf p :subtree-hashes))))

(deftest canonical-hash-deterministic
  (string= (lsma:canonical-ast-hash *sample-ast*)
           (lsma:canonical-ast-hash *sample-ast*)))

(deftest structural-equality-renamed-vars
  (lsma:ast-structural-equal-p '(+ x y) '(+ a b)))

(deftest structural-inequality-different-ops
  (not (lsma:ast-structural-equal-p '(+ x y) '(* x y))))

;; ──────────────────────────────────────────────────────────────────
;; 4. Storage / ADF registration
;; ──────────────────────────────────────────────────────────────────
(deftest next-adf-symbol-generates
  (let* ((s1 (lsma:next-adf-symbol "TEST"))
         (s2 (lsma:next-adf-symbol "TEST")))
    (and (symbolp s1)
         (symbolp s2)
         (not (eq s1 s2)))))

(deftest full-pipeline-extract-register
  (let* ((passport (lsma:extract-passport *sample-ast* :domain :math)))
    (setf (getf passport :ast-str) "(+ (* x y) (sin z))")
    (let ((sym (lsma:register-passport-as-adf passport)))
      (and sym
           (assoc sym cognitive-engine::*adf-library* :test #'eq)))))

(deftest register-second-adf
  (let* ((passport (lsma:extract-passport *sample-ast2* :domain :math)))
    (setf (getf passport :ast-str) "(* (+ a b) (- c d))")
    (let ((sym (lsma:register-passport-as-adf passport)))
      (and sym
           (= (length cognitive-engine::*adf-library*) 2)))))

(deftest save-and-load-passport-round-trip
  (let* ((ast '(+ v0 42))
         (p (lsma:extract-passport ast :domain :test-domain))
         (hash (getf p :ast-hash)))
    (setf (getf p :ast-str) "(+ v0 42)")
    (lsma::jsonl-cache-write p)
    (let* ((loaded (car (lsma::jsonl-cache-read :hash hash))))
      (and loaded
           (string= (getf loaded :ast-hash) hash)))))

(deftest load-all-passports
  (let ((all (lsma:load-all-passports)))
    (listp all)))

;; ──────────────────────────────────────────────────────────────────
;; 5. ADF Scoring
;; ──────────────────────────────────────────────────────────────────
(deftest historical-success-neutral-new
  (let ((p (list :success-count 0 :failure-count 0)))
    (= (lsma::historical-success p) 0.5)))

(deftest historical-success-half
  (let ((p (list :success-count 5 :failure-count 5)))
    (= (lsma::historical-success p) 0.5)))

(deftest historical-success-all-success
  (let ((p (list :success-count 10 :failure-count 0)))
    (= (lsma::historical-success p) 1.0)))

(deftest failure-penalty-50pct
  (let ((p (list :success-count 5 :failure-count 5)))
    (= (lsma::failure-penalty p) 0.5)))

(deftest failure-penalty-no-failures
  (let ((p (list :success-count 10 :failure-count 0)))
    (= (lsma::failure-penalty p) 0.0)))

(deftest novelty-bonus-high-for-new
  (let ((p (list :usage-count 0)))
    (> (lsma::novelty-bonus p) 0.9)))

(deftest novelty-bonus-low-for-used
  (let ((p (list :usage-count 100)))
    (< (lsma::novelty-bonus p) 0.6)))

(deftest bloat-penalty-small-ast
  (let ((p (list :ast-str "(+ x y)")))
    (< (lsma::bloat-penalty p) 0.1)))

(deftest domain-affinity-match
  (= (lsma::domain-affinity (list :domains '(:math)) :math) 1.0))

(deftest domain-affinity-no-match
  (= (lsma::domain-affinity (list :domains '(:physics)) :math) 0.1))

(deftest operator-affinity-50pct
  (let ((p (list :operator-profile '((+ . 2) (* . 1)))))
    (> (lsma::operator-affinity p '(+ -)) 0.3)))

;; ──────────────────────────────────────────────────────────────────
;; 6. Composite scoring
;; ──────────────────────────────────────────────────────────────────
(deftest compute-adf-score-in-range
  (let* ((passport (lsma:extract-passport *sample-ast* :domain :math))
         (score (lsma:compute-adf-score passport :domain :math
                                        :candidates (list *sample-ast2*))))
    (and (>= score 0.0) (<= score 1.0))))

(deftest compute-adf-score-better-for-matching-domain
  (let* ((p-math (lsma:extract-passport '(+ x y) :domain :math))
         (p-phys (lsma:extract-passport '(+ x y) :domain :physics))
         (score-math (lsma:compute-adf-score p-math :domain :math
                                             :candidates nil))
         (score-phys (lsma:compute-adf-score p-phys :domain :math
                                             :candidates nil)))
    (>= score-math score-phys)))

;; ──────────────────────────────────────────────────────────────────
;; 7. Selection
;; ──────────────────────────────────────────────────────────────────
(deftest select-adf-from-library
  (let ((ctxt (list :domain :math :op-seq '(+ *) :adf-library cognitive-engine::*adf-library*))
        (candidates (copy-list cognitive-engine::*adf-library*)))
    (let ((chosen (lsma:select-adf candidates ctxt)))
      (or (null candidates) ; empty library → nil is ok
          (and chosen (assoc (car chosen) cognitive-engine::*adf-library* :test #'eq))))))

(deftest select-adf-empty-returns-nil
  (null (lsma:select-adf nil (list :domain :test))))

;; ──────────────────────────────────────────────────────────────────
;; 8. Outcome recording
;; ──────────────────────────────────────────────────────────────────
(deftest record-outcome-success
  (let* ((ast '(/ (* x y) z))
         (p (lsma:extract-passport ast :domain :math)))
    (setf (getf p :ast-str) (format nil "~A" ast))
    (let ((sym (lsma:register-passport-as-adf p)))
      (lsma::jsonl-cache-write p)
      (lsma:record-adf-outcome sym t :domain :math)
      (not (null sym)))))

(deftest record-outcome-failure
  (let* ((ast '(/ (* x y) z))
         (p (lsma:extract-passport ast :domain :math)))
    (setf (getf p :ast-str) (format nil "~A" ast))
    (let ((sym (lsma:register-passport-as-adf p)))
      (lsma::jsonl-cache-write p)
      (lsma:record-adf-outcome sym nil :domain :math)
      (not (null sym)))))

;; ──────────────────────────────────────────────────────────────────
;; 9. Eviction
;; ──────────────────────────────────────────────────────────────────
(deftest compute-utility-score-ranges
  (let* ((p (list :usage-count 5 :success-count 8 :failure-count 2
                  :freshness "2026-07-01T12:00:00Z"))
         (score (lsma:compute-utility-score p)))
    (and (>= score 0.0) (<= score 1.0))))

(deftest find-eviction-candidates-empty-library
  (null (lsma:find-eviction-candidates nil)))

(deftest check-library-size-below-cap
  (multiple-value-bind (exceeded-p size max)
      (lsma:check-library-size :adf-library '((a . (+ 1 2)) (b . (+ 3 4))))
    (and (not exceeded-p) (= size 2) (= max 500))))

(deftest periodic-eviction-keeps-small-library
  (let* ((lib (copy-list cognitive-engine::*adf-library*))
         (evicted (lsma:periodic-eviction lib :domain :math :dry-run t)))
    ;; Should not evict with only 2 entries
    (or (null evicted) (= evicted 0))))

;; ──────────────────────────────────────────────────────────────────
;; Summary
;; ──────────────────────────────────────────────────────────────────
(format t "~%=== LSMA Integration Smoke Tests Complete ===~%")
(format t "  Passed: ~D  Failed: ~D  Total: ~D~%" *pass* *fail* (+ *pass* *fail*))
(if (> *fail* 0)
    (format t "  *** SOME TESTS FAILED ***~%")
    (format t "  All tests passed.~%"))
