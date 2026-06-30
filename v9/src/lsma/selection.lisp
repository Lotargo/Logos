;;; LSMA — Phase 2: ADF Selection
;;; File: v9/src/lsma/selection.lisp
;;;
;;; Weighted ADF scoring and selection for use during evolution.
;;; Replaces random ADF selection with multi-factor ADF_SCORE.
;;;
;;; Package defined in package.lisp — this file assumes (in-package :lsma).

(in-package :lsma)

;; ————————————————————————————————————————————————————————————————————
;; Configuration: default score weights
;; ————————————————————————————————————————————————————————————————————

(defparameter *selection-weights*
  '(:structural-similarity  0.25
    :domain-affinity        0.20
    :operator-affinity      0.15
    :historical-success     0.15
    :freshness              0.10
    :novelty-bonus          0.05
    :bloat-penalty          0.05
    :failure-penalty        0.05)
  "Weights for each factor in the ADF score formula.
   Values must sum to 1.0. Used by COMPUTE-ADF-SCORE.")

;; ————————————————————————————————————————————————————————————————————
;; Similarity / affinity helpers
;; ————————————————————————————————————————————————————————————————————

(defun structural-similarity (ast candidates)
  "Compute average subtree-hash overlap between AST and candidate ADF bodies.
   Returns a value in [0, 1]."
  (unless (and ast candidates (listp candidates))
    (return-from structural-similarity 0.0))
  (let ((ast-hashes (extract-subtree-hashes ast :limit 20))
        (total-overlap 0.0)
        (count 0))
    (dolist (c candidates)
      (let ((c-hashes (extract-subtree-hashes c :limit 20))
            (overlap 0.0))
        (dolist (h ast-hashes)
          (when (member h c-hashes :test #'string=)
            (setf overlap (+ overlap 1.0))))
        (setf total-overlap (+ total-overlap
                               (/ overlap (max (length ast-hashes) 1))))
        (incf count)))
    (if (> count 0)
        (/ total-overlap count)
        0.0)))

(defun domain-affinity (passport domain)
  "Score how relevant an ADF passport is to the given domain, in [0, 1]."
  (let ((domains (getf passport :domains)))
    (cond
      ((null domain) 0.5)
      ((member domain domains :test #'eq) 1.0)
      ((member :unified domains :test #'eq) 0.8)
      (t 0.1))))

(defun operator-affinity (passport op-seq)
  "Score how well an ADF's operator profile matches the current operator sequence.
   Uses Jaccard similarity on operator sets."
  (let* ((op-profile (getf passport :operator-profile))
         (adf-ops (mapcar #'car op-profile))
         (adf-set (coerce adf-ops 'list))
         (op-set (coerce op-seq 'list))
         (intersection (length (intersection adf-set op-set :test #'eq)))
         (union (length (union adf-set op-set :test #'eq))))
    (if (> union 0)
        (/ (coerce intersection 'float) union)
        0.0)))

(defun historical-success (passport)
  "Compute success rate from passport counters, in [0, 1]."
  (let* ((success (getf passport :success-count 0))
         (failure (getf passport :failure-count 0))
         (total (+ success failure)))
    (if (> total 0)
        (/ (coerce success 'float) total)
        0.5)))  ; neutral for new ADFs

(defun freshness (passport)
  "Score how recently an ADF was used, in [0, 1].
   1.0 = just used, decays to 0.0 over time."
  (let ((freshness-str (getf passport :freshness "")))
    (if (string= freshness-str "")
        0.0
        0.8)))  ; simplified: treat any freshness timestamp as reasonably fresh

(defun novelty-bonus (passport)
  "Penalty for overused ADFs. Returns high bonus for low-usage ADFs."
  (let ((usage (getf passport :usage-count 0)))
    (/ 1.0 (max 1.0 (log (+ usage 1) 10)))))

(defun bloat-penalty (passport)
  "Penalty for ADF depth/size, in [0, 1]. Higher = more bloated."
  (let* ((ast-str (getf passport :ast-str ""))
         (depth (count #\( ast-str)))
    (min 1.0 (/ depth 50.0))))

(defun failure-penalty (passport)
  "Penalty based on recent failure rate, in [0, 1]."
  (let* ((success (getf passport :success-count 0))
         (failure (getf passport :failure-count 0))
         (total (+ success failure)))
    (if (> total 0)
        (min 1.0 (/ (coerce failure 'float) total))
        0.0)))

;; ————————————————————————————————————————————————————————————————————
;; Composite score
;; ————————————————————————————————————————————————————————————————————

(defun compute-adf-score (passport &key (domain nil) (op-seq nil) adf-library (candidates nil))
  "Assemble all factors into a final score in [0, 1].
   Higher = more likely to be selected / kept.
   When CANDIDATES is provided, computes structural similarity against them."
  (declare (ignore adf-library))
  (let* ((weights *selection-weights*)
          (score 0.0)
          (total-weight 0.0))
    (flet ((weight (key)
             (or (getf weights key) 0.0)))
      ;; Structural similarity vs candidates
      (let ((w (weight :structural-similarity)))
        (when (> w 0.0)
          (incf score (* w (structural-similarity
                            (handler-case
                                (read-from-string (getf passport :ast-str ""))
                              (error () nil))
                            candidates)))
          (incf total-weight w)))
      ;; Domain affinity
      (let ((w (weight :domain-affinity)))
        (when (> w 0.0)
          (incf score (* w (domain-affinity passport domain)))
          (incf total-weight w)))
      ;; Operator affinity
      (let ((w (weight :operator-affinity)))
        (when (and (> w 0.0) op-seq)
          (incf score (* w (operator-affinity passport op-seq)))
          (incf total-weight w)))
      ;; Historical success
      (let ((w (weight :historical-success)))
        (when (> w 0.0)
          (incf score (* w (historical-success passport)))
          (incf total-weight w)))
      ;; Freshness
      (let ((w (weight :freshness)))
        (when (> w 0.0)
          (incf score (* w (freshness passport)))
          (incf total-weight w)))
      ;; Novelty bonus (additive)
      (let ((w (weight :novelty-bonus)))
        (when (> w 0.0)
          (incf score (* w (novelty-bonus passport)))
          (incf total-weight w)))
      ;; Bloat penalty (subtractive)
      (let ((w (weight :bloat-penalty)))
        (when (> w 0.0)
          (decf score (* w (bloat-penalty passport)))
          (incf total-weight w)))
      ;; Failure penalty (subtractive)
      (let ((w (weight :failure-penalty)))
        (when (> w 0.0)
          (decf score (* w (failure-penalty passport)))
          (incf total-weight w))))
    (if (> total-weight 0.0)
        (max 0.0 (min 1.0 (/ score total-weight)))
        0.0)))

;; ————————————————————————————————————————————————————————————————————
;; Selection
;; ————————————————————————————————————————————————————————————————————

(defun select-adf (candidates context)
  "Weighted random selection from a list of (adf-symbol . ast) candidates.
   CONTEXT is a plist with keys :domain, :op-seq, :adf-library.
   Returns a single (adf-symbol . ast) pair, or NIL if candidates is empty."
  (unless candidates
    (return-from select-adf nil))
  (let* ((domain (getf context :domain))
         (op-seq (getf context :op-seq))
         (adf-lib (getf context :adf-library))
         scored)
    ;; Score each candidate
    (dolist (c candidates)
      (let* ((ast (cdr c))
             (passport (list :ast-str (format nil "~A" ast)
                             :domains (if domain (list domain) nil)
                             :operator-profile (extract-operator-profile ast)
                             :usage-count 0
                             :success-count 0
                             :failure-count 0
                             :freshness "")))
        (push (cons (compute-adf-score passport
                                        :domain domain
                                        :op-seq op-seq
                                        :adf-library adf-lib
                                        :candidates (mapcar #'cdr candidates))
                    c)
              scored)))
    (setf scored (sort scored #'> :key #'car))
    ;; Weighted random: prefer higher scores but allow exploration
    (let ((total (loop for (s . c) in scored sum (max 0.01 s)))
          (pick (random 1.0)))
      (loop for (score . candidate) in scored
            do (decf pick (/ (max 0.01 score) total))
            when (<= pick 0.0) return candidate))))

;; ————————————————————————————————————————————————————————————————————
;; Usage / outcome tracking
;; ————————————————————————————————————————————————————————————————————

(defun record-adf-usage (adf-symbol)
  "Increment the usage counter for an ADF's passport in the JSONL cache."
  (let* ((sym-name (symbol-name adf-symbol))
         (passports (jsonl-cache-read))
         (updated nil))
    (dolist (p passports)
      (let ((ast-str (getf p :ast-str "")))
        (when (and (search sym-name ast-str :test #'char-equal)
                   (or (null updated) (string> (getf p :freshness "")
                                                (getf updated :freshness ""))))
          (setf updated p))))
    (when updated
      (let* ((new-usage (1+ (getf updated :usage-count 0)))
             (new-freshness (multiple-value-bind (s m h d mo y)
                                (get-decoded-time)
                              (format nil "~4,'0D-~2,'0D-~2,'0DT~2,'0D:~2,'0D:~2,'0DZ"
                                      y mo d h m s)))
             (augmented (list* :usage-count new-usage
                               :freshness new-freshness
                               updated)))
        (jsonl-cache-delete (getf updated :ast-hash))
        (jsonl-cache-write augmented :dedup nil)))))

(defun record-adf-outcome (adf-symbol success &key (domain nil))
  "Record success or failure outcome for an ADF.
   Updates the passport's success/failure counter in the JSONL cache."
  (declare (ignore domain))
  (let* ((sym-name (symbol-name adf-symbol))
         (passports (jsonl-cache-read))
         (target nil))
    ;; Find the most recently updated passport matching this ADF symbol
    (dolist (p passports)
      (let ((ast-str (getf p :ast-str "")))
        (when (search sym-name ast-str :test #'char-equal)
          (if (or (null target)
                  (string> (getf p :freshness "")
                           (getf target :freshness "")))
              (setf target p)))))
    (when target
      (let* ((new-success (if success
                              (1+ (getf target :success-count 0))
                              (getf target :success-count 0)))
             (new-failure (if (not success)
                              (1+ (getf target :failure-count 0))
                              (getf target :failure-count 0)))
             (new-freshness (multiple-value-bind (s m h d mo y)
                                (get-decoded-time)
                              (format nil "~4,'0D-~2,'0D-~2,'0DT~2,'0D:~2,'0D:~2,'0DZ"
                                      y mo d h m s)))
             (augmented (list* :usage-count (1+ (getf target :usage-count 0))
                               :success-count new-success
                               :failure-count new-failure
                               :freshness new-freshness
                               target)))
        (jsonl-cache-delete (getf target :ast-hash))
        (jsonl-cache-write augmented :dedup nil)))))
