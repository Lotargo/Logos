(in-package :cognitive-engine)

(defvar *telemetry-session-id* (format nil "session-~A" (get-internal-real-time)))

(defun %escape-json-string (str)
  (with-output-to-string (s)
    (loop for char across (format nil "~A" str) do
      (cond
        ((char= char #\") (write-string "\\\"" s))
        ((char= char #\\) (write-string "\\\\" s))
        ((char= char #\Newline) (write-string "\\n" s))
        (t (write-char char s))))))

(defun log-telemetry (event-type message &key (source "lisp_engine") (payload-plist nil))
  "Calls the Python telemetry logger to record an event. payload-plist is a property list."
  (let* ((payload-json (if payload-plist
                           (with-output-to-string (s)
                             (write-char #\{ s)
                             (loop for (key val) on payload-plist by #'cddr
                                   for first = t then nil
                                   do (unless first (write-string ", " s))
                                      (format s "\"~A\": " (string-downcase (symbol-name key)))
                                      (cond
                                        ((numberp val) (format s "~A" val))
                                        ((or (eq val t) (eq val nil)) (format s "~A" (if val "true" "false")))
                                        (t (format s "\"~A\"" (%escape-json-string val)))))
                             (write-char #\} s))
                           "{}"))
         (cmd (list "python3" "v9/telemetry/telemetry_logger.py" "write-local"
                    "--event-type" event-type
                    "--event-source" source
                    "--session-id" *telemetry-session-id*
                    "--message" message
                    "--payload" payload-json)))
    (handler-case
        (uiop:run-program cmd :ignore-error-status t)
      (error (e)
        (format t "[TELEMETRY ERROR] Failed to log event: ~A~%" e)))))

(defun log-fitness-telemetry (candidate-id fitness-score input-ast output-ast &key (execution-time 0) (error-rate 0))
  "Specific helper for logging fitness evaluation results."
  (log-telemetry "fitness_evaluated"
                 (format nil "Candidate ~A evaluated with fitness ~,4F" candidate-id fitness-score)
                 :payload-plist (list :candidate_id candidate-id
                                      :fitness_score fitness-score
                                      :input_ast (format nil "~A" input-ast)
                                      :output_ast (format nil "~A" output-ast)
                                      :execution_time_ms execution-time
                                      :error_rate error-rate)))

(defun fetch-telemetry-knowledge (&key (min-fitness 0.9))
  "Calls the Python telemetry logger to fetch high-fitness ASTs and axioms."
  (let* ((cmd (list "python3" "v9/telemetry/telemetry_logger.py" "fetch-knowledge"
                    "--min-fitness" (format nil "~,2F" min-fitness)))
         (output (handler-case
                     (uiop:run-program cmd :output :string :ignore-error-status t)
                   (error () nil))))
    (if output
        (handler-case
            (let* ((lisp-format-cmd (list "python3" "-c"
                                         "import sys, json; d = json.loads(sys.stdin.read()); print(f'(:asts ({ \" \".join([\"\\\"\" + str(x).replace(\"\\\"\", \"\\\\\\\"\") + \"\\\"\" for x in d.get(\"asts\", [])]) }) :axioms ({ \" \".join([\"\\\"\" + str(x).replace(\"\\\"\", \"\\\\\\\"\") + \"\\\"\" for x in d.get(\"axioms\", [])]) }))')"))
                   (lisp-str (uiop:run-program lisp-format-cmd :input (make-string-input-stream output) :output :string)))
              (read-from-string lisp-str))
          (error (e)
            (format t "[KNOWLEDGE FETCH ERROR] ~A~%" e)
            nil))
        nil)))
