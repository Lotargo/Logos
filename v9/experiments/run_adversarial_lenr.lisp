(require :asdf)

(defpackage :cognitive-engine (:use :cl))
(in-package :cognitive-engine)

(defvar *is-cli* t)
(defvar *current-dataset* nil)
(defvar *regression-vars* nil)

(load "v9/src/engine.lisp")

(defun run-adversarial-lenr ()
  (format t "Starting Adversarial Falsification (Red Team) for LENR Theory...~%")

  (with-open-file (*standard-output* "v9/experiments/adversarial_lenr.log"
                                     :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create)

    (format t "========================================================~%")
    (format t "RED TEAM ATTACK: EXTREME BOUNDARY CONDITIONS~%")
    (format t "========================================================~%")
    (format t "Attempting to break the hypothesized AST: (- V (INFO_BOUND 0 S))~%")
    (format t "Testing against: Near Absolute Zero, Extreme Plasma, Micro-Fractures, Math Paradoxes~%~%")

    (setf *regression-vars* '(E V L S))
    (setf *current-dataset* "v9/data/extreme_lenr_data.csv")

    ;; We use the exact base operators that derived the formula, plus some adversarial noise injectors
    (let ((*current-operators* '(+ - * / sin cos exp sqr sqrt deriv int info_bound seq matrix row))
          (*current-constants* '(0.0 1.0 10.0 -1.0 1000.0 -1000.0)))

      ;; Start with the "proven" AST from the previous experiment.
      ;; The engine's symbolic regression will attempt to evaluate it against the EXTREME dataset.
      ;; If the formula is robust, it will adapt slightly (or stay stable) and maintain a low penalty.
      ;; If it is brittle, the MSE will explode to infinity or trigger Prolog censorship.
      (run-engine-parallel '(- V (INFO_BOUND 0 S)) :regression 100 4))

    (format t "~%========================================================~%")
    (format t "ADVERSARIAL EXPERIMENT COMPLETED~%")
    (format t "========================================================~%"))

  (format t "Adversarial test complete. Results saved to v9/experiments/adversarial_lenr.log~%"))

(run-adversarial-lenr)