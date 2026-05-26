(require :asdf)
(defpackage :cognitive-engine (:use :cl))
(defparameter cognitive-engine::*is-cli* t)

(defpackage :cognitive-engine-breaker (:use :cl))
(in-package :cognitive-engine-breaker)

(defvar *is-cli* t)
(defvar *regression-vars* nil)
(defvar *current-dataset* nil)

;; Load the main engine
(load "v8/src/engine.lisp")

;; We also need access to the check-with-prolog internals directly to test raw ASTs
(defun check-raw-ast (ast domain)
  (let* ((proc (uiop:launch-program (list "swipl" "-q" "-s" "v8/prolog/daemon.pl")
                                    :input :stream :output :stream))
         (proc-cell (list proc))
         (penalty (cognitive-engine::check-with-prolog ast domain proc-cell :target)))
    (format (uiop:process-info-input proc) "quit~%")
    (ignore-errors (force-output (uiop:process-info-input proc)))
    (uiop:wait-process proc)
    penalty))

(format t "========================================================~%")
(format t "          V8 ENGINE BREAKER TEST SUITE                  ~%")
(format t "========================================================~%~%")

(format t "== TEST 1: Deeply Nested AST (Stack Overflow / Bloat Check) ==~%")
(defun generate-deep-ast (depth base)
  (if (<= depth 0)
      base
      (list 'add (generate-deep-ast (1- depth) base) 'x)))

(let* ((deep-ast (generate-deep-ast 2000 'x))
       (penalty (check-raw-ast deep-ast :arithmetic)))
  (format t "Resulting penalty for depth 2000 arithmetic AST: ~,2F~%" penalty))


(format t "~%== TEST 2: Cross-Domain Type Violation (Quantum Matrix inside Thermodynamics) ==~%")
(let* ((invalid-ast '(carnot (seq (h q1) (cnot q1 q2)) t_cold))
       (penalty (check-raw-ast invalid-ast :unified)))
  (format t "Resulting penalty for Quantum logic inside Thermo equation: ~,2F~%" penalty))


(format t "~%== TEST 3: Math Anomaly (Division by zero) ==~%")
(let* ((div-zero-ast '(div x (sub 1 1)))
       (penalty (check-raw-ast div-zero-ast :arithmetic)))
  (format t "Resulting penalty for explicit Division by Zero: ~,2F~%" penalty))


(format t "~%== TEST 4: Non-existent Operator Check ==~%")
(let* ((fake-op-ast '(magic_op x y))
       (penalty (check-raw-ast fake-op-ast :unified)))
  (format t "Resulting penalty for fake operator: ~,2F~%" penalty))


(format t "~%== TEST 5: Extreme Noise Regression Search ==~%")
(format t "Attempting to find an equation for a highly non-linear, noisy dataset.~%")
(setf *regression-vars* '(x1 x2 x3))
(setf *current-dataset* "v8/data/extreme_noise_data.csv")

;; Run the engine on regression domain for 1000 iterations to see if it hangs or outputs anything useful
(handler-case
    (cognitive-engine::run-engine-parallel '(add x1 x2) :regression 1000 (cognitive-engine::detect-cpu-cores))
  (error (e) (format t "Engine crashed during extreme noise search: ~A~%" e)))

(format t "~%========================================================~%")
(format t "          BREAKER TESTS COMPLETED                       ~%")
(format t "========================================================~%")
