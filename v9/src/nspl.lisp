(defpackage :nspl
  (:use :cl)
  (:export :nspl-packet
           :make-nspl-packet
           :nspl-packet-domain-id
           :nspl-packet-op-id
           :nspl-packet-payload-length
           :nspl-packet-data
           :serialize-nspl
           :deserialize-nspl
           :ast-to-nspl
           :nspl-to-ast))

(in-package :nspl)

;; Simple structure mapping
(defstruct nspl-packet
  (domain-id 0 :type (unsigned-byte 8))
  (op-id 0 :type (unsigned-byte 8))
  (payload-length 0 :type (unsigned-byte 16))
  (data (make-array 0 :element-type '(unsigned-byte 8))))

;; -----------------------------------------
;; Basic Domain and Operator ID Mappings
;; -----------------------------------------

(defvar *domain-to-id*
  '((:arithmetic . 1)
    (:logic . 2)
    (:quantum . 3)
    (:relativity . 4)
    (:thermo . 5)))

(defvar *id-to-domain*
  '((1 . :arithmetic)
    (2 . :logic)
    (3 . :quantum)
    (4 . :relativity)
    (5 . :thermo)))

;; Mapping common operators and vars to byte IDs for the payload
(defvar *sym-to-byte*
  (let ((h (make-hash-table :test 'equal)))
    (setf (gethash 'nspl::add h) 10)
    (setf (gethash 'nspl::sub h) 11)
    (setf (gethash 'nspl::mul h) 12)
    (setf (gethash 'nspl::div h) 13)
    (setf (gethash 'nspl::and h) 20)
    (setf (gethash 'nspl::or h) 21)
    (setf (gethash 'nspl::not h) 22)
    (setf (gethash 'nspl::h h) 30)
    (setf (gethash 'nspl::x_gate h) 31)
    (setf (gethash 'nspl::cnot h) 32)
    (setf (gethash 'nspl::x h) 100)
    (setf (gethash 'nspl::y h) 101)
    (setf (gethash 'nspl::z h) 102)
    (setf (gethash 'nspl::p h) 103)
    (setf (gethash 'nspl::q h) 104)
    (setf (gethash 'nspl::q1 h) 105)
    (setf (gethash 'nspl::q2 h) 106)
    (setf (gethash 'nspl::seq h) 107)
    (setf (gethash 'nspl::m h) 108)
    (setf (gethash 'nspl::r h) 109)
    (setf (gethash 'nspl::l_p h) 110)
    (setf (gethash 'nspl::lc_resonance h) 111)
    (setf (gethash 'nspl::inductive_shift h) 112)
    h))

(defun ast-node-to-bytes (node)
  "Recursively converts an AST into a list of bytes."
  (cond
    ((null node) nil)
    ((numberp node)
     (list 255 (mod (floor node) 255)))
    ((symbolp node)
     (let* ((sym-name (string-upcase (symbol-name node)))
            (interned-sym (intern sym-name :nspl))
            (b (gethash interned-sym *sym-to-byte*)))
       (if b (list b) (list 254))))
    ((listp node)
     (append (ast-node-to-bytes (car node))
             (apply #'append (mapcar #'ast-node-to-bytes (cdr node)))))))

(defun get-sym-for-byte (b)
  (cond ((= b 10) 'add)
        ((= b 11) 'sub)
        ((= b 12) 'mul)
        ((= b 13) 'div)
        ((= b 20) 'and)
        ((= b 21) 'or)
        ((= b 22) 'not)
        ((= b 30) 'h)
        ((= b 31) 'x_gate)
        ((= b 32) 'cnot)
        ((= b 100) 'x)
        ((= b 101) 'y)
        ((= b 102) 'z)
        ((= b 103) 'p)
        ((= b 104) 'q)
        ((= b 105) 'q1)
        ((= b 106) 'q2)
        ((= b 107) 'seq)
        ((= b 108) 'm)
        ((= b 109) 'r)
        ((= b 110) 'l_p)
        ((= b 111) 'lc_resonance)
        ((= b 112) 'inductive_shift)
        (t 'unknown)))

(defvar *byte-to-sym*
  (let ((h (make-hash-table :test 'eql)))
    (maphash (lambda (k v) (setf (gethash v h) k)) *sym-to-byte*)
    h))

;; -----------------------------------------
;; Serialization / Deserialization
;; -----------------------------------------

(defun serialize-nspl (packet)
  "Converts an NSPL-PACKET struct into a raw byte vector."
  (let* ((len (nspl-packet-payload-length packet))
         (vec (make-array (+ 4 len) :element-type '(unsigned-byte 8))))
    (setf (aref vec 0) (nspl-packet-domain-id packet))
    (setf (aref vec 1) (nspl-packet-op-id packet))
    (setf (aref vec 2) (ldb (byte 8 8) len))
    (setf (aref vec 3) (ldb (byte 8 0) len))
    (replace vec (nspl-packet-data packet) :start1 4)
    vec))

(defun deserialize-nspl (vec)
  "Parses a byte vector back into an NSPL-PACKET struct."
  (if (< (length vec) 4)
      (error "Packet too short"))
  (let* ((domain-id (aref vec 0))
         (op-id (aref vec 1))
         (len (dpb (aref vec 2) (byte 8 8) (aref vec 3)))
         (data (make-array len :element-type '(unsigned-byte 8))))
    (when (< (length vec) (+ 4 len))
      (error "Packet length mismatch"))
    (replace data vec :start2 4 :end2 (+ 4 len))
    (make-nspl-packet :domain-id domain-id
                      :op-id op-id
                      :payload-length len
                      :data data)))

(defun ast-to-nspl (domain ast)
  "Converts a domain and a Lisp AST into an NSPL binary packet."
  (let* ((domain-id (or (cdr (assoc domain *domain-to-id*)) 0))
         (op-sym (if (and (listp ast) (symbolp (car ast)))
                     (intern (string-upcase (symbol-name (car ast))) :nspl)
                     nil))
         (op-id (if op-sym (or (gethash op-sym *sym-to-byte*) 0) 0))
         (bytes (ast-node-to-bytes ast))
         (payload (make-array (length bytes) :element-type '(unsigned-byte 8) :initial-contents bytes)))
    (make-nspl-packet :domain-id domain-id
                      :op-id op-id
                      :payload-length (length payload)
                      :data payload)))

(defun nspl-to-ast (packet)
  "Converts an NSPL binary packet back to a partial AST string/list representation for Prolog checking."
  ;; In this mock implementation, we just translate bytes back to symbols.
  ;; For an exact AST reconstruction, we'd need arity checking (like in Lisp generator).
  (let ((syms nil)
        (data (nspl-packet-data packet))
        (i 0))
    (loop while (< i (length data)) do
      (let ((b (aref data i)))
        (cond
          ((= b 255)
           (push (aref data (1+ i)) syms)
           (incf i 2))
          ((= b 254)
           (push 'unknown syms)
           (incf i 1))
          (t
           (push (get-sym-for-byte b) syms)
           (incf i 1)))))
    (nreverse syms)))
