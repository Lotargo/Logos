(require :asdf)
(defpackage :cognitive-engine (:use :cl))
(defparameter cognitive-engine::*is-cli* t)

(load "v9/src/engine.lisp")

(ensure-directories-exist "v9/experiments/empirical_discovery/")

(defpackage :cognitive-engine-experiments (:use :cl))
(in-package :cognitive-engine-experiments)

(defun set-dataset (file)
  (setf cognitive-engine::*current-dataset* file))

(defun run-and-log (name ast domain iterations file)
  (with-open-file (stream file :direction :output :if-exists :supersede :if-does-not-exist :create)
    (format stream "=== EXPERIMENT: ~A ===~%" name)
    (format stream "Base AST: ~A~%" ast)
    (format stream "Domain: ~A~%" domain)
    (format stream "Iterations: ~D~%" iterations)
    (format stream "----------------------------------------~%")

    ;; Redirect standard output to both console and file
    (let ((*standard-output* (make-broadcast-stream *standard-output* stream)))
      (cognitive-engine::run-engine-parallel ast domain iterations (cognitive-engine::detect-cpu-cores)))
    (format stream "----------------------------------------~%")
    (format stream "EXPERIMENT COMPLETED.~%")))

;; Run Experiment 6: Adversarial Singularity
(format t "Starting Experiment 6: Adversarial Singularity Healing...~%")
(set-dataset "v9/data/adversarial_singularity.csv")

;; We start with standard Newtonian gravity which will crash on R=0
;; The engine MUST discover (div m (add (mul r r) (mul l l))) to survive
(run-and-log "Experiment 6: Adversarial Singularity Healing"
             '(div m (mul r r))
             :regression
             1500
             "v9/experiments/empirical_discovery/experiment_6_singularity.txt")
