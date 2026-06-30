;;; LSMA — Phase 1: JSONL/Neon Storage
;;; File: v9/src/lsma/storage.lisp
;;;
;;; Two-layer storage for AST passports:
;;;   1. Local JSONL cache (fast, always available)
;;;   2. Neon PostgreSQL (logos_knowledge table, via Python bridge)
;;;
;;; Dependencies: lsma/passport.lisp, telemetry_helper.lisp

(in-package :cognitive-engine)

;; ————————————————————————————————————————————————————————————————————
;; Configuration
;; ————————————————————————————————————————————————————————————————————

(defvar *jsonl-cache-path*
  (or (ignore-errors
        (uiop:getenv "LOGOS_JSONL_CACHE"))
      "v9/telemetry/cache/logos_knowledge.jsonl")
  "Path to the JSONL cache file for passport storage.")

;; ————————————————————————————————————————————————————————————————————
;; JSONL cache helpers
;; ————————————————————————————————————————————————————————————————————

(defun %ensure-cache-dir ()
  "Create cache directory if it doesn't exist."
  (let ((dir (make-pathname :name nil :type nil :defaults *jsonl-cache-path*)))
    (ensure-directories-exist dir)))

(defun %passport->jsonl-line (passport)
  "Serialize a passport plist to a JSONL line (Lisp s-expression plist).
   Each line is a plist readable by READ-FROM-STRING."
  (let* ((hash (getf passport :ast-hash))
         (ast-str (getf passport :ast-str ""))
         (op-profile (getf passport :operator-profile))
         (domains (getf passport :domains))
         (usage-count (getf passport :usage-count 0))
         (success-count (getf passport :success-count 0))
         (failure-count (getf passport :failure-count 0))
         (freshness (getf passport :freshness "")))
    (let ((*print-pretty* nil))
      (format nil "~S~%"
              (list :ast_hash hash :ast ast-str
                    :passport (list :operator_profile op-profile
                                    :domains domains
                                    :usage_count usage-count
                                    :success_count success-count
                                    :failure_count failure-count
                                    :freshness freshness))))))

(defun jsonl-cache-write (passport)
  "Write a passport to the JSONL cache (append)."
  (%ensure-cache-dir)
  (with-open-file (f *jsonl-cache-path*
                     :direction :output
                     :if-exists :append
                     :if-does-not-exist :create)
    (write-string (%passport->jsonl-line passport) f)))

(defun jsonl-cache-read (&key (hash nil) (domain nil))
  "Read passports from JSONL cache. Filter by hash or domain if provided."
  (unless (probe-file *jsonl-cache-path*)
    (return-from jsonl-cache-read nil))
  (let (results)
    (with-open-file (f *jsonl-cache-path*
                       :direction :input
                       :if-does-not-exist nil)
      (when f
        (loop for line = (read-line f nil nil)
              while line
              do (handler-case
                     (let* ((json (read-from-string line))
                            (entry-hash (getf json :ast_hash))
                            (entry-domain (getf json :passport :domains)))
                       (when (and (or (null hash) (string= entry-hash hash))
                                  (or (null domain)
                                      (and (listp entry-domain)
                                           (member domain entry-domain
                                                   :test (lambda (d e)
                                                           (string-equal (string d) (string e)))))))
                         (push json results)))
                   (error () nil)))))
    (nreverse results)))

(defun jsonl-cache-exists-p (hash)
  "Check if a passport with the given hash exists in the cache."
  (not (null (jsonl-cache-read :hash hash))))

;; ————————————————————————————————————————————————————————————————————
;; Neon persistence (via Python bridge)
;; ————————————————————————————————————————————————————————————————————

(defun %python-executable ()
  "Return the configured Python executable."
  (or (uiop:getenv "LOGOS_PYTHON")
      #+win32 "C:/Users/etotm/AppData/Local/Programs/Python/Python312/python.exe"
      "python3"))

(defun save-passport-to-neon (passport)
  "Save a passport to Neon via the Python telemetry bridge.
   Returns T on success, NIL on failure."
  (let* ((hash (getf passport :ast-hash))
         (ast-str (getf passport :ast-str ""))
         (passport-json (plist-to-json passport))
         (cmd (list (%python-executable)
                    "v9/telemetry/telemetry_logger.py"
                    "save-knowledge"
                    "--ast-hash" hash
                    "--ast" ast-str
                    "--passport" passport-json)))
    (handler-case
        (progn
          (uiop:run-program cmd :output :string :ignore-error-status t)
          t)
      (error () nil))))

(defun load-passports-from-neon (&key (min-fitness 0.9))
  "Load passports from Neon via Python bridge.
   Returns a list of (ast-hash . ast-sexp) pairs."
  (let ((cmd (list (%python-executable)
                   "v9/telemetry/telemetry_logger.py"
                   "fetch-knowledge-lisp"
                   "--min-fitness" (format nil "~,2F" min-fitness))))
    (handler-case
        (let ((output (uiop:run-program cmd :output :string :ignore-error-status t)))
          (when output
            (handler-case
                (read-from-string output)
              (error () nil))))
      (error () nil))))

;; ————————————————————————————————————————————————————————————————————
;; High-level API
;; ————————————————————————————————————————————————————————————————————

(defun save-passport (passport &key (to-neon nil))
  "Save a passport to JSONL cache (always) and optionally to Neon."
  (jsonl-cache-write passport)
  (when to-neon
    (save-passport-to-neon passport)))

(defun load-passport-by-hash (hash)
  "Load a single passport by hash. Checks JSONL cache first."
  (let ((cached (jsonl-cache-read :hash hash)))
    (car cached)))

(defun load-passports-by-domain (domain)
  "Load all passports for a given domain from JSONL cache."
  (jsonl-cache-read :domain domain))

(defun load-all-passports ()
  "Load all passports from JSONL cache."
  (jsonl-cache-read))
