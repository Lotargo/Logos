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

(defun check-with-prolog (ast domain)
  "Sends the AST to SWI-Prolog to check if it unifies with invariants.
   Returns T if Prolog accepts it (Censor approves), NIL otherwise."
  (let* ((prolog-term (lisp-to-prolog ast))
         ;; Query the universal censor module, passing the domain
         (query (format nil "censor(~A, ~A)." (string-downcase (symbol-name domain)) prolog-term))
         (command (list "swipl" "-q" "-s" "v7/rules.pl" "-g" query "-t" "halt"))
         (success nil))
    (multiple-value-bind (out err code)
        (uiop:run-program command :output :string :error-output :string :ignore-error-status t)
      (declare (ignore out err))
      (setf success (= code 0)))
    success))

;; =======================================================================
;; 4. Main Universal Cognitive Engine Loop
;; =======================================================================

(defun run-engine (base-ast domain iterations)
  (set-domain domain)
  (format t "=== Starting Universal Cognitive Engine v7 ===~%")
  (format t "Domain: ~A~%" domain)
  (format t "Base AST: ~A~%" base-ast)
  (loop for i from 1 to iterations
        do (let ((hypothesis (mutate base-ast)))
             (format t "~%Iteration ~D~%" i)
             (format t "Hypothesis: ~A~%" hypothesis)
             (format t "Prolog term: ~A~%" (lisp-to-prolog hypothesis))

             (if (check-with-prolog hypothesis domain)
                 (progn
                   (format t "[ACCEPT] Prolog censor approved the hypothesis!~%")
                   (return hypothesis))
                 (format t "[REJECT] Prolog censor rejected the hypothesis.~%")))))

(defun main ()
  ;; Start with an AST that has division by zero
  (let ((arith-base '(/ (+ x 1) 0))
        ;; A calculus AST that shouldn't be accepted (e.g. invalid arity for sin)
        (calc-base '(deriv (sin x t) x))
        ;; Quantum AST that is invalid (e.g. seq needs valid quantum nodes like q1)
        (quant-base '(seq q1 0)))

    (format t "~%--- Running Arithmetic Domain ---~%")
    (run-engine arith-base :arithmetic 20)

    (format t "~%--- Running Calculus Domain ---~%")
    (run-engine calc-base :calculus 20)

    (format t "~%--- Running Quantum Domain ---~%")
    ;; Provide a better base string for quantum that mutating once or twice fixes it easily.
    ;; cnot takes 2 arguments, control and target. seq takes 2 arguments.
    ;; let's use a base that just needs a small mutation
    (run-engine '(seq q1 q1) :quantum 500)))

(main)
