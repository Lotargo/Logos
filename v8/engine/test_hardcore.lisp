(require :asdf)

(defpackage :cognitive-engine (:use :cl))
(in-package :cognitive-engine)
(defvar *current-operators* nil)

(load "v8/engine/engine.lisp")

(in-package :cognitive-engine)
(format t "--- Running First-Principle Engine Test (v8) ---~%")
;; Test basic Boolean logic evaluation and Occam's Razor
(run-engine-parallel '(and true p) :logic 100 2)
