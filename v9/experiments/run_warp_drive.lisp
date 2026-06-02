(require :asdf)

(defpackage :cognitive-engine (:use :cl))
(in-package :cognitive-engine)
(defvar *current-operators* nil)

(load "v9/src/engine.lisp")

(in-package :cognitive-engine)
(format t "--- Running Standalone Meta-Axiomatic Hardcore Test: WARP DRIVE ---~%")

(run-engine-parallel '(add_vel 0.8 0.8) :relativity 1000 (detect-cpu-cores))
