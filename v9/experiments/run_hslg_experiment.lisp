(require :asdf)

(defpackage :cognitive-engine (:use :cl))
(in-package :cognitive-engine)
(defvar *current-operators* nil)

(load "v9/src/engine.lisp")

(in-package :cognitive-engine)
(format t "--- Running Standalone Meta-Axiomatic Hardcore Test: HSLG 3D->4D ---~%")

;; The seed is the paradox of classical gravity: limit as r->0 of 1/r
(run-engine-parallel '(limit (div 1 r) r 0) :calculus 1000 (detect-cpu-cores))
