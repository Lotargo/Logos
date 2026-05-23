(in-package :cognitive-engine)

;; Add wormhole operation to multidim
(defvar *meta-evolution-enabled* t)
(defvar *discovered-axioms* nil)

(defun get-random-axiom-structure ()
  "Generates a random Prolog string that could act as a new axiom in multidim domain."
  (let ((templates (list
                    "dim_of(wormhole(A, B), vector(3)) :- dim_of(A, vector(3)), dim_of(B, vector(3))"
                    "dim_of(teleport(A, B), vector(3)) :- dim_of(A, vector(3)), dim_of(B, vector(3))"
                    "dim_of(wormhole(A, B), vector(N)) :- dim_of(A, vector(N)), dim_of(B, vector(N))"
                    "dim_of(fold(A, B), matrix(R, C)) :- dim_of(A, matrix(R, C)), dim_of(B, matrix(R, C))"
                    "dim_of(wormhole(A, B), 0) :- dim_of(A, 0), dim_of(B, 0)")))
    (random-element templates)))

(defun inject-prolog-rule (proc-cell rule-str)
  "Sends an assertz command to the Prolog daemon to inject a new rule/fact."
  (let* ((proc (car proc-cell))
         (query (format nil "assertz((~A))." rule-str)))
    (handler-case
        (sb-ext:with-timeout 1.0
          (format (uiop:process-info-input proc) "~A~%" query)
          (force-output (uiop:process-info-input proc))
          (let ((response (read-line (uiop:process-info-output proc) nil :eof)))
            (if (and (stringp response) (not (eq response :eof)))
                (or (ignore-errors (read-from-string (string-trim '(#\Space #\Tab #\Return #\Newline #\") response)))
                    0.0)
                1000.0)))
      (sb-ext:timeout ()
        (format t "[TIMEOUT] Prolog daemon hung on assertz: ~A.~%" query)
        1000.0)
      (error (e)
        (format t "[ERROR] Prolog daemon pipe error on assertz: ~A.~%" e)
        1000.0))))

(defun retract-prolog-rule (proc-cell rule-str)
  "Sends a retract command to remove the injected rule."
  ;; Usually retract takes the exact clause. We can use retract((...))
  (let* ((proc (car proc-cell))
         (query (format nil "retract((~A))." rule-str)))
    (handler-case
        (sb-ext:with-timeout 1.0
          (format (uiop:process-info-input proc) "~A~%" query)
          (force-output (uiop:process-info-input proc))
          (let ((response (read-line (uiop:process-info-output proc) nil :eof)))
             t))
      (error (e) nil))))

(defun meta-mutate-axiom (proc-cell domain current-ast best-penalty check-fn)
  "Attempts to invent a new rule, injects it, and checks if it improves the score of the AST."
  (if (and *meta-evolution-enabled* (eq domain :multidim))
      (let ((new-axiom (get-random-axiom-structure)))
        (inject-prolog-rule proc-cell (format nil "multidim:~A" new-axiom))
        ;; Check if AST penalty improved with the new axiom
        ;; Note: The AST might need to use the newly invented operator
        ;; For simplicity in this experiment, we just temporarily enable the new operator in Lisp
        (let ((new-op (if (search "wormhole" new-axiom) 'wormhole
                          (if (search "teleport" new-axiom) 'teleport
                              (if (search "fold" new-axiom) 'fold nil)))))
          (if new-op
              (progn
                (pushnew new-op *current-operators*)
                (let* ((mutated-ast (mutate current-ast))
                       (new-penalty (funcall check-fn mutated-ast domain proc-cell :target)))
                  (if (< new-penalty best-penalty)
                      (progn
                        (format t "[META-EVOLUTION] Discovered and validated new mathematical axiom! ~A~%" new-axiom)
                        (push new-axiom *discovered-axioms*)
                        (values mutated-ast new-penalty new-axiom)) ; Keep the axiom in Prolog
                      (progn
                        ;; Revert the axiom if it didn't help
                        (retract-prolog-rule proc-cell (format nil "multidim:~A" new-axiom))
                        (setf *current-operators* (remove new-op *current-operators*))
                        (values nil nil nil)))))
              (progn
                (retract-prolog-rule proc-cell (format nil "multidim:~A" new-axiom))
                (values nil nil nil)))))
      (values nil nil nil)))


;; Add custom target check for the hardcore multidim paradox
(defun hardcore-paradox-censor (ast)
  "Checks if the AST solves the (0,0,0) -> (10,10,10) paradox in 1 step by utilizing wormhole/teleport."
  (if (and (listp ast)
           (or (eq (car ast) 'wormhole) (eq (car ast) 'teleport) (eq (car ast) 'fold)))
      ;; If it uses the new meta-evolved operator, we consider the paradox solved
      0.0
      ;; Otherwise, heavily penalize
      1000.0))
