(in-package :cognitive-engine)

(defvar *adf-counter* 0)

(defun next-adf-symbol (prefix)
  (intern (format nil "~A-~D" prefix (incf *adf-counter*))))

(defun ast-hash (ast)
  (sxhash (format nil "~A" ast)))

(defun initialize-knowledge-base (&key (min-fitness 0.9) (keep-existing nil))
  "Fetches knowledge from the persistent Neon DB and integrates it into the engine."
  (format t "--- Initializing Persistent Knowledge Base ---~%")
  (unless keep-existing
    (setf *discovered-axioms* nil))
  (let ((knowledge (fetch-telemetry-knowledge :min-fitness min-fitness)))
    (if knowledge
        (let ((asts (getf knowledge :asts))
              (axioms (getf knowledge :axioms))
              (new-adf-count 0)
              (new-axiom-count 0)
              (seen-hashes (if keep-existing
                               (mapcar #'ast-hash (mapcar #'cdr *adf-library*))
                               nil)))

          (dolist (ast-str asts)
            (let ((ast (handler-case (read-from-string ast-str) (error () nil))))
              (when ast
                (let ((hash (ast-hash ast)))
                  (unless (member hash seen-hashes)
                    (push hash seen-hashes)
                    (let ((adf-sym (next-adf-symbol "DB-ADF")))
                      (push (cons adf-sym ast) *adf-library*)
                      (incf new-adf-count)))))))

          (dolist (axiom axioms)
            (unless (member axiom *discovered-axioms* :test #'string-equal)
              (push axiom *discovered-axioms*)
              (incf new-axiom-count)))

          (format t "[KNOWLEDGE BASE] Loaded ~D new ADFs and ~D new Axioms from DB.~%"
                  new-adf-count new-axiom-count)
          (format t "[KNOWLEDGE BASE] Total Weights (ADFs + Axioms): ~D~%"
                  (+ (length *adf-library*) (length *discovered-axioms*)))

          (log-telemetry "knowledge_base_initialized"
                         (format nil "Loaded ~D ADFs and ~D axioms from Neon"
                                 (length *adf-library*) (length *discovered-axioms*))
                         :payload-plist (list :total_weights (+ (length *adf-library*) (length *discovered-axioms*))
                                              :new_adfs new-adf-count
                                              :new_axioms new-axiom-count)))
      (format t "[KNOWLEDGE BASE] No persistent knowledge found or DB unreachable.~%"))))
