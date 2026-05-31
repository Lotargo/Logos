(require :asdf)
(defpackage :cognitive-engine (:use :cl))
(in-package :cognitive-engine)
(defvar *current-dataset* nil)
(defvar *regression-vars* nil)
(defvar *is-cli* t)
(load "v9/src/engine.lisp")

(format t "--- Running The Ultimate Benchmark: Rediscovery of Physics (v8) ---~%")

;; Goal 1: Rediscover Kepler's Third Law from CSV
(format t "== Goal 1: Rediscover Kepler's Third Law ==~%")
(setf *regression-vars* '(a))
(setf *current-dataset* "v9/data/kepler_data.csv")
(run-engine-parallel '(mul a a) :regression 1 1)

;; Goal 2: Quantum Algorithms - Grover's Search (represented as unitary matrices matching an oracle target)
(format t "== Goal 2: Discover Grover's Algorithm via Unitary Matrices ==~%")
(run-engine-parallel '(seq (h q1) (seq (oracle q1 q2) (h q1))) :quantum 1 1)

;; Goal 3: Rediscover Relativistic Kinematics from CSV
(format t "== Goal 3: Rediscover Relativistic Kinematics (Lorentz Factor) ==~%")
(setf *regression-vars* '(v c))
(setf *current-dataset* "v9/data/relativity_data.csv")
(run-engine-parallel '(div 1 (sub 1 (div (mul v v) (mul c c)))) :regression 1 1)
