;;; CFFI wrapper for sonata_cuda.dll (GPU + CPU SIMD backends)
;;; Load: (load "cuda/cffi.lisp")
;;; Usage: (eval-ast-sse ast-opcodes ast-args data-array n-rows n-vars &key backend)
;;;   backend ::= :auto | :cuda | :cpu
;;;   :auto  → try CUDA, fall back to CPU

(defpackage :sonata-engine
  (:use :cl :cffi)
  (:export
   #:*backend*
   #:*backend-name*
   #:load-engine
   #:shutdown-engine
   #:eval-ast-sse
   #:eval-ast-sse-batch
   #:cpu-simd-level
   #:cpu-force-simd-level
   #:ast-op-add
   #:ast-op-sub
   #:ast-op-mul
   #:ast-op-div
   #:ast-op-sin
   #:ast-op-cos
   #:ast-op-exp
   #:ast-op-log
   #:ast-op-sqrt
   #:ast-op-neg
   #:ast-op-var
   #:ast-op-const
   #:flatten-ast
   #:demo
   #:demo-cpu))

(in-package :sonata-engine)

;;; --- AST opcodes ---
(defconstant +ast-op-add   1)
(defconstant +ast-op-sub   2)
(defconstant +ast-op-mul   3)
(defconstant +ast-op-div   4)
(defconstant +ast-op-sin   5)
(defconstant +ast-op-cos   6)
(defconstant +ast-op-exp   7)
(defconstant +ast-op-log   8)
(defconstant +ast-op-sqrt  9)
(defconstant +ast-op-neg   10)
(defconstant +ast-op-var   11)
(defconstant +ast-op-const 12)

;;; --- Backend state ---
(defvar *backend* :auto)
(defvar *backend-name* "unknown")
(defvar *engine-loaded* nil)

;;; --- Foreign library ---
(define-foreign-library sonata-engine
  (:windows "sonata_cuda.dll")
  (t (:default "libsonata_cuda")))

;;; --- GPU (CUDA) foreign functions ---
(defcfun ("sonata_cuda_init" %cuda-init) :void)
(defcfun ("sonata_cuda_shutdown" %cuda-shutdown) :void)
(defcfun ("sonata_cuda_eval_ast_sse" %cuda-eval-ast-sse) :void
  (data :pointer) (n-rows :int) (n-vars :int)
  (opcodes :pointer) (args :pointer) (ast-len :int)
  (out-error :pointer) (stream :pointer))
(defcfun ("sonata_cuda_eval_ast_sse_batch" %cuda-eval-ast-sse-batch) :void
  (data :pointer) (n-datasets :int) (n-rows-per-ds :int) (n-vars :int)
  (opcodes :pointer) (args :pointer) (ast-len :int)
  (out-errors :pointer) (stream :pointer))

;;; --- CPU (SIMD) foreign functions ---
(defcfun ("sonata_cpu_eval_ast_sse" %cpu-eval-ast-sse) :int
  (data :pointer) (n-rows :int) (n-vars :int)
  (opcodes :pointer) (args :pointer) (ast-len :int)
  (out-error :pointer))
(defcfun ("sonata_cpu_eval_ast_sse_batch" %cpu-eval-ast-sse-batch) :int
  (data :pointer) (n-datasets :int) (n-rows-per-ds :int) (n-vars :int)
  (opcodes :pointer) (args :pointer) (ast-len :int)
  (out-errors :pointer))
(defcfun ("sonata_cpu_simd_level" %cpu-simd-level) :int)
(defcfun ("sonata_cpu_force_simd_level" %cpu-force-simd-level) :int (level :int))

;;; --- Load / init ---
(defun load-engine (&key (dll-path #P"cuda/sonata_cuda.dll") (backend :auto))
  "Load the engine DLL and probe available backends.
BACKEND: :auto (try CUDA → CPU), :cuda, :cpu."
  (setf *backend* backend)
  (unless *engine-loaded*
    (let* ((src-dir (make-pathname :directory (pathname-directory
                     (truename (merge-pathnames dll-path *default-pathname-defaults*)))))
           (alt-dir (truename #P"C:/Users/etotm/AppData/Local/Temp/")))
      ;; Load DLL (try source dir first, fall back to alt non-ASCII-safe dir)
      (flet ((try-load (dir)
               (pushnew dir cffi:*foreign-library-directories*)
               (handler-case (load-foreign-library 'sonata-engine)
                 (error () (setf cffi:*foreign-library-directories*
                                 (rest cffi:*foreign-library-directories*))
                        nil))))
        (or (try-load src-dir)
            (try-load alt-dir)
            (error "Unable to load sonata_cuda.dll from ~a or ~a" src-dir alt-dir)))
      (setf *engine-loaded* t)))
  (case backend
    (:cuda
     (handler-case
         (progn (%cuda-init)
                (setf *backend-name* "CUDA")
                :cuda)
       (error (e)
         (warn "CUDA init failed: ~a. Use :cpu backend." e)
         (setf *backend-name* "CUDA-unavailable")
          :cpu)))
    (:cpu
     (setf *backend-name* "CPU")
     :cpu)
    (:auto
     (handler-case
         (progn (%cuda-init)
                (setf *backend-name* "CUDA")
                :cuda)
       (error ()
         (setf *backend-name* "CPU (SIMD)")
         :cpu)))))

(defun shutdown-engine ()
  "Shutdown GPU backend if active."
  (when (string= *backend-name* "CUDA")
    (ignore-errors (%cuda-shutdown)))
  (setf *backend-name* "unknown"))

;;; --- High-level eval ---
(defun eval-ast-sse (opcodes args data-array n-rows n-vars)
  "Evaluate flattened AST. Returns SSE as single float.
Auto-selects GPU or CPU based on *backend*."
  (check-type opcodes (vector (signed-byte 32)))
  (check-type args (vector single-float))
  (check-type data-array (vector single-float))
  (let ((ast-len (length opcodes))
        (n-floats (* n-rows n-vars)))
    (assert (>= (length data-array) n-floats) ()
            "data-array too small: need ~d floats, have ~d" n-floats (length data-array))
    (cffi:with-foreign-objects ((ast-opcodes :int ast-len)
                                (ast-args :float ast-len)
                                (data-ptr :float n-floats)
                                (result :float))
      ;; Copy Lisp arrays to foreign memory
      (loop for i below ast-len do
        (setf (cffi:mem-aref ast-opcodes :int i) (aref opcodes i))
        (setf (cffi:mem-aref ast-args :float i) (aref args i)))
      (loop for i below n-floats do
        (setf (cffi:mem-aref data-ptr :float i) (aref data-array i)))
      (setf (cffi:mem-ref result :float) 0.0f0)
      ;; Dispatch to backend
      (let ((use-cuda (or (eq *backend* :cuda)
                          (and (eq *backend* :auto)
                               (string= *backend-name* "CUDA")))))
        (if use-cuda
            (%cuda-eval-ast-sse data-ptr n-rows n-vars
                                ast-opcodes ast-args ast-len
                                result (cffi:null-pointer))
            (let ((ret (%cpu-eval-ast-sse data-ptr n-rows n-vars
                                          ast-opcodes ast-args ast-len
                                          result)))
              (assert (= ret 0) () "CPU eval returned error: ~d" ret))))
      (cffi:mem-ref result :float))))

(defun eval-ast-sse-batch (opcodes args data-array
                           n-datasets n-rows-per-ds n-vars)
  "Evaluate same AST against multiple independent datasets.
Returns a list of SSE values, one per dataset."
  (check-type opcodes (vector (signed-byte 32)))
  (check-type args (vector single-float))
  (check-type data-array (vector single-float))
  (let ((ast-len (length opcodes))
        (n-floats (* n-datasets n-rows-per-ds n-vars)))
    (assert (>= (length data-array) n-floats) ()
            "data-array too small: need ~d floats, have ~d" n-floats (length data-array))
    (cffi:with-foreign-objects ((ast-opcodes :int ast-len)
                                (ast-args :float ast-len)
                                (data-ptr :float n-floats)
                                (results :float n-datasets))
      (loop for i below ast-len do
        (setf (cffi:mem-aref ast-opcodes :int i) (aref opcodes i))
        (setf (cffi:mem-aref ast-args :float i) (aref args i)))
      (loop for i below n-floats do
        (setf (cffi:mem-aref data-ptr :float i) (aref data-array i)))
      (loop for i below n-datasets do
        (setf (cffi:mem-aref results :float i) 0.0f0))
      (let ((use-cuda (or (eq *backend* :cuda)
                          (and (eq *backend* :auto)
                               (string= *backend-name* "CUDA")))))
        (if use-cuda
            (%cuda-eval-ast-sse-batch data-ptr n-datasets n-rows-per-ds n-vars
                                      ast-opcodes ast-args ast-len
                                      results (cffi:null-pointer))
            (let ((ret (%cpu-eval-ast-sse-batch data-ptr n-datasets n-rows-per-ds n-vars
                                                ast-opcodes ast-args ast-len
                                                results)))
              (assert (= ret 0) () "CPU batch eval returned error: ~d" ret))))
      (loop for i below n-datasets collect
            (cffi:mem-aref results :float i)))))

;;; --- SIMD level query / control ---
(defun cpu-simd-level ()
  "Returns current SIMD level: 0=scalar, 1=SSE2, 2=AVX2."
  (%cpu-simd-level))

(defun cpu-force-simd-level (level)
  "Force SIMD level: 0=scalar, 1=SSE2, 2=AVX2."
  (let ((ret (%cpu-force-simd-level level)))
    (assert (= ret 0) () "Invalid SIMD level: ~d" level)
    level))

;;; --- S-expression to postfix flattener ---
(defun flatten-ast (expr)
  "Convert s-expr like (+ (* v0 2.0) v1) into postfix opcodes and args vectors.
Returns (values opcodes-vector args-vector)."
  (let ((opcodes '())
        (args '()))
    (labels ((walk (node)
               (cond
                 ((numberp node)
                  (push +ast-op-const opcodes)
                  (push (coerce node 'single-float) args))
                 ((symbolp node)
                  (let ((name (string node)))
                    (if (char-equal (char name 0) #\v)
                        (let ((idx (parse-integer (subseq name 1))))
                          (push +ast-op-var opcodes)
                          (push (coerce idx 'single-float) args))
                        (error "Unknown variable: ~a" node))))
                 ((consp node)
                  (let ((op (first node))
                        (operands (rest node)))
                    (dolist (o operands) (walk o))
                    (push (ecase op
                             (+ +ast-op-add) (- +ast-op-sub)
                             (* +ast-op-mul) (/ +ast-op-div)
                             (sin +ast-op-sin) (cos +ast-op-cos)
                             (exp +ast-op-exp) (log +ast-op-log)
                             (sqrt +ast-op-sqrt) (neg +ast-op-neg))
                           opcodes)
                    (push 0.0 args)))
                 (t (error "Invalid AST node: ~a" node)))))
      (walk expr)
      (values
        (make-array (length opcodes) :element-type '(signed-byte 32)
                    :initial-contents (nreverse opcodes))
        (make-array (length args) :element-type 'single-float
                    :initial-contents (nreverse args))))))

;;; --- Self-tests ---
(defun demo (&key (backend :auto))
  "Test GPU backend. AST: (+ (* v0 2.0) v1)"
  (format t "Loading engine (backend=~a)~%" backend)
  (load-engine :backend backend)
  (format t "Active backend: ~a~%" *backend-name*)
  (multiple-value-bind (opcodes args) (flatten-ast '(+ (* v0 2.0) v1))
    (format t "Opcodes: ~a~%" opcodes)
    (format t "Args:    ~a~%" args)
    (let* ((n-rows 4)
           (n-vars 3)
           (data (make-array (* n-rows n-vars)
                             :element-type 'single-float
                             :initial-contents
                             (list 1.0 2.0 4.0
                                   3.0 4.0 10.0
                                   5.0 6.0 16.0
                                   0.0 1.0 1.0))))
      (let ((sse (eval-ast-sse opcodes args data n-rows n-vars)))
        (format t "SSE: ~a~%" sse)
        (if (< (abs sse) 1e-5)
            (format t "PASS: SSE near zero~%")
            (format t "FAIL: expected SSE ~a, got ~a~%" 0.0 sse)))))
  (shutdown-engine))

(defun demo-cpu ()
  "Test CPU SIMD backend with the same AST."
  (demo :backend :cpu))
