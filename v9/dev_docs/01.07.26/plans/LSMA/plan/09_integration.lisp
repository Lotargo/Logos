;; LSMA — Integration: Modify Existing Engine
;; ================================================
;;
;; Changes to existing files to wire in LSMA.
;;
;; TODO:
;;   [ ] v9/src/lsma/package.lisp     — defpackage for all LSMA modules
;;   [ ] engine.lisp: load LSMA modules
;;   [ ] engine.lisp: replace (next-adf-symbol ...) with (select-adf ...) in run-engine-parallel
;;   [ ] engine.lisp: record ADF outcomes after each worker iteration
;;   [ ] engine.lisp: call periodic-eviction from worker-loop
;;   [ ] knowledge_loader.lisp: replace ast-hash with canonical-ast-hash
;;   [ ] knowledge_loader.lisp: save/restore passports instead of raw ADFs
;;   [ ] knowledge_loader.lisp: load passports on engine init
;;   [ ] telemetry migrations: add 003_lsma_knowledge.sql
