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
          (random-element *current-constants*)
          (random-element *current-variables*))
      (let ((op (car ast))
            (args (cdr ast)))
        (if (< (random 10) 3) ; 30% chance to mutate the operator
            ;; If mutating operator, keep same arity by choosing ops based on domain if possible,
            ;; but for simplicity we just mutate it randomly and let Prolog reject bad arity.
            (cons (random-element *current-operators*) args)
            ;; Otherwise, mutate a random child node
            (let ((mutated-args (copy-list args))
                  (idx (random (length args))))
              (setf (nth idx mutated-args) (mutate (nth idx mutated-args)))
              (cons op mutated-args))))))

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
      (string= response "true"))))

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
      (loop for i from 1 to iterations
            do (let ((hypothesis (mutate base-ast)))
                 (if (check-with-prolog hypothesis domain proc)
                     (progn
                       (format t "[Thread ~D] [ACCEPT] Iteration ~D: ~A~%" thread-id i hypothesis)
                       (setf result hypothesis)
                       (return)))))
      ;; Clean up the Prolog daemon
      (format (uiop:process-info-input proc) "quit~%")
      (ignore-errors (force-output (uiop:process-info-input proc)))
      (uiop:wait-process proc)
      result)))

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
            (format t "Found valid hypotheses:~%")
            (loop for res in results do (format t "  ~A~%" res)))
          (format t "No valid hypotheses found.~%")))))

(defun main ()
  ;; Start with an AST that has division by zero
  (let ((arith-base '(/ (+ x 1) 0))
        ;; A calculus AST that shouldn't be accepted (e.g. invalid arity for sin)
        (calc-base '(deriv (sin x t) x))
        ;; Quantum AST that is invalid (e.g. seq needs valid quantum nodes like q1)
        (quant-base '(seq q1 0))
        ;; Use a sensible default of 4 threads
        (num-threads 4))

    (format t "~%--- Running Arithmetic Domain ---~%")
    (run-engine-parallel arith-base :arithmetic 20 num-threads)

    (format t "~%--- Running Calculus Domain ---~%")
    (run-engine-parallel calc-base :calculus 20 num-threads)

    (format t "~%--- Running Quantum Domain ---~%")
    ;; Provide a better base string for quantum that mutating once or twice fixes it easily.
    ;; cnot takes 2 arguments, control and target. seq takes 2 arguments.
    ;; let's use a base that just needs a small mutation
    (run-engine-parallel '(seq q1 q1) :quantum 500 num-threads)))

(main)
