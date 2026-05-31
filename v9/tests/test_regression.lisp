(require :asdf)

(defpackage :cognitive-engine (:use :cl))
(in-package :cognitive-engine)
(defvar *current-operators* nil)

(load "v9/src/engine.lisp")

(in-package :cognitive-engine)
(format t "--- Running Symbolic Regression First-Principle Test (v8) ---~%")
(format t "Goal: Discover Newtonian Gravity purely from CSV data and Root Axioms.~%")
;; Starting from a somewhat related AST to test if it can discover (div (mul m1 m2) (mul r r))
(run-engine-parallel '(div (mul m1 m2) (mul r r)) :regression 1 1)
