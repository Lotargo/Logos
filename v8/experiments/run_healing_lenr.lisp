(require :asdf)

(defpackage :cognitive-engine (:use :cl))
(in-package :cognitive-engine)

(defvar *is-cli* t)
(defvar *current-dataset* nil)
(defvar *regression-vars* nil)

(load "v8/src/engine.lisp")

(defun run-healing-lenr ()
  (format t "Starting Theory Healing and Meta-Evolution...~%")

  (with-open-file (*standard-output* "v8/experiments/healing_lenr.log"
                                     :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create)

    (format t "========================================================~%")
    (format t "THEORY HEALING: DISCOVERING A UNIVERSAL LENR FORMULA~%")
    (format t "========================================================~%")
    (format t "Input dataset contains both stable resonance and micro-fractures.~%")
    (format t "Engine is tasked to find a universal AST that heals previous vulnerabilities.~%~%")

    (setf *regression-vars* '(T F C))
    (setf *current-dataset* "v8/data/healing_lenr_data.csv")

    (let ((*current-operators* '(+ - * / sin cos exp sqr sqrt deriv int info_bound entropy seq matrix row))
          (*current-constants* '(0.0 1.0 10.0 -1.0 1000.0 -1000.0)))

      ;; Neutral starting AST, forcing the engine to build the healed formula from scratch
      (run-engine-parallel '(* T F) :regression 100 4))

    (format t "~%========================================================~%")
    (format t "HEALING EXPERIMENT COMPLETED~%")
    (format t "========================================================~%"))

  (format t "Healing test complete. Results saved to v8/experiments/healing_lenr.log~%"))

(run-healing-lenr)