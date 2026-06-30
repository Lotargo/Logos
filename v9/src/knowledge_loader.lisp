(in-package :cognitive-engine)

(defun initialize-knowledge-base (&key (min-fitness 0.9))
  "Fetches knowledge from the persistent Neon DB and integrates it into the engine."
  (format t "--- Initializing Persistent Knowledge Base ---~%")
  (let ((knowledge (fetch-telemetry-knowledge :min-fitness min-fitness)))
    (if knowledge
        (let ((asts (getf knowledge :asts))
              (axioms (getf knowledge :axioms))
              (new-adf-count 0)
              (new-axiom-count 0))

          ;; Integrate ASTs as ADFs
          (dolist (ast-str asts)
            (let ((ast (handler-case (read-from-string ast-str) (error () nil))))
              (when ast
                (let ((adf-sym (intern (format nil "DB-ADF-~D" (1+ (length *adf-library*))))))
                  (unless (member ast *adf-library* :key #'cdr :test #'equal)
                    (push (cons adf-sym ast) *adf-library*)
                    (incf new-adf-count))))))

          ;; Integrate Axioms
          (dolist (axiom axioms)
            (unless (member axiom *discovered-axioms* :test #'string-equal)
              (push axiom *discovered-axioms*)
              (incf new-axiom-count)))

          (format t "[KNOWLEDGE BASE] Loaded ~D new ADFs and ~D new Axioms from DB.~%"
                  new-adf-count new-axiom-count)
          (format t "[KNOWLEDGE BASE] Total Weights (ADFs + Axioms): ~D~%"
                  (+ (length *adf-library*) (length *discovered-axioms*)))

          ;; Log the initialization
          (log-telemetry "knowledge_base_initialized"
                         (format nil "Loaded ~D ADFs and ~D axioms from Neon"
                                 (length *adf-library*) (length *discovered-axioms*))
                         :payload-plist (list :total_weights (+ (length *adf-library*) (length *discovered-axioms*))
                                              :new_adfs new-adf-count
                                              :new_axioms new-axiom-count)))
        (format t "[KNOWLEDGE BASE] No persistent knowledge found or DB unreachable.~%"))))
