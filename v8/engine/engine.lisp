(require :asdf)

(defpackage :cognitive-engine
  (:use :cl))
(in-package :cognitive-engine)

;; Load Meta-Evolution extensions
(load "v8/engine/meta_evolve.lisp")
(load "v8/engine/ontology_generator.lisp")
(load "v8/engine/verilog_emitter.lisp")
(load "v8/engine/curry_howard.lisp")

;; =======================================================================
;; 1. Domains Configuration
;; =======================================================================

(defvar *unified-operators* '(+ - * / add sub mul div deriv int sin cos seq matrix row matmul transpose cross dot scale norm gamma add_vel carnot delta_s entropy info_bound and or implies not))
(defvar *unified-variables* '(x y z t q1 q2 q3 m2x3 m3x2 m3x3 m4x1 s1 s2 v1 v2 t_hot t_cold area volume p q))
(defvar *unified-constants* '(0 1 2 5 10 -1 0.1 0.5 0.8 0.9 1.2 100 300 500 true false 0.70710678 -0.70710678))

(defvar *current-operators* *unified-operators*)
(defvar *current-variables* *unified-variables*)
(defvar *current-constants* *unified-constants*)

(defun detect-regression-vars (csv-file)
  "Reads the first line of the CSV file and returns a list of generic symbols (v1 v2 ... vn)."
  (let ((path (or csv-file "v8/engine/anomaly_data.csv")))
    (handler-case
        (with-open-file (stream path :direction :input)
          (let ((first-line (read-line stream nil nil)))
            (if first-line
                (let* ((comma-count (count #\, first-line))
                       (num-vars comma-count))
                  (loop for i from 1 to num-vars
                        collect (intern (format nil "V~D" i))))
                '(v1 v2 v3))))
      (error () '(v1 v2 v3)))))

(defun set-domain (domain-name)
  (declare (ignore domain-name))
  (setf *current-operators* *unified-operators*)
  (setf *current-variables*
        (append (if (and (boundp '*regression-vars*) *regression-vars*)
                    *regression-vars*
                    (detect-regression-vars (and (boundp '*current-dataset*) *current-dataset*)))
                *unified-variables*))
  (setf *current-constants* *unified-constants*))

;; =======================================================================
;; 2. Lisp: Generator and Mutator of DNA
;; =======================================================================

(defun random-element (list)
  (nth (random (length list)) list))

(defun op-arity (op)
  (if (member op '(h x_gate y_gate z_gate transpose norm gamma delta_s not oracle))
      1
      2))

(defun mutate (ast)
  "Mutates the AST by randomly changing operators, variables, or numbers, and occasionally growing."
  (if (atom ast)
      (if (< (random 100) 15) ; 15% chance to grow an atom into a subtree
          (let ((op (and *current-operators* (random-element *current-operators*))))
            (cond
              ((eq op 'matrix)
               '(matrix (row 1.0 0.0) (row 0.0 1.0)))
              ((eq op 'row)
               '(row 1.0 0.0))
              (op
               (cons op (loop repeat (op-arity op)
                              collect (if (< (random 10) 5)
                                          (if *current-variables* (random-element *current-variables*) 0)
                                          (if *current-constants* (random-element *current-constants*) 0)))))
              (t ast)))
          (if (numberp ast)
              (if *current-constants* (random-element *current-constants*) ast)
              (if *current-variables* (random-element *current-variables*) ast)))
      (let ((op (car ast))
            (args (cdr ast)))
        (if (< (random 10) 4) ; 40% chance to mutate the operator
            (if (and *current-operators* (not (member op '(matrix row))))
                (cons (random-element (remove 'row (remove 'matrix *current-operators*))) args)
                ast)
            ;; Otherwise, mutate a random child node
            (if args
                (let ((mutated-args (copy-list args))
                      (idx (random (length args))))
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

(defvar *adf-library* nil)
(defparameter *novelty-search-mode* :auto)


(defun expand-adfs (ast)
  "Recursively expands any ADF symbols in the AST into their actual bodies."
  (cond
    ((null ast) nil)
    ((atom ast)
     (let ((body (assoc ast *adf-library*)))
       (if body
           (expand-adfs (cdr body))
           ast)))
    ((listp ast)
     (let ((body (assoc (car ast) *adf-library*)))
       (if body
           (expand-adfs (cdr body))
           (cons (car ast) (mapcar #'expand-adfs (cdr ast))))))))

(defun lisp-to-prolog (ast)
  "Translates Lisp AST into Prolog term syntax after expanding any ADFs."
  (let ((expanded (expand-adfs ast)))
    (cond
      ((numberp expanded) (format nil "~A" expanded))
      ((symbolp expanded) (string-downcase (symbol-name expanded)))
      ((listp expanded)
       (let ((op (car expanded))
             (args (cdr expanded)))
         (let ((prolog-op (case op
                            (+ "add")
                            (- "sub")
                            (* "mul")
                            (/ "div")
                            (t (string-downcase (symbol-name op))))))
           (format nil "~A(~{~A~^, ~})" prolog-op (mapcar #'lisp-to-prolog args))))))))

(defvar *current-dataset* nil)

(defun check-with-prolog (ast domain proc-cell &optional (mode :target))
  "Sends the AST to the running SWI-Prolog daemon with a 1.0s timeout.
   Returns the penalty score (a float between 0.0 and 1000.0) if successful, or 1000.0 if failed."
  (let* ((proc (car proc-cell))
         (prepared-ast (if (eq domain :curry_howard) (generate-proof ast) ast))
         (prolog-term (lisp-to-prolog prepared-ast))
         (query (format nil "censor(~A, ~A, ~A, Penalty)." (string-downcase (symbol-name mode)) (string-downcase (symbol-name domain)) prolog-term)))
    ;; Re-inject active dataset and active variables if regression
    (when (eq domain :regression)
      (when (and (boundp '*current-dataset*) *current-dataset*)
         (let* ((actual-vars (remove-if (lambda (v) (search "ADF" (symbol-name v))) *current-variables*))
                (combined-query (format nil "retractall(active_dataset(_)), assertz(active_dataset('~A')), retractall(regression_vars(_)), assertz(regression_vars([~{~A~^, ~}]))." 
                                      *current-dataset* 
                                      (mapcar (lambda (v) (string-downcase (symbol-name v))) actual-vars))))
           (handler-case
              (sb-ext:with-timeout 1.0
                (format (uiop:process-info-input proc) "~A~%" combined-query)
                (force-output (uiop:process-info-input proc))
                (read-line (uiop:process-info-output proc) nil :eof))
              (error (e) nil)))))
    (handler-case
        (sb-ext:with-timeout 1.0 ; 1.0 second (1000 milliseconds)
          (format (uiop:process-info-input proc) "~A~%" query)
          (force-output (uiop:process-info-input proc))
          (let ((response (read-line (uiop:process-info-output proc) nil :eof)))
            (if (and (stringp response) (not (eq response :eof)))
                (or (ignore-errors (read-from-string (string-trim '(#\Space #\Tab #\Return #\Newline #\") response)))
                    1000.0)
                1000.0)))
      (sb-ext:timeout ()
        (format t "[TIMEOUT] Prolog daemon hung on query: ~A. Forcefully restarting...~%" query)
        (ignore-errors (uiop:terminate-process proc :urgent t))
        (let ((new-proc (uiop:launch-program (list "swipl" "-q" "-s" "v8/engine/daemon.pl")
                                             :input :stream
                                             :output :stream)))
          (setf (car proc-cell) new-proc))
        1000.0)
      (error (e)
        (format t "[ERROR] Prolog daemon pipe error: ~A. Restarting daemon...~%" e)
        (ignore-errors (uiop:terminate-process proc :urgent t))
        (let ((new-proc (uiop:launch-program (list "swipl" "-q" "-s" "v8/engine/daemon.pl")
                                             :input :stream
                                             :output :stream)))
          (setf (car proc-cell) new-proc))
        1000.0))))

;; =======================================================================
;; 4. Main Universal Cognitive Engine Loop (Multi-Threaded)
;; =======================================================================

(defun get-domain-config (domain-name)
  (declare (ignore domain-name))
  (values *unified-operators*
          (append (if (and (boundp '*regression-vars*) *regression-vars*)
                      *regression-vars*
                      (detect-regression-vars (and (boundp '*current-dataset*) *current-dataset*)))
                  *unified-variables*)
          *unified-constants*))

(defun worker-loop (base-ast domain iterations thread-id migration-pools migration-mutexes)
  (multiple-value-bind (ops vars consts) (get-domain-config domain)
    ;; Dynamic bindings of special variables are thread-local in SBCL
    (let* ((*current-operators* ops)
           (*current-variables* (append vars (mapcar #'car *adf-library*)))
           (*current-constants* consts)
           (proc (uiop:launch-program (list "swipl" "-q" "-s" "v8/engine/daemon.pl")
                                      :input :stream
                                      :output :stream))
           (proc-cell (list proc))
           (best-ast base-ast)
           (current-mode (if (eq *novelty-search-mode* t) :novelty :target))
           (best-penalty (check-with-prolog base-ast domain proc-cell current-mode))
           (actual-iters 0)
           (stagnation-counter 0)
           (novelty-discoveries 0))
      (let ((current-ast base-ast))
        (loop for i from 1 to iterations
              while (or (> best-penalty 0.0) (eq current-mode :novelty))
              do (incf actual-iters)
                 (incf stagnation-counter)

                 ;; Auto Mode Switching Logic
                 (when (eq *novelty-search-mode* :auto)
                   (cond
                     ((and (eq current-mode :target) (> stagnation-counter 100))
                      (format t "[Thread ~D] Stagnation detected. Switching to EXPLORATION (Novelty) mode.~%" thread-id)
                      (setf current-mode :novelty)
                      (setf stagnation-counter 0)
                      (setf novelty-discoveries 0)
                      (setf best-penalty 1000.0)) ; Reset best penalty for novelty
                     ((and (eq current-mode :novelty) (>= novelty-discoveries 5))
                      (format t "[Thread ~D] Sufficient exploration done. Switching back to TARGET mode.~%" thread-id)
                      (setf current-mode :target)
                      (setf stagnation-counter 0)
                      (setf best-penalty (check-with-prolog best-ast domain proc-cell :target)))))

                 (let* ((hypothesis (mutate current-ast))
                        (penalty (check-with-prolog hypothesis domain proc-cell current-mode)))

                   ;; Attempt Meta-Evolution mutation
                   (when (and (> penalty 0.0) (< (random 100) 20)) ; Trigger Meta-Evolution 20% of the time on invalid ASTs
                     (multiple-value-bind (meta-ast meta-penalty meta-axiom)
                         (meta-mutate-axiom proc-cell domain current-ast best-penalty #'check-with-prolog)
                       (when meta-ast
                         (setf hypothesis meta-ast)
                         (setf penalty meta-penalty))))

                   ;; Log Discoveries in Novelty Mode
                   (when (and (eq current-mode :novelty) (< penalty 100.0) (< penalty best-penalty))
                      (format t "[NOVELTY DISCOVERY] Thread ~D found novel state in ~A! AST: ~A (Penalty: ~,2F)~%" thread-id domain hypothesis penalty)
                      (incf novelty-discoveries)
                      (with-open-file (stream "discoveries.log" :direction :output :if-exists :append :if-does-not-exist :create)
                        (format stream "[NOVELTY] Thread ~D | Domain: ~A | Penalty: ~,2F | AST: ~A~%" thread-id domain penalty hypothesis)))

                   (if (or (< penalty best-penalty)
                           (and (= penalty best-penalty) (< (length (format nil "~A" hypothesis)) (length (format nil "~A" best-ast))))
                           (< (random 100) 15))
                       (progn
                         (when (< penalty best-penalty)
                           (setf stagnation-counter 0))
                         (setf best-ast hypothesis)
                         (setf best-penalty penalty)
                         (setf current-ast hypothesis)
                         (when (and (eq current-mode :target) (= best-penalty 0.0))
                           (format t "[Thread ~D] [CONVERGED] Iteration ~D: ~A (Penalty: 0.0)~%" thread-id i best-ast)
                           (return)))))
                 
                 ;; Periodic Island Migration (Ring Topology)
                 (when (and migration-pools migration-mutexes (> actual-iters 0) (= 0 (mod actual-iters 50)))
                   (let* ((num-pools (length migration-pools))
                          (target-idx (mod thread-id num-pools))
                          (mutex (aref migration-mutexes target-idx))
                          (pool (aref migration-pools target-idx)))
                     (sb-thread:with-mutex (mutex)
                       (unless (member best-ast pool :test #'equal)
                         (when (< (length pool) 5)
                           (setf (aref migration-pools target-idx) (cons best-ast pool))
                           (format t "[Thread ~D] Migrated best AST to Thread ~D: ~A~%" thread-id (1+ target-idx) best-ast)))))
                   
                   (let* ((our-idx (1- thread-id))
                          (mutex (aref migration-mutexes our-idx))
                          (immigrants nil))
                     (sb-thread:with-mutex (mutex)
                       (setf immigrants (aref migration-pools our-idx))
                       (setf (aref migration-pools our-idx) nil))
                     (dolist (immigrant immigrants)
                       (let ((imm-penalty (check-with-prolog immigrant domain proc-cell current-mode)))
                         (if (< imm-penalty best-penalty)
                             (progn
                               (setf best-ast immigrant)
                               (setf best-penalty imm-penalty)
                               (setf current-ast immigrant)
                               (format t "[Thread ~D] Accepted immigrant! New best: ~A (Penalty: ~,2F)~%" thread-id best-ast best-penalty))
                             (when (< (random 100) 50)
                               (let* ((child (crossover current-ast immigrant))
                                      (child-penalty (check-with-prolog child domain proc-cell current-mode)))
                                 (when (< child-penalty best-penalty)
                                   (setf best-ast child)
                                   (setf best-penalty child-penalty)
                                   (setf current-ast child)
                                   (format t "[Thread ~D] Crossover with immigrant! New best: ~A (Penalty: ~,2F)~%" thread-id child best-penalty)))))))))))
      ;; Clean up the Prolog daemon
      (let ((active-proc (car proc-cell)))
        (format (uiop:process-info-input active-proc) "quit~%")
        (ignore-errors (force-output (uiop:process-info-input active-proc)))
        (uiop:wait-process active-proc))
      (cons best-ast actual-iters))))

(defun synthesize-hybrids (winners domain desired-hybrids max-iterations)
  (when (< (length winners) 2)
    (return-from synthesize-hybrids winners))
  (format t "~%--- Final Synthesis Phase (Island Crossover) ---~%")
  (multiple-value-bind (ops vars consts) (get-domain-config domain)
    (let* ((*current-operators* ops)
           (*current-variables* (append vars (mapcar #'car *adf-library*)))
           (*current-constants* consts)
           (proc (uiop:launch-program (list "swipl" "-q" "-s" "v8/engine/daemon.pl")
                                      :input :stream
                                      :output :stream))
           (proc-cell (list proc))
           (hybrids nil))
      (loop for i from 1 to max-iterations
            while (< (length hybrids) desired-hybrids)
            do (let* ((parent1 (random-element winners))
                      (parent2 (random-element winners))
                      (child (crossover parent1 parent2)))
                 ;; Only accept the child if it's actually different from parents and has 0.0 penalty
                 (when (and (not (equal child parent1))
                            (not (equal child parent2))
                            (= (check-with-prolog child domain proc-cell) 0.0))
                   (format t "[SYNTHESIS] Found valid hybrid at iteration ~D: ~A~%" i child)
                   (push child hybrids))))
      (let ((active-proc (car proc-cell)))
        (format (uiop:process-info-input active-proc) "quit~%")
        (ignore-errors (force-output (uiop:process-info-input active-proc)))
        (uiop:wait-process active-proc))
      hybrids)))

(defun run-engine-parallel (base-ast domain iterations num-threads)
  (setf *discovered-axioms* nil)
  (format t "=== Starting Parallel Logos Cognitive Engine ===~%")
  (format t "Domain: ~A~%" domain)
  (format t "Base AST: ~A~%" base-ast)
  (format t "Threads: ~D~%" num-threads)

  (let* ((start-time (get-internal-real-time))
         (migration-pools (make-array num-threads :initial-element nil))
         (migration-mutexes (map 'vector (lambda (x) (declare (ignore x)) (sb-thread:make-mutex)) (make-list num-threads)))
         (threads (loop for i from 1 to num-threads
                        collect (let ((thread-id i))
                                  (sb-thread:make-thread
                                   (lambda ()
                                     (worker-loop base-ast domain iterations thread-id migration-pools migration-mutexes))))))
         (thread-results (mapcar #'sb-thread:join-thread threads))
         (end-time (get-internal-real-time))
         (elapsed-seconds (/ (- end-time start-time) (coerce internal-time-units-per-second 'double-float)))
         (total-iterations (loop for res in thread-results sum (cdr res)))
         (winners (remove-duplicates (remove nil (mapcar #'car thread-results)) :test #'equal)))

    ;; Dynamic Subroutine Extraction: Register successful island winners as new ADF symbols
    (dolist (w winners)
      (let ((adf-sym (intern (format nil "ADF-~D" (1+ (length *adf-library*))))))
        (push (cons adf-sym w) *adf-library*)
        (format t "[ADF MANAGER] Extracted and registered dynamic subroutine: ~A -> ~A~%" adf-sym w)))
    
    (format t "~%==================================================~%")
    (format t "      LOGOS ENGINE PERFORMANCE DASHBOARD~%")
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
              (loop for h in hybrids do (format t "  ~A~%" h))
              ;; Generate LaTeX Ontology for the best discovery
              (generate-latex-ontology domain base-ast *discovered-axioms* (car hybrids) total-iterations elapsed-seconds))))
        (format t "No valid hypotheses found.~%"))

    ;; Silicon Lowering
    (when (and winners (member domain '(:hardware :logic)))
      (let* ((best (car winners))
             (mod-name (format nil "synth_~A" (string-downcase (symbol-name domain))))
             (path (format nil "v8/hardware/~A.v" mod-name)))
        (uiop:run-program "mkdir -p v8/hardware" :ignore-error-status t)
        (emit-verilog best mod-name path)))
    ))

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
  (let ((domains nil))
    (when (contains-operator-p '(gamma add_vel v1 v2) ast) (push :relativity domains))
    (when (contains-operator-p '(carnot delta_s t_hot t_cold) ast) (push :thermo domains))
    (when (contains-operator-p '(entropy info_bound area volume) ast) (push :holography domains))
    (when (contains-operator-p '(tensor seq h x_gate y_gate z_gate cnot oracle q1 q2 q3) ast) (push :quantum domains))
    (when (contains-operator-p '(matmul transpose cross dot scale norm m2x3 m3x2 m3x3 m4x1 v2_a v2_b v3_a v3_b v4_a) ast) (push :multidim domains))
    (when (contains-operator-p '(deriv int sin cos t) ast) (push :calculus domains))
    (when (contains-operator-p '(and or xor implies not p q true false) ast) (push :logic domains))
    (when (contains-operator-p '(gate_and gate_or gate_not r s) ast) (push :hardware domains))
    (when (contains-operator-p '(proof type int) ast) (push :curry_howard domains))
    (let ((unique-domains (remove-duplicates domains)))
      (cond
        ((> (length unique-domains) 1) :unified)
        ((= (length unique-domains) 1) (car unique-domains))
        (t :arithmetic)))))

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
          (run-engine-parallel '(add v3_a v3_b) :multidim 2000 num-threads)
          (format t "~%--- Running Meta-Axiomatic Hardcore Test (Paradox) ---~%")
          (run-engine-parallel '(cross v3_a v3_b) :multidim 50 num-threads)

          (format t "~%--- Running Relativity Domain ---~%")
          (run-engine-parallel '(gamma 1.2) :relativity 20000 num-threads)

          (format t "~%--- Running Thermodynamics Domain ---~%")
          (run-engine-parallel '(carnot 0 t_cold) :thermo 50000 num-threads)

          (format t "~%--- Running Holography Domain ---~%")
          (run-engine-parallel '(entropy volume) :holography 200 num-threads)

          (format t "~%--- Running Logic Domain ---~%")
          (run-engine-parallel '(and p (not p)) :logic 200 num-threads)

          (format t "~%--- Running Hardware Domain (Silicon Lowering) ---~%")
          (run-engine-parallel '(and p (or q r)) :hardware 200 num-threads)

          (format t "~%--- Running Grand Unified Cross-Domain ---~%")
          (run-engine-parallel '(add (seq (h q2) (cnot q2 q1)) (carnot 0 t_cold)) :unified 200 num-threads)))))

(unless (boundp '*is-cli*) (main))
