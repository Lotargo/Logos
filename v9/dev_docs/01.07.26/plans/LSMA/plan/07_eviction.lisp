;; LSMA — Phase 3: Forgetting / Eviction
;; ================================================
;; File: v9/src/lsma/eviction.lisp
;;
;; Prevents ADF library bloat by evicting low-utility ADFs.
;; Triggered periodically or on threshold exceed.
;;
;; Criteria:
;;   - freshness (last usage timestamp)
;;   - failure rate threshold
;;   - low structural diversity (redundant with other ADFs)
;;
;; TODO:
;;   [ ] compute-utility-score        — combined freshness + success rate
;;   [ ] find-eviction-candidates     — bottom-N by utility
;;   [ ] evict-adf                    — remove from all structures and DB
;;   [ ] check-library-size           — trigger warning at threshold
;;   [ ] periodic-eviction            — called every N iterations
