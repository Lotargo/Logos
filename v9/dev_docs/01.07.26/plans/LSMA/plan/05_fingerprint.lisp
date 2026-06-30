;; LSMA — Phase 3: Behavioral Fingerprints
;; ================================================
;; File: v9/src/lsma/fingerprint.lisp
;;
;; Lazy, cached behavior traces for ADF candidates.
;; Computed only when ADF becomes a selection candidate.
;;
;; Strategy:
;;   1. Probe set — small fixed set of input vectors (5-10 per domain)
;;   2. Lazy computation — only when ADF is shortlisted for selection
;;   3. Cache — *behavior-cache* hash table, invalidated on mutation
;;   4. Comparison — cosine similarity between output vectors
;;
;; TODO:
;;   [ ] define-probe-set             — configurable probe input vectors per domain
;;   [ ] compute-behavior-trace       — eval ADF on all probes → output vector
;;   [ ] cache-behavior-trace         — store in *behavior-cache*
;;   [ ] get-behavior-trace           — read from cache or compute + cache
;;   [ ] invalidate-behavior-cache    — clear entry when ADF mutates
;;   [ ] cosine-similarity            — compare two behavior vectors
;;   [ ] similar-by-behavior          — top-K ADFs with closest behavior
