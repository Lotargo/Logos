(require :asdf)
(defpackage :cognitive-engine (:use :cl))
(in-package :cognitive-engine)
(load "v7/engine/engine.lisp")
(in-package :cognitive-engine)

(defun run-nlp-stress-test ()
  (format t "========================================================~%")
  (format t "  V7 COGNITIVE ENGINE - NLP STRESS TEST (HARDENED)~%")
  (format t "========================================================~%")

  (let ((num-threads (detect-cpu-cores)))

    (format t "~%[TEST 1] \"What are you?\" (Target: identity, artificial)~%")
    (setf *nlp-target-tags* "[identity, artificial]")
    (run-engine-parallel '(sentence (np (pronoun i)) (vp (verb am))) :nlp 2000 num-threads)

    (format t "~%[TEST 2] \"What is your purpose?\" (Target: action, compute, data)~%")
    (setf *nlp-target-tags* "[action, compute, data]")
    (run-engine-parallel '(sentence (np (pronoun i)) (vp (verb am))) :nlp 2000 num-threads)

    (format t "~%[TEST 3] \"Are you human?\" (Target: negative, biological)~%")
    (setf *nlp-target-tags* "[negative, biological]")
    (run-engine-parallel '(sentence (np (pronoun i)) (vp (verb am))) :nlp 2000 num-threads)

    (format t "~%[TEST 4] \"Say hello.\" (Target: social, start)~%")
    (setf *nlp-target-tags* "[social, start]")
    (run-engine-parallel '(sentence (greeting hello) (sentence (np (pronoun i)) (vp (verb am)))) :nlp 2000 num-threads)

    (format t "~%========================================================~%")
    (format t "Test completed.~%")))

(run-nlp-stress-test)
