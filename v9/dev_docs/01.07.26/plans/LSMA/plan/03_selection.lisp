;; LSMA — Phase 2: ADF Selection
;; ================================================
;; File: v9/src/lsma/selection.lisp
;;
;; Replaces random ADF selection with weighted ADF_SCORE formula.
;; Tracks usage/success/failure per ADF.
;;
;; ADF_SCORE formula:
;;   w_sim  * structural_similarity
;; + w_beam * behavior_similarity
;; + w_dom  * domain_affinity
;; + w_op   * operator_affinity
;; + w_hist * historical_success
;; + w_frsh * freshness
;; + w_nov  * novelty_bonus
;; - w_bloat* bloat_penalty
;; - w_fail * failure_penalty
;;
;; TODO:
;;   [ ] define-adf-score-weights     — configurable weight constants
;;   [ ] structural-similarity        — compare AST subtrees overlap
;;   [ ] behavior-similarity          — cosine sim of behavior fingerprints
;;   [ ] domain-affinity              — how relevant ADF is to current domain
;;   [ ] operator-affinity            — operator co-occurrence score
;;   [ ] historical-success           — success/(success+failure) ratio
;;   [ ] freshness                    — time since last usage
;;   [ ] novelty-bonus                — penalty for overused ADFs
;;   [ ] bloat-penalty                — penalty for depth/size
;;   [ ] failure-penalty              — recent failure penalty
;;   [ ] compute-adf-score            — assemble all factors into final score
;;   [ ] select-adf                   — weighted random selection from candidates
;;   [ ] record-adf-usage             — increment usage counter
;;   [ ] record-adf-outcome           — record success/failure outcome
