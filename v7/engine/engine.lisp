(require :asdf)

(defpackage :cognitive-engine
  (:use :cl))
(in-package :cognitive-engine)

;; =======================================================================
;; 1. Domains Configuration
;; =======================================================================

(defvar *current-operators* '(+ - * /))
(defvar *current-variables* '(x y z))
(defvar *current-constants* '(0 1 2 5 10))

(defun set-domain (domain-name)
  (case domain-name
    (:arithmetic
     (setf *current-operators* '(+ - * /))
     (setf *current-variables* '(x y z))
     (setf *current-constants* '(0 1 2 5 10)))
    (:calculus
     (setf *current-operators* '(+ - * / deriv int sin cos))
     (setf *current-variables* '(x t))
     (setf *current-constants* '(0 1 -1)))
    (:quantum
     (setf *current-operators* '(tensor seq h x_gate y_gate z_gate cnot))
     (setf *current-variables* '(q1 q2 q3))
     (setf *current-constants* '(1 0)))
    (t (error "Unknown domain"))))

;; =======================================================================
;; 2. Lisp: Generator and Mutator of DNA
;; =======================================================================

(defun random-element (list)
  (nth (random (length list)) list))

(defun mutate (ast)
  "Mutates the AST by randomly changing operators, variables, or numbers."
  (if (atom ast)
      (if (numberp ast)
          (if *current-constants* (random-element *current-constants*) ast)
          (if *current-variables* (random-element *current-variables*) ast))
      (let ((op (car ast))
            (args (cdr ast)))
        (if (< (random 10) 4) ; 40% chance to mutate the operator
            (if *current-operators*
                (cons (random-element *current-operators*) args)
                ast)
            ;; Otherwise, mutate a random child node
            (if args
                (let ((mutated-args (copy-list args))
                      (idx (random (length args))))
                  ;; For thermodynamics `0` is technically a number, so make sure
                  ;; random mutations don't get stuck if we just randomly pick a leaf
                  (if (and (atom (nth idx mutated-args)) (< (random 10) 5))
                      (setf (nth idx mutated-args) (if *current-variables* (random-element *current-variables*) (nth idx mutated-args)))
                      (setf (nth idx mutated-args) (mutate (nth idx mutated-args))))
                  (cons op mutated-args))
                ast)))))

(defun crossover (ast1 ast2)
  "Simple crossover: replace a random subtree in ast1 with ast2."
  (if (atom ast1)
      ast2
      (if (< (random 10) 3)
          ast2
          (let ((new-args (copy-list (cdr ast1)))
                (idx (random (length (cdr ast1)))))
            (setf (nth idx new-args) (crossover (nth idx new-args) ast2))
            (cons (car ast1) new-args)))))

;; =======================================================================
;; 3. Prolog Interface: Mathematical Censor
;; =======================================================================

(defun lisp-to-prolog (ast)
  "Translates Lisp AST into Prolog term syntax."
  (cond
    ((numberp ast) (format nil "~A" ast))
    ((symbolp ast) (string-downcase (symbol-name ast)))
    ((listp ast)
     (let ((op (car ast))
           (args (cdr ast)))
       (let ((prolog-op (case op
                          (+ "add")
                          (- "sub")
                          (* "mul")
                          (/ "div")
                          (t (string-downcase (symbol-name op))))))
         (format nil "~A(~{~A~^, ~})" prolog-op (mapcar #'lisp-to-prolog args)))))))

(defun check-with-prolog (ast domain proc)
  "Sends the AST to the running SWI-Prolog daemon.
   Returns T if Prolog accepts it (Censor approves), NIL otherwise."
  (let* ((prolog-term (lisp-to-prolog ast))
         (query (format nil "censor(~A, ~A)." (string-downcase (symbol-name domain)) prolog-term)))
    (format (uiop:process-info-input proc) "~A~%" query)
    (force-output (uiop:process-info-input proc))
    (let ((response (read-line (uiop:process-info-output proc) nil :eof)))
      (and (stringp response)
           (string= (string-trim '(#\Space #\Tab #\Return #\Newline) response) "true")))))

;; =======================================================================
;; 4. Main Universal Cognitive Engine Loop (Multi-Threaded)
;; =======================================================================

(defun get-domain-config (domain-name)
  (case domain-name
    (:arithmetic
     (values '(+ - * /) '(x y z) '(0 1 2 5 10)))
    (:calculus
     (values '(+ - * / deriv int sin cos) '(x t) '(0 1 -1)))
    (:quantum
     (values '(tensor seq h x_gate y_gate z_gate cnot) '(q1 q2 q3) '(1 0)))
    (:multidim
     (values '(add sub dot cross scale norm matmul transpose) '(m2x3 m3x2 m3x3 m4x1 s1 s2) '(0 1)))
    (:relativity
     (values '(gamma add_vel) '(v1 v2) '(0 0.1 0.5 0.8 0.9 1.2)))
    (:thermo
     (values '(carnot delta_s) '(t_hot t_cold) '(0 100 300 500)))
    (:holography
     (values '(entropy info_bound) '(area volume) '(0 1 2 5 10)))
    (:logic
     (values '(and or implies not) '(p q) '(true false)))
    (t (error "Unknown domain"))))

(defun worker-loop (base-ast domain iterations thread-id)
  (multiple-value-bind (ops vars consts) (get-domain-config domain)
    ;; Dynamic bindings of special variables are thread-local in SBCL
    (let ((*current-operators* ops)
          (*current-variables* vars)
          (*current-constants* consts)
          (proc (uiop:launch-program (list "swipl" "-q" "-s" "v7/engine/daemon.pl")
                                     :input :stream
                                     :output :stream))
          (result nil))
      ;; Use a local hypothesis that evolves over time rather than always mutating base-ast
      (let ((current-ast base-ast))
        (loop for i from 1 to iterations
              do (let ((hypothesis (mutate current-ast)))
                   (if (check-with-prolog hypothesis domain proc)
                       (progn
                         (format t "[Thread ~D] [ACCEPT] Iteration ~D: ~A~%" thread-id i hypothesis)
                         (setf result hypothesis)
                         (return))
                       ;; If rejected, occasionally keep the mutation anyway to escape local minima
                       ;; Increase probability of keeping to 20% to better traverse deep AST valleys
                       (when (< (random 100) 20)
                         (setf current-ast hypothesis))))))
      ;; Clean up the Prolog daemon
      (format (uiop:process-info-input proc) "quit~%")
      (ignore-errors (force-output (uiop:process-info-input proc)))
      (uiop:wait-process proc)
      result)))

(defun synthesize-hybrids (winners domain desired-hybrids max-iterations)
  (when (< (length winners) 2)
    (return-from synthesize-hybrids winners))
  (format t "~%--- Final Synthesis Phase (Island Crossover) ---~%")
  (multiple-value-bind (ops vars consts) (get-domain-config domain)
    (let ((*current-operators* ops)
          (*current-variables* vars)
          (*current-constants* consts)
          (proc (uiop:launch-program (list "swipl" "-q" "-s" "v7/engine/daemon.pl")
                                     :input :stream
                                     :output :stream))
          (hybrids nil))
      (loop for i from 1 to max-iterations
            while (< (length hybrids) desired-hybrids)
            do (let* ((parent1 (random-element winners))
                      (parent2 (random-element winners))
                      (child (crossover parent1 parent2)))
                 ;; Only accept the child if it's actually different from parents
                 (when (and (not (equal child parent1))
                            (not (equal child parent2))
                            (check-with-prolog child domain proc))
                   (format t "[SYNTHESIS] Found valid hybrid at iteration ~D: ~A~%" i child)
                   (push child hybrids))))
      (format (uiop:process-info-input proc) "quit~%")
      (ignore-errors (force-output (uiop:process-info-input proc)))
      (uiop:wait-process proc)
      hybrids)))

(defun run-engine-parallel (base-ast domain iterations num-threads)
  (format t "=== Starting Parallel Cognitive Engine v7 ===~%")
  (format t "Domain: ~A~%" domain)
  (format t "Base AST: ~A~%" base-ast)
  (format t "Threads: ~D~%" num-threads)

  (let ((threads (loop for i from 1 to num-threads
                       collect (let ((thread-id i))
                                 (sb-thread:make-thread
                                  (lambda ()
                                    (worker-loop base-ast domain iterations thread-id)))))))
    (let ((results (remove nil (mapcar #'sb-thread:join-thread threads))))
      (if results
          (progn
            (format t "Found valid hypotheses from Islands:~%")
            (loop for res in results do (format t "  ~A~%" res))
            (let ((hybrids (synthesize-hybrids results domain 3 20000)))
              (when hybrids
                (format t "Ultimate Hybrids:~%")
                (loop for h in hybrids do (format t "  ~A~%" h)))))
          (format t "No valid hypotheses found.~%")))))

(defun detect-cpu-cores ()
  "Attempts to detect the number of logical CPU cores. Fallbacks to 4 if detection fails."
  (let ((env-cores (uiop:getenv "NUMBER_OF_PROCESSORS")))
    (if env-cores
        (or (ignore-errors (parse-integer env-cores)) 4)
        (let ((proc-cores (ignore-errors
                            (with-open-file (s "/proc/cpuinfo" :if-does-not-exist nil)
                              (if s
                                  (loop for line = (read-line s nil nil)
                                        while line
                                        count (search "processor" line))
                                  nil)))))
          (or proc-cores 4)))))

(defun main ()
  ;; Start with an AST that has division by zero or algebraic redundancy
  (let ((arith-base '(+ x 0))
        ;; A calculus AST that shouldn't be accepted (e.g. invalid arity for sin)
        (calc-base '(deriv (sin x t) x))
        ;; Quantum AST that is invalid (redundant double Hadamard gate)
        (quant-base '(h (h q1)))
        ;; Auto-detect CPU threads for 100% utilization
        (num-threads (detect-cpu-cores)))
    (format t "~%[SYSTEM] Detected logical CPU cores: ~D~%" num-threads)

    (format t "~%--- Running Arithmetic Domain ---~%")
    (run-engine-parallel arith-base :arithmetic 200 num-threads)

    (format t "~%--- Running Calculus Domain ---~%")
    (run-engine-parallel calc-base :calculus 200 num-threads)

    (format t "~%--- Running Quantum Domain ---~%")
    (run-engine-parallel quant-base :quantum 200 num-threads)

    (format t "~%--- Running Multi-Dimensional Tensor Domain ---~%")
    ;; Complex dimensionally invalid AST: (matmul m2x3 m2x3)
    ;; Columns of first matrix (3) do not match rows of second matrix (2)
    (run-engine-parallel '(matmul m2x3 m2x3) :multidim 20000 num-threads)

    (format t "~%--- Running Relativity Domain ---~%")
    ;; Speeds exceeding light speed c=1.0 (1.2) must be rejected and healed
    (run-engine-parallel '(gamma 1.2) :relativity 20000 num-threads)

    (format t "~%--- Running Thermodynamics Domain ---~%")
    ;; Absolute zero is physically impossible, Th cannot be equal to Tc
    (run-engine-parallel '(carnot 0 t_cold) :thermo 50000 num-threads)

    (format t "~%--- Running Holography Domain ---~%")
    ;; Entropy must be bounded by area, volume is invalid
    (run-engine-parallel '(entropy volume) :holography 200 num-threads)

    (format t "~%--- Running Logic Domain ---~%")
    ;; Logical contradictions are forbidden
    (run-engine-parallel '(and p (not p)) :logic 200 num-threads)))

(main)
