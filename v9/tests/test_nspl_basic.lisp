(require :asdf)

(load "v9/src/nspl.lisp")
(use-package :nspl)

(defun run-tests ()
  (format t "Testing NSPL Serialization...~%")
  (let* ((ast '(add x y))
         (packet (ast-to-nspl :arithmetic ast)))
    (format t "Original AST: ~A~%" ast)
    (format t "Domain ID: ~D~%" (nspl-packet-domain-id packet))
    (format t "Payload Length: ~D~%" (nspl-packet-payload-length packet))

    (let ((bytes (serialize-nspl packet)))
      (format t "Serialized Bytes: ~A~%" bytes)

      (let* ((decoded-packet (deserialize-nspl bytes))
             (decoded-ast (nspl-to-ast decoded-packet)))
        (format t "Decoded Packet Domain: ~D~%" (nspl-packet-domain-id decoded-packet))
        (format t "Decoded AST (flat): ~A~%" decoded-ast)))))

(run-tests)
