(in-package :cognitive-engine)

(defvar *meta-evolution-enabled* t)
(defvar *discovered-axioms* nil)
(defvar *invented-op-counter* 0)

(defun extract-unique-variables (ast variables &optional acc)
  "Scans the AST and returns a list of unique variables found within it."
  (cond
    ((null ast) (remove-duplicates acc))
    ((atom ast)
     (if (member ast variables)
         (pushnew ast acc)
         acc))
    ((listp ast)
     (let ((acc-after-car (extract-unique-variables (car ast) variables acc)))
       (extract-unique-variables (cdr ast) variables acc-after-car)))))

(defun generate-random-ast-subtree (depth max-depth)
  "Generates a random AST subtree using current operators, variables, and constants."
  (if (or (>= depth max-depth) (< (random 100) 40))
      ;; Leaf node: return a random variable or constant
      (if (and (boundp '*current-variables*) (boundp '*current-constants*)
               *current-variables* *current-constants*)
          (if (< (random 100) 50)
              (random-element *current-variables*)
              (random-element *current-constants*))
          (if (and (boundp '*current-variables*) *current-variables*)
              (random-element *current-variables*)
              (if (and (boundp '*current-constants*) *current-constants*)
                  (random-element *current-constants*)
                  0)))
      ;; Internal node: select an operator
      (let ((op (if (and (boundp '*current-operators*) *current-operators*)
                    (random-element *current-operators*)
                    'add)))
        (if (member op '(deriv int))
            ;; deriv and int require 2 args: Expr and Var. The second arg must be a variable.
            (list op
                  (generate-random-ast-subtree (1+ depth) max-depth)
                  (if (and (boundp '*current-variables*) *current-variables*)
                      (random-element *current-variables*)
                      'x))
            (cons op (loop repeat (if (member op '(h x_gate y_gate z_gate transpose norm gamma delta_s not sin cos)) 1 2)
                           collect (generate-random-ast-subtree (1+ depth) max-depth)))))))

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
  (let* ((proc (car proc-cell))
         (query (format nil "retract((~A))." rule-str)))
    (handler-case
        (sb-ext:with-timeout 1.0
          (format (uiop:process-info-input proc) "~A~%" query)
          (force-output (uiop:process-info-input proc))
          (let ((response (read-line (uiop:process-info-output proc) nil :eof)))
             t))
      (sb-ext:timeout () nil)
      (error (e) nil))))

(defun meta-mutate-axiom (proc-cell domain current-ast best-penalty check-fn)
  "Dynamically invents a new operation based on a random Lisp subtree, injects it into Prolog, and evaluates it."
  (if *meta-evolution-enabled*
      (let* ((sub-ast (generate-random-ast-subtree 0 3))
             (unique-vars (if (boundp '*current-variables*)
                              (extract-unique-variables sub-ast *current-variables*)
                              nil))
             (new-op-name (intern (format nil "INVENTED_OP_~D" (incf *invented-op-counter*)))))

        ;; If no variables are used, it's just a constant expression, skip inventing a function for it
        (if (null unique-vars)
            (values nil nil nil)
            (let* ((prolog-sub-ast (lisp-to-prolog sub-ast))
                   (prolog-vars (mapcar #'lisp-to-prolog unique-vars))
                   (args-str (format nil "~{~A~^, ~}" prolog-vars))
                   (op-call (format nil "~A(~A)" (string-downcase (symbol-name new-op-name)) args-str))
                   ;; Construct rule
                   (new-axiom (format nil "unified_eval(~A, P) :- unified_eval(~A, P)" op-call prolog-sub-ast)))

              ;; Inject the new axiom
              (inject-prolog-rule proc-cell new-axiom)

              ;; Add to Lisp operators
              (when (boundp '*current-operators*)
                (pushnew new-op-name *current-operators*))

              ;; Create a hypothesis AST using the new operator
              ;; Instead of fully random mutation, we can deliberately insert the new operator
              (let* ((hypothesis (list new-op-name))
                     (hypothesis-ast (append hypothesis unique-vars)) ; Basic insertion
                     (mutated-ast (if (< (random 100) 50)
                                      hypothesis-ast
                                      (mutate current-ast))) ; Sometimes just mutate with new op available
                     (new-penalty (funcall check-fn mutated-ast domain proc-cell :target)))

                (if (< new-penalty best-penalty)
                    (progn
                      (format t "[META-EVOLUTION] Invented and validated new operation! ~A~%" new-axiom)
                      (push new-axiom *discovered-axioms*)
                      (values mutated-ast new-penalty new-axiom))
                    (progn
                      ;; Revert
                      (retract-prolog-rule proc-cell new-axiom)
                      (when (boundp '*current-operators*)
                        (setf *current-operators* (remove new-op-name *current-operators*)))
                      (values nil nil nil)))))))
      (values nil nil nil)))

