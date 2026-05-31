(require :asdf)

(defpackage :cognitive-engine (:use :cl))
(in-package :cognitive-engine)

(defvar *is-cli* t)
(defvar *current-dataset* nil)
(defvar *regression-vars* nil)

(load "v9/src/engine.lisp")

(defun run-lenr-experiment ()
  (format t "Starting Theoretical Verification of Cold Fusion (LENR)...~%")

  (with-open-file (*standard-output* "v9/experiments/lenr_results.log"
                                     :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create)

    (format t "========================================================~%")
    (format t "EXPERIMENT 1: QUANTUM TUNNELING WITH ELECTRON SCREENING~%")
    (format t "========================================================~%")
    (format t "Searching for AST to maximize P_tunnel despite V > E~%~%")

    (setf *regression-vars* '(E V L S))
    (setf *current-dataset* "v9/data/tunneling_data.csv")
    (let ((*current-operators* '(+ - * / sin cos exp sqr sqrt deriv int))
          (*current-constants* '(1.0 2.0 0.5 -1.0 -2.0)))
      ;; Neutral starting AST
      (run-engine-parallel '(* E 1.0) :regression 100 4))

    (format t "~%========================================================~%")
    (format t "EXPERIMENT 2: PHONON RESONANCE IN PALLADIUM LATTICE~%")
    (format t "========================================================~%")
    (format t "Searching for thermodynamic/acoustic coupling AST~%~%")

    (setf *regression-vars* '(F T M))
    (setf *current-dataset* "v9/data/phonon_resonance.csv")
    (let ((*current-operators* '(+ - * / sin cos exp sqr deriv int carnot entropy))
          (*current-constants* '(1.0 10.0 100.0 1000.0 -1.0)))
      ;; Neutral starting AST
      (run-engine-parallel '(+ F T) :regression 100 4))

    (format t "~%========================================================~%")
    (format t "EXPERIMENT COMPLETED SUCCESSFULLY~%")
    (format t "========================================================~%"))

  (format t "Experiment complete. Results saved to v9/experiments/lenr_results.log~%"))

(run-lenr-experiment)