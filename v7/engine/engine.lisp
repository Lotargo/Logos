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
  "Mutates the AST by randomly changing operators, variables, or numbers, and occasionally growing."
  (if (atom ast)
      (if (< (random 100) 15) ; 15% chance to grow an atom into a subtree
          (let ((op (and *current-operators* (random-element *current-operators*))))
            (if op
                (cons op (loop repeat (if (member op '(h x_gate y_gate z_gate transpose norm gamma delta_s)) 1 2)
                               collect (if (< (random 10) 5)
                                           (if *current-variables* (random-element *current-variables*) 0)
                                           (if *current-constants* (random-element *current-constants*) 0))))
                ast))
          (if (numberp ast)
              (if *current-constants* (random-element *current-constants*) ast)
              (if *current-variables* (random-element *current-variables*) ast)))
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
     (values '(seq h cnot) '(q1 q2) nil))
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
          (result nil)
          (actual-iters 0))
      ;; Use a local hypothesis that evolves over time rather than always mutating base-ast
      (let ((current-ast base-ast))
        (loop for i from 1 to iterations
              do (incf actual-iters)
                 (let ((hypothesis (mutate current-ast)))
                   (if (check-with-prolog hypothesis domain proc)
                       (progn
                         (format t "[Thread ~D] [ACCEPT] Iteration ~D: ~A~%" thread-id i hypothesis)
                         (setf result hypothesis)
                         (return))
                       ;; If rejected, occasionally keep the mutation anyway to escape local minima
                       (when (< (random 100) 20)
                         (setf current-ast hypothesis))))))
      ;; Clean up the Prolog daemon
      (format (uiop:process-info-input proc) "quit~%")
      (ignore-errors (force-output (uiop:process-info-input proc)))
      (uiop:wait-process proc)
      (cons result actual-iters))))

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

  (let* ((start-time (get-internal-real-time))
         (threads (loop for i from 1 to num-threads
                        collect (let ((thread-id i))
                                  (sb-thread:make-thread
                                   (lambda ()
                                     (worker-loop base-ast domain iterations thread-id))))))
         (thread-results (mapcar #'sb-thread:join-thread threads))
         (end-time (get-internal-real-time))
         (elapsed-seconds (/ (- end-time start-time) (coerce internal-time-units-per-second 'double-float)))
         (total-iterations (loop for res in thread-results sum (cdr res)))
         (winners (remove nil (mapcar #'car thread-results))))
    
    (format t "~%==================================================~%")
    (format t "      v7 ENGINE PERFORMANCE DASHBOARD~%")
    (format t "==================================================~%")
    (format t "Total Elapsed Time    : ~,4F seconds~%" elapsed-seconds)
    (format t "Logical CPU Cores     : ~D~%" num-threads)
    (format t "Total ASTs Evaluated  : ~D~%" total-iterations)
    (format t "Throughput (AST/sec)  : ~,2F~%" (if (> elapsed-seconds 0) (/ total-iterations elapsed-seconds) 0))
    (format t "Avg Latency per AST   : ~,4F ms~%" (if (> total-iterations 0) (/ (* elapsed-seconds 1000) total-iterations) 0))
    (format t "==================================================~%~%")

    (if winners
        (progn
          (format t "Found valid hypotheses from Islands:~%")
          (loop for res in winners do (format t "  ~A~%" res))
          (let ((hybrids (synthesize-hybrids winners domain 3 20000)))
            (when hybrids
              (format t "Ultimate Hybrids:~%")
              (loop for h in hybrids do (format t "  ~A~%" h)))))
        (format t "No valid hypotheses found.~%"))))

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

(defun contains-operator-p (operators ast)
  "Recursively checks if the AST contains any of the given operators/symbols."
  (cond
    ((null ast) nil)
    ((atom ast)
     (and (or (symbolp ast) (stringp ast) (characterp ast))
          (member ast operators :test #'string-equal)))
    (t (or (contains-operator-p operators (car ast))
           (contains-operator-p operators (cdr ast))))))

(defun detect-domain-by-ast (ast)
  "Auto-detects the scientific domain based on operators and variables present in the AST."
  (cond
    ((contains-operator-p '(gamma add_vel v1 v2) ast) :relativity)
    ((contains-operator-p '(carnot delta_s t_hot t_cold) ast) :thermo)
    ((contains-operator-p '(entropy info_bound area volume) ast) :holography)
    ((contains-operator-p '(tensor seq h x_gate y_gate z_gate cnot q1 q2 q3) ast) :quantum)
    ((contains-operator-p '(matmul transpose cross dot scale norm m2x3 m3x2 m3x3 m4x1 v2_a v2_b v3_a v3_b v4_a) ast) :multidim)
    ((contains-operator-p '(deriv int sin cos t) ast) :calculus)
    ((contains-operator-p '(and or implies not p q true false) ast) :logic)
    (t :arithmetic))) ; default fallback

(defun parse-cli-args (args)
  "Parses command line arguments into variables."
  (let ((domain nil)
        (base-ast nil)
        (iterations 20000)
        (threads nil))
    (loop for arg-list = args then (cdr arg-list)
          while arg-list
          do (let ((arg (car arg-list))
                   (next-arg (cadr arg-list)))
               (cond
                 ((or (string= arg "--domain") (string= arg "-d"))
                  (setf domain (intern (string-upcase next-arg) :keyword))
                  (setf arg-list (cdr arg-list)))
                 ((or (string= arg "--base") (string= arg "-b"))
                  (setf base-ast (read-from-string next-arg))
                  (setf arg-list (cdr arg-list)))
                 ((or (string= arg "--iterations") (string= arg "-i"))
                  (setf iterations (parse-integer next-arg))
                  (setf arg-list (cdr arg-list)))
                 ((or (string= arg "--threads") (string= arg "-t"))
                  (setf threads (parse-integer next-arg))
                  (setf arg-list (cdr arg-list))))))
    (values domain base-ast iterations threads)))

(defun main ()
  (let ((args (uiop:command-line-arguments)))
    (if args
        (multiple-value-bind (domain base-ast iterations threads) (parse-cli-args args)
          (unless base-ast
            (error "Missing required argument: --base <lisp-expression> (e.g. -b \"(h (h q1))\")"))
          (let* ((auto-domain (or domain (detect-domain-by-ast base-ast)))
                 (num-threads (or threads (detect-cpu-cores))))
            (format t "~%=== Running Custom CLI Task ===~%")
            (if domain
                (format t "Domain: ~A~%" domain)
                (format t "Domain: ~A (Auto-detected)~%" auto-domain))
            (format t "Base AST: ~A~%" base-ast)
            (format t "Iterations: ~D~%" iterations)
            (format t "Threads: ~D~%" num-threads)
            (run-engine-parallel base-ast auto-domain iterations num-threads)))
        ;; If no CLI arguments, run the default full multi-domain demo suite!
        (let ((arith-base '(+ x 0))
              (calc-base '(deriv (sin x t) x))
              (quant-base '(seq (h q2) (cnot q2 q1)))
              (num-threads (detect-cpu-cores)))
          (format t "~%[SYSTEM] Detected logical CPU cores: ~D~%" num-threads)

          (format t "~%--- Running Arithmetic Domain ---~%")
          (run-engine-parallel arith-base :arithmetic 200 num-threads)

          (format t "~%--- Running Calculus Domain ---~%")
          (run-engine-parallel calc-base :calculus 200 num-threads)

          (format t "~%--- Running Quantum Domain ---~%")
          (run-engine-parallel quant-base :quantum 200 num-threads)

          (format t "~%--- Running Multi-Dimensional Tensor Domain ---~%")
          (run-engine-parallel '(matmul m2x3 m2x3) :multidim 20000 num-threads)

          (format t "~%--- Running Relativity Domain ---~%")
          (run-engine-parallel '(gamma 1.2) :relativity 20000 num-threads)

          (format t "~%--- Running Thermodynamics Domain ---~%")
          (run-engine-parallel '(carnot 0 t_cold) :thermo 50000 num-threads)

          (format t "~%--- Running Holography Domain ---~%")
          (run-engine-parallel '(entropy volume) :holography 200 num-threads)

          (format t "~%--- Running Logic Domain ---~%")
          (run-engine-parallel '(and p (not p)) :logic 200 num-threads)))))

(main)
