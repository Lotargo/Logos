(require :asdf)

(defpackage :cognitive-engine (:use :cl))
(in-package :cognitive-engine)

(defvar *is-cli* t)
(defvar *current-dataset* nil)
(defvar *regression-vars* nil)

(load "v9/src/engine.lisp")

(defun run-poincare-experiment ()
  (format t "Starting Millennium Prize: Poincare Conjecture Experiment...~%")

  (with-open-file (*standard-output* "v9/experiments/poincare_results.log"
                                     :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create)

    (format t "========================================================~%")
    (format t "EXPERIMENT 1: POINCARE CONJECTURE (TOPOLOGICAL INVARIANT)~%")
    (format t "========================================================~%")

    (setf *regression-vars* '(D P1 C B))
    (setf *current-dataset* "v9/data/poincare_data.csv")
    (run-engine-parallel '(or D P1) :regression 100 4)

    (format t "~%========================================================~%")
    (format t "EXPERIMENT 2: RICCI FLOW EQUATION (METRIC EVOLUTION)~%")
    (format t "========================================================~%")

    (setf *regression-vars* '(t g R))
    (setf *current-dataset* "v9/data/ricci_flow.csv")
    (run-engine-parallel '(* 1 t) :regression 100 4)

    (format t "~%========================================================~%")
    (format t "EXPERIMENT COMPLETED SUCCESSFULLY~%")
    (format t "========================================================~%"))

  (format t "Experiment complete. Results saved to v9/experiments/poincare_results.log~%"))

(run-poincare-experiment)