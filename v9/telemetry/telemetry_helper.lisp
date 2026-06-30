(in-package :cognitive-engine)

(defvar *telemetry-session-id* (format nil "session-~A" (get-internal-real-time)))
(defvar *python-executable*
  (or (uiop:getenv "LOGOS_PYTHON")
      #+win32 "C:/Users/etotm/AppData/Local/Programs/Python/Python312/python.exe"
      "python3"))

(defun %json-escape (s)
  (format nil "~S" s))

(defun plist-to-json (plist)
  (if (null plist)
      "{}"
      (let (parts)
        (loop for (key val) on plist by #'cddr
              do (push (format nil "~S: ~A"
                               (string-downcase (symbol-name key))
                               (typecase val
                                 (number (format nil "~A" val))
                                 (string (%json-escape val))
                                 (keyword (%json-escape (string-downcase (symbol-name val))))
                                 (null "null")
                                 (t (if (eq val t) "true" (%json-escape (format nil "~A" val))))))
                       parts))
        (format nil "{~{~A~^, ~}}" (nreverse parts)))))

(defun log-telemetry (event-type message &key (source "lisp_engine") (payload-plist nil))
  (let* ((payload-json (plist-to-json payload-plist))
         (cmd (list *python-executable* "v9/telemetry/telemetry_logger.py" "write-local"
                    "--event-type" event-type
                    "--event-source" source
                    "--session-id" *telemetry-session-id*
                    "--message" message
                    "--payload" payload-json)))
    (handler-case
        (sb-ext:with-timeout 5.0
          (uiop:run-program cmd :ignore-error-status t))
      (sb-ext:timeout ()
        (format t "[TELEMETRY TIMEOUT] Failed to log ~A within 5s~%" event-type))
      (error (e)
        (format t "[TELEMETRY ERROR] ~A~%" e)))))

(defun log-fitness-telemetry (candidate-id fitness-score input-ast output-ast &key (execution-time 0) (error-rate 0))
  (log-telemetry "fitness_evaluated"
                 (format nil "Candidate ~A evaluated with fitness ~,4F" candidate-id fitness-score)
                 :payload-plist (list :candidate_id candidate-id
                                      :fitness_score fitness-score
                                      :input_ast (format nil "~A" input-ast)
                                      :output_ast (format nil "~A" output-ast)
                                      :execution_time_ms execution-time
                                      :error_rate error-rate)))

(defun fetch-telemetry-knowledge (&key (min-fitness 0.9))
  (let* ((cmd (list *python-executable* "v9/telemetry/telemetry_logger.py" "fetch-knowledge-lisp"
                    "--min-fitness" (format nil "~,2F" min-fitness)))
         (output (handler-case
                     (sb-ext:with-timeout 10.0
                       (uiop:run-program cmd :output :string :ignore-error-status t))
                   (sb-ext:timeout ()
                     (format t "[KNOWLEDGE FETCH TIMEOUT] Python hung on fetch within 10s~%")
                     nil)
                   (error () nil))))
    (if output
        (handler-case
            (read-from-string output)
          (error (e)
            (format t "[KNOWLEDGE FETCH ERROR] ~A~%" e)
            nil))
        nil)))
