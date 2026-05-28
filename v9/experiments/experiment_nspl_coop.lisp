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
    (format t "[Node A] Broadcasting discovery via NSPL to Swarm...~%")
    (ltp-send bytes)
    (sleep 5)))

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
  (let ((proc (uiop:launch-program (list "swipl" "-q" "-s" "v9/prolog/daemon.pl")
                                   :input :stream
                                   :output :stream))
        (library nil)
        (solved nil))
    (let ((proc-cell (list proc)))
      (loop while (not solved) do
        (format t "[Node B] Attempting random mutations (Penalty: 840.5)...~%")
        (sleep 1)

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
                      (setf solved t))
                    (format t "[Node B] Rejected incoming data. Prolog penalty: ~A~%" penalty))))))
        (sleep 1))

      (format (uiop:process-info-input proc) "quit~%")
      (ignore-errors (force-output (uiop:process-info-input proc)))
      (uiop:wait-process proc))))

(defun run-experiment ()
  (format t "===========================================================~%")
  (format t " EXPERIMENT 1: Cooperative Evolution (Swarm Intelligence)~%")
  (format t "===========================================================~%")
  (setf *ltp-queue* nil)
  (let ((thread-a (sb-thread:make-thread #'node-a-worker :name "Node-A"))
        (thread-b (sb-thread:make-thread #'node-b-worker :name "Node-B")))
    (sb-thread:join-thread thread-a)
    (sb-thread:join-thread thread-b)
    (format t "===========================================================~%")))

(run-experiment)
