(in-package :cognitive-engine)

(defvar *adf-counter* 0)

(defun next-adf-symbol (prefix)
  (intern (format nil "~A-~D" prefix (incf *adf-counter*))))

(defun initialize-knowledge-base (&key (min-fitness 0.9) (keep-existing nil))
  "Fetches knowledge from LSMA passport cache or persistent Neon DB.
   Uses canonical-ast-hash for deduplication.
   Restores passports into ADF library on engine init."
  (format t "--- Initializing Persistent Knowledge Base ---~%")
  (unless keep-existing
    (setf *discovered-axioms* nil))

  ;; Phase 1: Try restoring from local JSONL passport cache first
  (let ((cached-passports (lsma:load-all-passports)))
    (when cached-passports
      (let ((restored-adfs (lsma:batch-passports->adfs cached-passports))
            (loaded-count 0))
        (dolist (entry restored-adfs)
          (let ((hash (lsma:canonical-ast-hash (cdr entry))))
            (unless (and keep-existing
                         (assoc (car entry) *adf-library* :test #'eq))
              (push entry *adf-library*)
              (incf loaded-count))))
        (format t "[KNOWLEDGE BASE] Restored ~D ADFs from passport cache.~%" loaded-count)
        (format t "[KNOWLEDGE BASE] Total Weights (ADFs + Axioms): ~D~%"
                (+ (length *adf-library*) (length *discovered-axioms*)))
        (log-telemetry "knowledge_base_initialized"
                        (format nil "Restored ~D ADFs from passport cache"
                                (length *adf-library*))
                        :payload-plist (list :total_weights (+ (length *adf-library*) (length *discovered-axioms*))
                                             :source "cache"))
        (return-from initialize-knowledge-base)))

  ;; Phase 2: Fall back to Neon DB if no cached passports
  (let ((knowledge (fetch-telemetry-knowledge :min-fitness min-fitness)))
    (if knowledge
        (let ((asts (getf knowledge :asts))
              (axioms (getf knowledge :axioms))
              (new-adf-count 0)
              (new-axiom-count 0)
              (seen-hashes (if keep-existing
                               (mapcar #'lsma:canonical-ast-hash
                                       (mapcar #'cdr *adf-library*))
                               nil)))

          (dolist (ast-str asts)
            (let ((ast (handler-case (read-from-string ast-str) (error () nil))))
              (when ast
                (let ((hash (lsma:canonical-ast-hash ast)))
                  (unless (member hash seen-hashes :test #'string=)
                    (push hash seen-hashes)
                    (let ((adf-sym (next-adf-symbol "DB-ADF")))
                      (push (cons adf-sym ast) *adf-library*)
                      ;; Save LSMA passport for this ADF
                      (let ((passport (lsma:extract-passport ast :domain nil)))
                        (setf (getf passport :ast-str) ast-str)
                        (lsma:save-passport passport))
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
      (format t "[KNOWLEDGE BASE] No persistent knowledge found or DB unreachable.~%")))))
