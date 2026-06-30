;; LSMA — Phase 2: Matrix Memory Algebra
;; ================================================
;; File: v9/src/lsma/matrix.lisp
;;
;; Pure Lisp matrix operations on SBCL native arrays.
;; No BLAS/LAPACK, no APL dependency in MVP.
;;
;; Matrices:
;;   ADF × FEATURES         — N×M double-float   — ADF feature vectors
;;   ADF × DOMAIN           — N×D float           — domain affinity per ADF
;;   OPERATOR × OPERATOR    — O×O integer         — co-occurrence counts
;;   ADF × BEHAVIOR_TRACE   — N×P double-float    — lazy, on-demand
;;   DOMAIN × OPERATOR      — D×O float           — domain-operator affinity
;;
;; TODO:
;;   [ ] init-op-cooc-matrix          — O×O zero matrix
;;   [ ] update-op-cooc               — increment co-occurrence for operator pair
;;   [ ] get-op-cooc                  — lookup co-occurrence count
;;   [ ] op-cooc-to-operator-affinity — normalize co-occurrence → affinity score
;;   [ ] init-adf-feature-matrix      — N×M from passport data
;;   [ ] extend-adf-feature-matrix    — add row for new ADF
;;   [ ] update-adf-domain-matrix     — update domain affinity row for ADF
;;   [ ] top-k-for-domain             — top-K ADFs for a given domain
;;   [ ] cross-domain-candidates      — ADFs successful in other domains
;;   [ ] eviction-candidates          — low-utility ADFs for removal
