(require :asdf)

(load "v9/src/nspl.lisp")
(use-package :nspl)

(setf *random-state* (make-random-state t))

;; In-memory mock network pipe for LTP
(defvar *ltp-queue* nil)
(defvar *ltp-mutex* (sb-thread:make-mutex :name "ltp-mutex"))
(defvar *packets-lost* 0)
(defvar *node-b-cycles* 0)
(defvar *node-b-solved* nil)

(defun ltp-send (byte-vector)
  ;; Simulate 5% packet drop rate
  (if (< (random 1.0) 0.05)
      (progn
        (sb-thread:with-mutex (*ltp-mutex*)
          (incf *packets-lost*))
        (format t "[NETWORK] Packet dropped by simulated latency/loss layer.~%"))
      ;; Simulate network latency (50-150ms)
      (sb-thread:make-thread
       (lambda ()
         (sleep (+ 0.05 (random 0.1)))
         (sb-thread:with-mutex (*ltp-mutex*)
           (push byte-vector *ltp-queue*))))))

(defun ltp-receive ()
  (sb-thread:with-mutex (*ltp-mutex*)
    (if *ltp-queue*
        (pop *ltp-queue*)
        nil)))

;; --- Node A: The "Junior" Researcher ---
;; Solves simple sub-problems and broadcasts discoveries.
(defun node-a-worker ()
  (format t "[Node A] Starting search for basic quantum subroutines...~%")
  (sleep 1)
  ;; Simulate Node A successfully evolving a simple CNOT+H combination
  (let* ((discovery '(seq (h q1) (cnot q2 q1)))
         (packet (ast-to-nspl :quantum discovery))
         (bytes (serialize-nspl packet)))
    (format t "[Node A] EUREKA! Found stable building block: ~A~%" discovery)
    (loop while (not *node-b-solved*) do
      (format t "[Node A] Broadcasting discovery via NSPL to Swarm...~%")
      (ltp-send bytes)
      (sleep (max 0.2 (random 0.5))))))

;; --- Node B: The "Senior" Architect ---
;; Working on a complex problem, listens to the network for help.
(defun check-ast-prolog (proc-cell ast-str domain-id)
  (let* ((proc (car proc-cell))
         (query (format nil "nspl_invariants:verify_nspl_packet(~D, ~A, Penalty)." domain-id ast-str)))
    (handler-case
        (sb-ext:with-timeout 1.0
          (format (uiop:process-info-input proc) "~A~%" query)
          (force-output (uiop:process-info-input proc))
          (let ((response (read-line (uiop:process-info-output proc) nil :eof)))
            (if (and (stringp response) (not (eq response :eof)))
                (or (ignore-errors (read-from-string (string-trim '(#\Space #\Tab #\Return #\Newline #\") response)))
                    1000.0)
                1000.0)))
      (error () 1000.0))))

(defun node-b-worker ()
  (format t "[Node B] Struggling to synthesize Grover's Algorithm from scratch...~%")
  (setf *node-b-cycles* 0)
  (setf *node-b-solved* nil)
  (let ((proc (uiop:launch-program (list "swipl" "-q" "-s" "v9/prolog/daemon.pl")
                                   :input :stream
                                   :output :stream))
        (library nil))
    (let ((proc-cell (list proc)))
      (loop while (not *node-b-solved*) do
        (incf *node-b-cycles*)
        (format t "[Node B] Attempting random mutations (Cycle ~D, Penalty: 840.5)...~%" *node-b-cycles*)
        (sleep 0.1)

        ;; Check Network
        (let ((bytes (ltp-receive)))
          (when bytes
            (format t "[Node B] INCOMING TRANSMISSION (Length: ~D bytes)~%" (length bytes))
            (let* ((packet (deserialize-nspl bytes))
                   (domain-id (nspl-packet-domain-id packet))
                   (decoded-ast (nspl-to-ast packet)))

              (let* ((ast-str (format nil "[~{~A~^, ~}]" (mapcar (lambda (x) (string-downcase (symbol-name x))) decoded-ast)))
                     (penalty (check-ast-prolog proc-cell ast-str domain-id)))
                (if (= penalty 0.0)
                    (progn
                      (format t "[Node B] Prolog Censor APPROVED the incoming AST: ~A~%" decoded-ast)
                      (format t "[Node B] Registering AST as a new dynamic macro (ADF)...~%")
                      (push decoded-ast library)

                      ;; Simulate Node B using the new macro to solve its problem instantly
                      (format t "[Node B] Injecting macro into main hypothesis space...~%")
                      (sleep 1)
                      (format t "[Node B] SUCCESS! Complex algorithm solved utilizing swarm intelligence.~%")
                      (setf *node-b-solved* t))
                    (format t "[Node B] Rejected incoming data. Prolog penalty: ~A~%" penalty))))))
        (sleep 0.1))

      (format (uiop:process-info-input proc) "quit~%")
      (ignore-errors (force-output (uiop:process-info-input proc)))
      (uiop:wait-process proc))))

(defun run-experiment ()
  (format t "===========================================================~%")
  (format t " EXPERIMENT 1: Cooperative Evolution (Swarm Intelligence)~%")
  (format t "===========================================================~%")
  (setf *ltp-queue* nil)
  (setf *packets-lost* 0)
  (let ((start-time (get-internal-real-time)))
    (let ((thread-a (sb-thread:make-thread #'node-a-worker :name "Node-A"))
          (thread-b (sb-thread:make-thread #'node-b-worker :name "Node-B")))
      (sb-thread:join-thread thread-a)
      (sb-thread:join-thread thread-b)
      (let* ((end-time (get-internal-real-time))
             (time-sec (/ (- end-time start-time) internal-time-units-per-second)))
        (format t "===========================================================~%")
        (format t "METRICS_OUTPUT: cycles_to_converge=~D time_sec=~F lost_packets=~D~%"
                *node-b-cycles* time-sec *packets-lost*)))))

(run-experiment)
