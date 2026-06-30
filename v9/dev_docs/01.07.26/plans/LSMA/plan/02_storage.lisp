;; LSMA — Phase 1: JSONL/Neon Storage
;; ================================================
;; File: v9/src/lsma/storage.lisp
;;
;; Persistent storage for AST passports.
;; Two-layer: PostgreSQL (Neon) + local JSONL cache.
;;
;; TODO:
;;   [ ] define-passport-schema       — logos_knowledge table DDL
;;   [ ] create-sql-migration          — migration SQL file in telemetry/migrations/
;;   [ ] save-passport                — insert/update passport in Neon
;;   [ ] load-passport-by-hash        — fetch single passport by ast_hash
;;   [ ] load-passports-by-domain     — fetch all passports for a domain
;;   [ ] load-all-passports           — full restore on engine start
;;   [ ] jsonl-cache-write             — write-through JSONL cache
;;   [ ] jsonl-cache-read             — read from JSONL on DB miss
;;   [ ] passport->adf                — reconstruct ADF entry from DB row
