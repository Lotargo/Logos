;;; LSMA Integration Smoke Test — Full Engine Run
;;; Runs run-engine-parallel with minimal iterations to verify the whole pipeline.
;;; Usage: sbcl --script v9/tests/test_integration_smoke.lisp
;;; Prerequisites: SWI-Prolog on PATH, run from repo root F:\Кейс\AGI-lite

(require :asdf)

;; Bootstrap: create cognitive-engine package, suppress engine auto-run
(defpackage :cognitive-engine (:use :cl))
(in-package :cognitive-engine)
(defvar *is-cli* t)

;; Override *current-dataset* to avoid missing-file errors on :regression domain
(defvar *current-dataset* nil)

;; Load the full engine
(load "v9/src/engine.lisp")

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

(format t "~%=== Integration Smoke Test: Full Engine w/ LSMA ===~%~%")

;; ──────────────────────────────────────────────────────────────────
;; Phase 1: Sanity checks before running the engine
;; ──────────────────────────────────────────────────────────────────

(deftest engine-loaded-cleanly
  (and (fboundp 'run-engine-parallel)
       (fboundp 'initialize-knowledge-base)
       (find-package :lsma)))

(deftest adf-library-empty-initially
  (null *adf-library*))

(deftest swipl-available
  (handler-case
      (let ((out (uiop:run-program '("swipl" "-q" "-g" "halt." "-t" "halt.")
                                   :output :string :ignore-error-status t)))
        (stringp out))
    (error () nil)))

;; ──────────────────────────────────────────────────────────────────
;; Phase 2: Short arithmetic run — 10 iterations, 2 threads
;; The arithmetic domain is the simplest: no CSV required.
;; Expects new ADFs to be created and registered in *adf-library*.
;; ──────────────────────────────────────────────────────────────────
(format t "~%Running engine (10 iters, 2 threads, :arithmetic)...~2%")

(defvar *engine-start-library-size* (length *adf-library*))

(multiple-value-bind (winners results)
    (handler-case
        (run-engine-parallel '(+ x 0) :arithmetic 10 2)
      (error (e)
        (format t "ENGINE ERROR: ~A~%" e)
        (values nil nil)))
  (defvar *engine-winners* winners)
  (defvar *engine-results* results))

(deftest engine-returned-results
  *engine-results*)

(deftest engine-produced-winners
  (and *engine-winners* (listp *engine-winners*)))

(deftest adf-library-grew
  (> (length *adf-library*) *engine-start-library-size*))

(deftest adf-library-has-valid-entries
  (every (lambda (entry)
           (and (symbolp (car entry))
                (listp (cdr entry))))
         *adf-library*))

;; ──────────────────────────────────────────────────────────────────
;; Phase 3: Verify ADF passport data was created
;; ──────────────────────────────────────────────────────────────────

(deftest passports-created-in-cache
  (let ((all (ignore-errors (lsma:load-all-passports))))
    (and (listp all) (> (length all) 0))))

(deftest adf-scores-computable
  (every (lambda (entry)
           (let* ((ast (cdr entry))
                  (p (lsma:extract-passport ast :domain :arithmetic)))
             (setf (getf p :ast-str) (format nil "~A" ast))
             (let ((score (lsma:compute-adf-score p :domain :arithmetic
                                                   :candidates (mapcar #'cdr *adf-library*))))
               (and (numberp score) (>= score 0.0) (<= score 1.0)))))
         *adf-library*))

;; ──────────────────────────────────────────────────────────────────
;; Phase 4: Verify selection works on the populated library
;; ──────────────────────────────────────────────────────────────────

(deftest select-adf-from-populated-library
  (let ((chosen (lsma:select-adf *adf-library* (list :domain :arithmetic
                                                      :op-seq '(+)
                                                      :adf-library *adf-library*))))
    (and chosen
         (assoc (car chosen) *adf-library* :test #'eq))))

(deftest eviction-check-on-library
  (multiple-value-bind (exceeded-p size max)
      (lsma:check-library-size :adf-library *adf-library*)
    (declare (ignore exceeded-p max))
    (> size 0)))

;; ──────────────────────────────────────────────────────────────────
;; Summary
;; ──────────────────────────────────────────────────────────────────
(format t "~%=== Integration Smoke Test Complete ===~%")
(format t "  Passed: ~D  Failed: ~D  Total: ~D~%" *pass* *fail* (+ *pass* *fail*))
(format t "  Engine winners: ~D~%" (if *engine-winners* (length *engine-winners*) 0))
(format t "  ADF library size: ~D~%" (length *adf-library*))
(if (> *fail* 0)
    (progn (format t "  *** SOME TESTS FAILED ***~%") (sb-ext:exit :code 1))
    (progn (format t "  All tests passed.~%") (sb-ext:exit :code 0)))
