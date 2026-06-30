;;; LSMA — Consolidated Package Definition
;;; All LSMA modules share the :lsma package.
;;; File: v9/src/lsma/package.lisp

(defpackage :lsma
  (:use :cl)
  (:export
   ;; Passport core (passport.lisp)
   :canonical-ast-hash
   :canonical-ast
   :canonicalize-variables
   :canonicalize-constants
   :extract-passport
   :extract-operator-profile
   :extract-subtree-hashes
   :extract-depth-profile
   :ast-structural-equal-p
   :passport-get
   :*canonical-variables*
   :*subtree-hash-limit*
   ;; Storage API (storage.lisp)
   :save-passport
   :load-passport-by-hash
   :load-passports-by-domain
   :load-all-passports
   :count-passports
   :passport->adf
   :batch-passports->adfs
   :register-passport-as-adf
   :*adf-prefix*
   :*adf-counter*
   :next-adf-symbol
   ;; JSONL cache
   :jsonl-cache-write
   :jsonl-cache-read
   :jsonl-cache-delete
   ;; Serialization helpers
   :plist-to-json
   ;; Selection API (selection.lisp)
   :*selection-weights*
   :compute-adf-score
   :select-adf
   :record-adf-usage
   :record-adf-outcome
   ;; Eviction API (eviction.lisp)
   :compute-utility-score
   :find-eviction-candidates
   :evict-adf
   :check-library-size
   :periodic-eviction))
