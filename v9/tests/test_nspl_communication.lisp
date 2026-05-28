(require :asdf)

(load "v9/src/nspl.lisp")
(use-package :nspl)

;; In-memory mock network pipe for LTP
(defvar *ltp-queue* nil)
(defvar *ltp-mutex* (sb-thread:make-mutex :name "ltp-mutex"))

(defun ltp-send (byte-vector)
  "Sends a byte vector over the LTP mock network."
  (sb-thread:with-mutex (*ltp-mutex*)
    (push byte-vector *ltp-queue*)))

(defun ltp-receive ()
  "Receives a byte vector from the LTP mock network, popping it from the queue."
  (sb-thread:with-mutex (*ltp-mutex*)
    (if *ltp-queue*
        (pop *ltp-queue*)
        nil)))

;; Logos Node A (Sender)
(defun logos-node-a ()
  (format t "[Node A] Initiating...~%")
  (let ((knowledge-to-share '((add x y) (and p q) (h q) (unknown_op p) (h x))))
    (dolist (ast knowledge-to-share)
      (let* ((domain (cond ((eq (car ast) 'add) :arithmetic)
                           ((eq (car ast) 'and) :logic)
                           ((eq (car ast) 'h) :quantum)
                           (t :arithmetic)))
             (packet (ast-to-nspl domain ast))
             (bytes (serialize-nspl packet)))
        (format t "[Node A] Serialized AST ~A into binary NSPL. Sending...~%" ast)
        (ltp-send bytes)
        (sleep 0.5)))))

;; Prolog Validation Interface for Node B
(defun check-nspl-with-prolog (domain-id decoded-ast proc-cell)
  (let* ((proc (car proc-cell))
         ;; Format the AST as a valid Prolog list (e.g. "[add, x, y]")
         (ast-str (format nil "[~{~A~^, ~}]" (mapcar (lambda (x)
                                                       (if (string-equal (symbol-name x) "UNKNOWN")
                                                           "'unknown'"
                                                           (string-downcase (symbol-name x))))
                                                     decoded-ast)))
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
      (error (e)
        (format t "[Node B ERROR] Prolog validation failed: ~A~%" e)
        1000.0))))

;; Logos Node B (Receiver)
(defun logos-node-b (expected-messages)
  (format t "[Node B] Initiating and waiting for messages...~%")
  (let ((received 0)
        (proc (uiop:launch-program (list "swipl" "-q" "-s" "v9/prolog/daemon.pl")
                                   :input :stream
                                   :output :stream)))
    (let ((proc-cell (list proc)))
      (loop while (< received expected-messages) do
        (let ((bytes (ltp-receive)))
          (if bytes
              (progn
                (incf received)
                (format t "[Node B] Received binary packet of length ~D.~%" (length bytes))
                (let* ((packet (deserialize-nspl bytes))
                       (domain-id (nspl-packet-domain-id packet))
                       (decoded-ast (nspl-to-ast packet)))
                  (format t "[Node B] Decoded packet. Domain ID: ~D. AST: ~A~%" domain-id decoded-ast)

                  ;; Perform Semantic Prolog Validation
                  (let ((penalty (check-nspl-with-prolog domain-id decoded-ast proc-cell)))
                    (if (= penalty 0.0)
                        (format t "[Node B] Prolog Validation SUCCESS (Penalty: 0.0). AST makes sense.~%")
                        (format t "[Node B] Prolog Validation REJECTED (Penalty: ~A). AST is gibberish or invalid!~%" penalty)))))
              (sleep 0.1))))

      (format (uiop:process-info-input proc) "quit~%")
      (ignore-errors (force-output (uiop:process-info-input proc)))
      (uiop:wait-process proc))))

(defun run-ltp-simulation ()
  (format t "--- Starting Lisp Transport Protocol (LTP) Simulation ---~%")
  (setf *ltp-queue* nil)
  (let ((thread-a (sb-thread:make-thread #'logos-node-a :name "Logos-Node-A"))
        (thread-b (sb-thread:make-thread (lambda () (logos-node-b 5)) :name "Logos-Node-B")))
    (sb-thread:join-thread thread-a)
    (sb-thread:join-thread thread-b)
    (format t "--- Simulation Complete ---~%")))

(run-ltp-simulation)
