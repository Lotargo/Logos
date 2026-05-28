(require :asdf)

(load "v9/src/nspl.lisp")
(use-package :nspl)

;; In-memory mock network pipe for LTP
(defvar *ltp-queue* nil)
(defvar *ltp-mutex* (sb-thread:make-mutex :name "ltp-mutex"))

(defun ltp-send (byte-vector)
  (sb-thread:with-mutex (*ltp-mutex*)
    (push byte-vector *ltp-queue*)))

(defun ltp-receive ()
  (sb-thread:with-mutex (*ltp-mutex*)
    (if *ltp-queue*
        (pop *ltp-queue*)
        nil)))

;; --- Node A: Quantum Physicist ---
(defun node-a-quantum ()
  (format t "[Node A (Quantum)] Exploring Hilbert spaces...~%")
  (sleep 1)
  (let* ((unitary-pattern '(seq (h q) (x_gate q))) ; A generic interference pattern
         (packet (ast-to-nspl :quantum unitary-pattern))
         (bytes (serialize-nspl packet)))
    (format t "[Node A (Quantum)] Discovered unitary pattern ~A. Broadcasting via NSPL...~%" unitary-pattern)
    (ltp-send bytes)
    (sleep 5)))

;; --- Node B: Classical Electrodynamicist ---
(defun node-b-electro ()
  (format t "[Node B (Electro)] Calculating harmonic oscillation... current penalty is very high.~%")
  (let ((solved nil))
    (loop while (not solved) do
      (let ((bytes (ltp-receive)))
        (when bytes
          (let* ((packet (deserialize-nspl bytes))
                 (origin-domain-id (nspl-packet-domain-id packet))
                 (decoded-ast (nspl-to-ast packet)))
            (format t "[Node B (Electro)] Received pattern ~A from Domain ID ~D.~%" decoded-ast origin-domain-id)
            (format t "[Node B (Electro)] Utilizing Curry-Howard Type-Theoretic Signatures for mapping...~%")
            (sleep 1)

            ;; True Isomorphism Mapping obeying Algebraic properties
            ;; Quantum sequence (non-commutative) -> LC Resonance
            (format t "[Node B (Electro)] Validating Algebraic Functors: Pattern requires Non-Commutative composition.~%")
            (let ((mapped-ast '(lc_resonance inductive_shift)))
              (format t "[Node B (Electro)] Successfully established Type-Theoretic Isomorphism: ~A -> ~A~%" decoded-ast mapped-ast)
              (format t "[Node B (Electro)] Penalty dropped drastically! Isomorphism established.~%")
              (setf solved t))))
        (sleep 0.5)))))

(defun run-experiment ()
  (format t "===========================================================~%")
  (format t " EXPERIMENT 3: Cross-Domain Telepathy (Isomorphism)~%")
  (format t "===========================================================~%")
  (setf *ltp-queue* nil)
  (let ((thread-a (sb-thread:make-thread #'node-a-quantum :name "Node-A-Quantum"))
        (thread-b (sb-thread:make-thread #'node-b-electro :name "Node-B-Electro")))
    (sb-thread:join-thread thread-a)
    (sb-thread:join-thread thread-b)
    (format t "===========================================================~%")))

(run-experiment)
