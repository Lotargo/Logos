(require :asdf)

(defpackage :cognitive-engine (:use :cl))
(in-package :cognitive-engine)
(defvar *current-operators* nil)

(load "v9/src/engine.lisp")

(in-package :cognitive-engine)
(format t "--- Running Standalone Meta-Axiomatic Hardcore Test: HSLG Part 2 (Information Paradox) ---~%")

;; The seed is the paradox of information loss during merger S_final - (S1 + S2) < 0
(run-engine-parallel '(sub (add (entropy s1) (entropy s2)) (entropy s_final)) :unified 1000 (detect-cpu-cores))
