(require :asdf)
(defpackage :cognitive-engine (:use :cl))
(defparameter cognitive-engine::*is-cli* t)

(load "v8/src/engine.lisp")

(ensure-directories-exist "v8/experiments/empirical_discovery/")

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

;; Run Experiment 4: Schrodinger Equation (Energy)
(format t "Starting Experiment 4: Schrodinger Equation...~%")
(set-dataset "v8/data/schrodinger_data.csv")
(run-and-log "Experiment 4: Schrodinger Equation"
             '(add p v)
             :regression
             800
             "v8/experiments/empirical_discovery/experiment_4_schrodinger.txt")

;; Run Experiment 5: Bekenstein-Hawking Entropy
(format t "Starting Experiment 5: Holographic Entropy...~%")
(set-dataset "v8/data/holographic_entropy_data.csv")
(run-and-log "Experiment 5: Bekenstein-Hawking Entropy"
             '(div a 2)
             :regression
             500
             "v8/experiments/empirical_discovery/experiment_5_entropy.txt")
