;;; LSMA — Phase 3: Forgetting / Eviction
;;; File: v9/src/lsma/eviction.lisp
;;;
;;; Prevents ADF library bloat by evicting low-utility ADFs.
;;; Triggered periodically or when library exceeds threshold.
;;;
;;; Package defined in package.lisp — this file assumes (in-package :lsma).

(in-package :lsma)

;; ————————————————————————————————————————————————————————————————————
;; Configuration
;; ————————————————————————————————————————————————————————————————————

(defparameter *eviction-max-library-size* 500
  "Soft cap on *adf-library* size. Beyond this, eviction is triggered.")

(defparameter *eviction-target-count* 20
  "Number of ADFs to evict per periodic-eviction call.")

;; ————————————————————————————————————————————————————————————————————
;; Utility scoring
;; ————————————————————————————————————————————————————————————————————

(defun compute-utility-score (passport)
  "Combined utility score for eviction decisions, in [0, 1].
   Higher = keep. Lower = evict.
   Factors: freshness (last usage), success rate, structural diversity."
  (let* ((usage (getf passport :usage-count 0))
         (success (getf passport :success-count 0))
         (failure (getf passport :failure-count 0))
         (total (+ success failure))
         (success-rate (if (> total 0)
                           (/ (coerce success 'float) total)
                           0.3))
         ;; Usage recency: more usage = more utility
         (usage-factor (/ 1.0 (max 1.0 (log (+ usage 1) 2))))
         ;; Freshness decay
         (freshness-str (getf passport :freshness ""))
         (freshness-factor (if (string= freshness-str "")
                               0.1  ; no timestamp = low utility
                               0.5))
         ;; Combined score
         (score (+ (* 0.4 success-rate)
                   (* 0.3 usage-factor)
                   (* 0.3 freshness-factor))))
    (max 0.0 (min 1.0 score))))

;; ————————————————————————————————————————————————————————————————————
;; Eviction candidates
;; ————————————————————————————————————————————————————————————————————

(defun find-eviction-candidates (adf-library &key (n *eviction-target-count*))
  "Find the bottom-N ADFs by utility score from the in-memory library.
   Returns a list of (adf-symbol . ast) pairs to evict."
  (unless adf-library
    (return-from find-eviction-candidates nil))
  (let (scored)
    (dolist (entry adf-library)
      (let* ((ast (cdr entry))
             (passport (list :ast-str (format nil "~A" ast)
                             :usage-count 0
                             :success-count 0
                             :failure-count 0
                             :freshness ""))
             ;; Try to find actual passport in JSONL cache
             (hash (handler-case
                       (canonical-ast-hash ast)
                     (error () nil)))
             (stored (when hash (load-passport-by-hash hash))))
        (when stored
          (setf passport stored))
        (push (cons (compute-utility-score passport) entry) scored)))
    (setf scored (sort scored #'< :key #'car))
    ;; Return bottom-N
    (loop for i from 1 to (min n (length scored))
          collect (cdr (nth (1- i) scored)))))

;; ————————————————————————————————————————————————————————————————————
;; Eviction
;; ————————————————————————————————————————————————————————————————————

(defun evict-adf (adf-symbol)
  "Remove an ADF from all structures: JSONL cache, *adf-library*.
   Returns T if evicted, NIL if not found."
  (let* ((sym-name (symbol-name adf-symbol))
         (lib (ignore-errors
               (symbol-value (find-symbol (string '*adf-library*)
                                          (find-package :cognitive-engine)))))
         (removed nil))
    ;; Remove from JSONL cache by finding matching passports
    (let ((passports (jsonl-cache-read)))
      (dolist (p passports)
        (let ((ast-str (getf p :ast-str "")))
          (when (search sym-name ast-str :test #'char-equal)
            (jsonl-cache-delete (getf p :ast-hash))
            (setf removed t)))))
    ;; Remove from *adf-library*
    (when lib
      (let ((new-lib (remove adf-symbol lib :key #'car :test #'eq)))
        (setf (symbol-value (find-symbol (string '*adf-library*)
                                         (find-package :cognitive-engine)))
              new-lib)
        (when (< (length new-lib) (length lib))
          (setf removed t))))
    removed))

;; ————————————————————————————————————————————————————————————————————
;; Library size management
;; ————————————————————————————————————————————————————————————————————

(defun check-library-size (&key (adf-library nil))
  "Check if the ADF library exceeds the soft cap.
   Returns (values exceeded-p current-size max-size)."
  (let* ((lib (or adf-library
                  (ignore-errors
                   (symbol-value (find-symbol (string '*adf-library*)
                                              (find-package :cognitive-engine))))))
         (size (length lib))
         (max *eviction-max-library-size*))
    (values (> size max) size max)))

;; ————————————————————————————————————————————————————————————————————
;; Periodic eviction
;; ————————————————————————————————————————————————————————————————————

(defun periodic-eviction (adf-library &key (domain nil) (dry-run nil))
  "Periodic eviction: check library size, evict bottom-N low-utility ADFs.
   Called every N iterations from the worker loop."
  (declare (ignore domain))
  (multiple-value-bind (exceeded-p size max)
      (check-library-size :adf-library adf-library)
    (when (or exceeded-p (> size (* max 0.8)))  ; evict also when approaching cap
      (let* ((candidates (find-eviction-candidates adf-library))
             (evicted 0))
        (dolist (entry candidates)
          (unless dry-run
            (when (evict-adf (car entry))
              (incf evicted))))
        (when (> evicted 0)
          (format t "[LSMA EVICTION] Evicted ~D low-utility ADFs (library: ~D/~D)~%"
                  evicted (- size evicted) max))
        evicted))))
