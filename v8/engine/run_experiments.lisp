(require :asdf)

(load "v8/engine/engine.lisp")

(defpackage :cognitive-engine-experiments (:use :cl))
(in-package :cognitive-engine-experiments)

(defun set-dataset (file)
  ;; Directly use run-program to inject the dynamic assertion before running engine
  ;; Replace slashes with pipes in sed so it doesn't break the expression
  (uiop:run-program (format nil "sed -i \"s|active_dataset('.*').|active_dataset('~A').|g\" v8/engine/regression.pl" file)))

(defun run-and-log (name ast domain iterations file)
  (with-open-file (stream file :direction :output :if-exists :supersede :if-does-not-exist :create)
    (format stream "=== EXPERIMENT: ~A ===~%" name)
    (format stream "Base AST: ~A~%" ast)
    (format stream "Domain: ~A~%" domain)
    (format stream "Iterations: ~D~%" iterations)
    (format stream "----------------------------------------~%")

    ;; Redirect standard output to both console and file
    (let ((*standard-output* (make-broadcast-stream *standard-output* stream)))
      (cognitive-engine::run-engine-parallel ast domain iterations 4))
    (format stream "----------------------------------------~%")
    (format stream "EXPERIMENT COMPLETED.~%")))

;; Run Experiment 1
(format t "Starting Experiment 1...~%")
(set-dataset "v8/engine/gravity_data.csv")
(run-and-log "Experiment 1: Ideal Formula (Confirmation)"
             '(div (mul m1 m2) (mul r r))
             :regression
             5
             "v8/experiments/empirical_discovery/experiment_1_ideal.txt")

;; Run Experiment 2
(format t "Starting Experiment 2...~%")
(set-dataset "v8/engine/gravity_data.csv")
(run-and-log "Experiment 2: Broken Formula (Healing)"
             '(div (mul m1 m2) r)
             :regression
             800
             "v8/experiments/empirical_discovery/experiment_2_healing.txt")

;; Run Experiment 3: Paradigm Shift (Anomaly Data)
(format t "Starting Experiment 3...~%")
(set-dataset "v8/engine/anomaly_data.csv")
(run-and-log "Experiment 3: Paradigm Shift (Anomaly)"
             '(add m1 m2)
             :regression
             500
             "v8/experiments/empirical_discovery/experiment_3_paradigm_shift.txt")
