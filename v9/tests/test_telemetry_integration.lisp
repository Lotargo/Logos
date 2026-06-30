(require :asdf)
(defpackage :cognitive-engine (:use :cl))
(defparameter cognitive-engine::*is-cli* t)
(load "v9/src/engine.lisp")

(in-package :cognitive-engine)

(format t "--- Testing Telemetry Integration ---~%")
(log-telemetry "integration_test" "Verifying Lisp to Python Telemetry pipeline")
(log-fitness-telemetry "test-candidate" 0.99 '(+ x 0) 'x)
(format t "Done.~%")
