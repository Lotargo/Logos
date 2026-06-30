(require :asdf)
(defpackage :cognitive-engine (:use :cl))
(defparameter cognitive-engine::*is-cli* t)
(load "v9/src/engine.lisp")

(in-package :cognitive-engine)

(defun run-cross-domain-experiment ()
  (let ((num-threads (detect-cpu-cores)))

    (format t "--- Phase 1: Accumulating Knowledge in Arithmetic ---~%")
    (run-engine-parallel '(mul x (sub 1 x)) :arithmetic 100 num-threads)

    (format t "--- Phase 2: Testing Transfer to Logic ---~%")
    (run-engine-parallel '(and p q) :logic 100 num-threads)

    (format t "--- Phase 3: Testing Transfer to Quantum ---~%")
    (run-engine-parallel '(seq (h q1) (h q2)) :quantum 100 num-threads)))

(run-cross-domain-experiment)
