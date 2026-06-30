(require :asdf)
(defpackage :cognitive-engine (:use :cl))
(defparameter cognitive-engine::*is-cli* t)
(load "v9/src/engine.lisp")

(in-package :cognitive-engine)

(defun run-complexity-experiment (&key (two-phase t))
  (let ((domain :regression)
        (dataset "v9/data/complex_formula.csv")
        (iterations 100)
        (num-threads (detect-cpu-cores)))

    (setf *current-dataset* dataset)
    (setf *regression-vars* '(v1))

    (if two-phase
        (progn
          (format t "--- Phase 1: Component Discovery ---~%")
          (run-engine-parallel '(sin v1) domain 100 num-threads)

          (format t "--- Phase 2: Final Formula Synthesis ---~%")
          (run-engine-parallel '(sin (add v1 v1)) domain iterations num-threads))

        (progn
          (format t "--- Control: One-Shot Search ---~%")
          (run-engine-parallel '(sin v1) domain (+ iterations 100) num-threads)))))

(let ((args sb-ext:*posix-argv*))
  (if (member "--one-shot" args :test #'string=)
      (run-complexity-experiment :two-phase nil)
      (run-complexity-experiment :two-phase t)))
