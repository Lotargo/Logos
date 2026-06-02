import re

with open('v7/engine/engine.lisp', 'r') as f:
    content = f.read()

# 1. Structural templates
templates_def = """
(defparameter *structural-templates* (list
  '(seq (h q3) (seq (cnot q2 q3) (h q3)))
  '(seq (t q1) (seq (t q2) (t q3)))
  '(seq (cnot q1 q2) (seq (cnot q2 q3) (cnot q1 q2)))
))
"""

if '*structural-templates*' not in content:
    content = content.replace(';; 2b. Synthesis-Specific Mutation Operators', ';; 2b. Synthesis-Specific Mutation Operators\n' + templates_def)

replace_vars_func = """
(defun instantiate-template (template)
  "Instantiate a structural template by replacing generic qubits with random current ones."
  (cond
    ((null template) nil)
    ((atom template)
     (if (and (symbolp template) (member template '(q1 q2 q3)))
         (if *current-variables* (random-element *current-variables*) template)
         template))
    (t (cons (instantiate-template (car template))
             (instantiate-template (cdr template))))))
"""

if 'instantiate-template' not in content:
    content = content.replace('(defun random-gate ()', replace_vars_func + '\n(defun random-gate ()')

bulk_swap_old = """(defun bulk-swap-mutation (ast)
  "Replace a random subtree with a new random contiguous sequence of gates (length 2 to 5)."
  (let ((new-seq (random-gate-sequence (+ 2 (random 4)))))
    (if (or (atom ast) (= (length (cdr ast)) 0))
        new-seq
        (if (< (random 10) 3) ; 30% chance to replace this node
            new-seq
            (let ((new-args (copy-list (cdr ast)))
                  (idx (random (length (cdr ast)))))
              (setf (nth idx new-args) (bulk-swap-mutation (nth idx new-args)))
              (cons (car ast) new-args))))))"""

bulk_swap_new = """(defun bulk-swap-mutation (ast)
  "Replace a random subtree with a new random contiguous sequence of gates (length 2 to 5) or a template."
  (let* ((use-template (and *structural-templates* (< (random 100) 25)))
         (new-seq (if use-template
                      (instantiate-template (random-element *structural-templates*))
                      (random-gate-sequence (+ 2 (random 4))))))
    (if (or (atom ast) (= (length (cdr ast)) 0))
        new-seq
        (if (< (random 10) 3) ; 30% chance to replace this node
            new-seq
            (let ((new-args (copy-list (cdr ast)))
                  (idx (random (length (cdr ast)))))
              (setf (nth idx new-args) (bulk-swap-mutation (nth idx new-args)))
              (cons (car ast) new-args))))))"""

content = content.replace(bulk_swap_old, bulk_swap_new)


# 2. Trackers for adaptive SA
worker_loop_old = """(let* ((*current-operators* ops)
           ;; Synthesis domain: gate args must be atom qubits, not ADF subexpressions
           (*current-variables* (if (eq domain :synthesis)
                                    vars
                                    (append vars (mapcar #'car *adf-library*))))
           (*current-constants* consts)
           (proc (uiop:launch-program (list "swipl" "-q" "-s" "v7/engine/daemon.pl")
                                      :input :stream
                                      :output :stream))
           (proc-cell (list proc))
            (best-ast base-ast)
            ;; Saved target best — protected from novelty mode overwrites
            (saved-best-ast base-ast)
            (current-mode (if (eq *novelty-search-mode* t) :novelty :target))
            (best-penalty (check-with-prolog base-ast domain proc-cell current-mode))
            (saved-best-penalty best-penalty)
            (actual-iters 0)
            (stagnation-counter 0)
            (novelty-discoveries 0))
       (let ((current-ast base-ast))"""

worker_loop_new = """(let* ((*current-operators* ops)
           ;; Synthesis domain: gate args must be atom qubits, not ADF subexpressions
           (*current-variables* (if (eq domain :synthesis)
                                    vars
                                    (append vars (mapcar #'car *adf-library*))))
           (*current-constants* consts)
           (proc (uiop:launch-program (list "swipl" "-q" "-s" "v7/engine/daemon.pl")
                                      :input :stream
                                      :output :stream))
           (proc-cell (list proc))
            (best-ast base-ast)
            ;; Saved target best — protected from novelty mode overwrites
            (saved-best-ast base-ast)
            (current-mode (if (eq *novelty-search-mode* t) :novelty :target))
            (best-penalty (check-with-prolog base-ast domain proc-cell current-mode))
            (saved-best-penalty best-penalty)
            (actual-iters 0)
            (stagnation-counter 0)
            (novelty-discoveries 0)
            (current-temp 250.0)
            (recent-accepts 0)
            (recent-moves 0))
       (let ((current-ast base-ast))"""

content = content.replace(worker_loop_old, worker_loop_new)

sa_old = """                     (when (and (not is-better) (eq domain :synthesis))
                       ;; Simulated Annealing for synthesis domain
                       (let* ((initial-temp 250.0)
                              (final-temp 0.05)
                              (temp (* initial-temp (expt (/ final-temp initial-temp) (/ i iterations))))
                              (prob (exp (- (/ delta temp)))))
                         (when (< (random 1.0) prob)
                           (setf accepted-uphill t))))"""

sa_new = """                     (when (and (not is-better) (eq domain :synthesis))
                       ;; Adaptive Simulated Annealing for synthesis domain
                       (incf recent-moves)
                       (let ((prob (exp (- (/ delta current-temp)))))
                         (when (< (random 1.0) prob)
                           (setf accepted-uphill t)
                           (incf recent-accepts)))
                       (when (>= recent-moves 100)
                         (let ((ratio (/ recent-accepts (float recent-moves))))
                           (if (< ratio 0.2)
                               (setf current-temp (* current-temp 1.1))
                               (setf current-temp (* current-temp 0.9))))
                         (setf recent-moves 0)
                         (setf recent-accepts 0)))"""

content = content.replace(sa_old, sa_new)


# 3. Lambda Decoupling
lambda_old = """                   (when (and (eq domain :synthesis) (eq current-mode :target)
                              (= (mod i (max 1 (floor iterations 50))) 0))
                     (let* ((progress (/ i iterations))
                            (lambda-val (if (< progress 0.8)
                                            0.01
                                            (+ 0.01 (* 0.49 (/ (- progress 0.8) 0.2))))))
                       (send-lambda proc-cell (min lambda-val 0.50))))"""

lambda_new = """                   (when (and (eq domain :synthesis) (eq current-mode :target)
                              (= (mod i (max 1 (floor iterations 50))) 0))
                     (let* ((progress (/ i iterations))
                            (lambda-val (if (< progress 0.8)
                                            0.0
                                            (* 0.50 (/ (- progress 0.8) 0.2)))))
                       (send-lambda proc-cell (min lambda-val 0.50))))"""

content = content.replace(lambda_old, lambda_new)

with open('v7/engine/engine.lisp', 'w') as f:
    f.write(content)
