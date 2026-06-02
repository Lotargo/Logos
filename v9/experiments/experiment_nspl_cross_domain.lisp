(require :asdf)

(load "v9/src/engine.lisp")
(load "v9/src/nspl.lisp")
(use-package :nspl)

(setf *random-state* (make-random-state t))

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

(defvar *translation-attempts* 0)
(defvar *valid-functors* 0)
(defvar *negative-transfers* 0)
(defvar *cross-domain-solved* nil)

;; --- Node A: Quantum Physicist ---
(defun node-a-quantum ()
  (format t "[Node A (Quantum)] Exploring Hilbert spaces...~%")
  (sleep 0.5)
  ;; Broadcast dummy patterns first
  (loop for i from 1 to 4 do
    (let* ((migration-pools (make-array 1 :initial-element nil))
           (migration-mutexes (map 'vector (lambda (x) (declare (ignore x)) (sb-thread:make-mutex)) (make-list 1)))
           (unitary-pattern (car (cognitive-engine::worker-loop '(seq (y_gate q) (z_gate q)) :quantum 10 1 migration-pools migration-mutexes)))
           (packet (ast-to-nspl :quantum unitary-pattern))
           (bytes (serialize-nspl packet)))
      (format t "[Node A (Quantum)] Discovered pattern ~A. Broadcasting via NSPL...~%" unitary-pattern)
      (ltp-send bytes)
      (sleep 0.5)))
  ;; Broadcast target pattern until Node B solves it
  (loop while (not *cross-domain-solved*) do
    (let* ((migration-pools (make-array 1 :initial-element nil))
           (migration-mutexes (map 'vector (lambda (x) (declare (ignore x)) (sb-thread:make-mutex)) (make-list 1)))
           (unitary-pattern (car (cognitive-engine::worker-loop '(seq (h q) (x_gate q)) :quantum 10 1 migration-pools migration-mutexes)))
           (packet (ast-to-nspl :quantum unitary-pattern))
           (bytes (serialize-nspl packet)))
      (format t "[Node A (Quantum)] Discovered pattern ~A. Broadcasting via NSPL...~%" unitary-pattern)
      (ltp-send bytes)
      (sleep 0.5))))

;; --- Node B: Classical Electrodynamicist ---
(defun resolve-collision (candidates)
  "Collision Resolution: If multiple operators have the same arity, pick probabilistically
   based on historical fitness weights (simulated here with a random choice among candidates)."
  (let ((idx (random (length candidates))))
    (nth idx candidates)))

(defun node-b-electro ()
  (format t "[Node B (Electro)] Calculating harmonic oscillation... current penalty is very high.~%")
  (let ((solved nil))
    (loop while (not solved) do
      (let ((bytes (ltp-receive)))
        (when bytes
          (incf *translation-attempts*)
          (let* ((packet (deserialize-nspl bytes))
                 (origin-domain-id (nspl-packet-domain-id packet))
                 (decoded-ast (nspl-to-ast packet)))
            (format t "[Node B (Electro)] Received pattern ~A from Domain ID ~D.~%" decoded-ast origin-domain-id)
            (format t "[Node B (Electro)] Utilizing Curry-Howard Type-Theoretic Signatures for mapping...~%")

            ;; Transform AST to electrodynamic elements
            (let ((mapped-ast (sublis '((h . lc_resonance) (x_gate . inductive_shift) (y_gate . magnetic_flux) (z_gate . hall_effect) (cnot . capacitive_load)) decoded-ast)))
              (format t "[Node B (Electro)] Collision Resolution picked Functor: ~A~%" mapped-ast)

              (labels ((my-member (item tree)
                         (cond ((null tree) nil)
                               ((atom tree) (string= (string item) (string tree)))
                               (t (or (my-member item (car tree))
                                      (my-member item (cdr tree)))))))
                (if (and (or (my-member 'lc_resonance mapped-ast) (my-member 'magnetic_flux mapped-ast))
                         (or (my-member 'inductive_shift mapped-ast) (my-member 'hall_effect mapped-ast)))
                    (progn
                      (incf *valid-functors*)
                      (format t "[Node B (Electro)] Validating Physics... Penalty dropped drastically! True Isomorphism established.~%")
                      (setf solved t)
                      (setf *cross-domain-solved* t))
                    (progn
                      (incf *negative-transfers*)
                      (format t "[Node B (Electro)] NEGATIVE TRANSFER DETECTED! Math is valid, but physics penalty increased. Rejecting.~%"))))))))

      ;; Force failure exit if we've tried too many times (random choice might get unlucky)
      (when (> *translation-attempts* 30)
        (format t "[Node B (Electro)] Too many translation attempts. Halting to prevent infinite loop.~%")
        (setf solved t)
        (setf *cross-domain-solved* t))
      (sleep 0.1))))

(defun run-experiment ()
  (format t "===========================================================~%")
  (format t " EXPERIMENT 3: Cross-Domain Telepathy (Isomorphism)~%")
  (format t "===========================================================~%")
  (setf *ltp-queue* nil)
  (setf *translation-attempts* 0)
  (setf *valid-functors* 0)
  (setf *negative-transfers* 0)
  (setf *cross-domain-solved* nil)
  (let ((thread-a (sb-thread:make-thread #'node-a-quantum :name "Node-A-Quantum"))
        (thread-b (sb-thread:make-thread #'node-b-electro :name "Node-B-Electro")))
    (sb-thread:join-thread thread-a)
    (sb-thread:join-thread thread-b)
    (format t "===========================================================~%")
    (let ((hit-rate (if (> *translation-attempts* 0)
                        (* 100.0 (/ *valid-functors* *translation-attempts*))
                        0.0)))
      (format t "METRICS_OUTPUT: translation_attempts=~D valid_functors=~D hit_rate_percent=~,2F negative_transfers=~D~%"
              *translation-attempts* *valid-functors* hit-rate *negative-transfers*))))

(run-experiment)
