;; LSMA — Phase 1: Canonical AST Hash + Passport
;; ================================================
;; File: v9/src/lsma/passport.lisp
;;
;; Depends on: ironclad (SHA256), cl-ppcre (variable canonicalization)
;; 
;; Provides:
;;   canonical-ast-hash    — deterministic SHA256 (structure, not variable names)
;;   extract-passport      — full passport plist from an AST
;;   extract-operator-profile — operator frequency map
;;   extract-subtree-hashes   — top-N subtrees by depth
;;   extract-depth-profile    — depth at each node position
;;   ast-structural-equal-p   — compare by canonical hash

;; TODO:
;;   [ ] canonical-ast-hash           — normalize variable names, then SHA256
;;   [ ] variable-canonicalize        — replace var names with positional indices
;;   [ ] constant-normalize           — round floats, unify numeric representation
;;   [ ] extract-operator-profile     — count operator frequencies in AST
;;   [ ] extract-subtree-hashes       — collect hashes of all subtrees, cap at top-N
;;   [ ] extract-depth-profile        — compute depth at each node position
;;   [ ] extract-passport             — assemble all above into a passport plist
;;   [ ] ast-structural-equal-p       — compare two ASTs by canonical hash
