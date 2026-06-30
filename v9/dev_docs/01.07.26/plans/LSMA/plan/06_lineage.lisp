;; LSMA — Phase 3: Lineage Tracking
;; ================================================
;; File: v9/src/lsma/lineage.lisp
;;
;; Bounded ancestry chain for each ADF.
;; Maximum 5 generations; older ancestors summarized as count.
;;
;; TODO:
;;   [ ] record-birth                 — register parent→child relationship
;;   [ ] get-lineage                  — return bounded ancestry chain
;;   [ ] compress-lineage             — summarize beyond depth 5
;;   [ ] lineage-depth                — count generations from root
;;   [ ] most-successful-lineage      — find best-performing branch
