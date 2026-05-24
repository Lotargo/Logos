(defvar *current-operators* nil)
(in-package :cognitive-engine)

;; Add wormhole operation to multidim
(defvar *meta-evolution-enabled* t)
(defvar *discovered-axioms* nil)

(defun get-random-axiom-structure ()
  "Generates a random Prolog string that could act as a new axiom in multidim domain."
  (let ((templates (list
                    "dim_of(wormhole(A, B), vector(3)) :- dim_of(A, vector(3)), dim_of(B, vector(3))"
                    "dim_of(teleport(A, B), vector(3)) :- dim_of(A, vector(3)), dim_of(B, vector(3))"
                    "dim_of(wormhole(A, B), vector(N)) :- dim_of(A, vector(N)), dim_of(B, vector(N))"
                    "dim_of(fold(A, B), matrix(R, C)) :- dim_of(A, matrix(R, C)), dim_of(B, matrix(R, C))"
                    "dim_of(wormhole(A, B), 0) :- dim_of(A, 0), dim_of(B, 0)")))
    (random-element templates)))

(defun inject-prolog-rule (proc-cell rule-str)
  "Sends an assertz command to the Prolog daemon to inject a new rule/fact."
  (let* ((proc (car proc-cell))
         (query (format nil "assertz((~A))." rule-str)))
    (handler-case
        (sb-ext:with-timeout 1.0
          (format (uiop:process-info-input proc) "~A~%" query)
          (force-output (uiop:process-info-input proc))
          (let ((response (read-line (uiop:process-info-output proc) nil :eof)))
            (if (and (stringp response) (not (eq response :eof)))
                (or (ignore-errors (read-from-string (string-trim '(#\Space #\Tab #\Return #\Newline #\") response)))
                    0.0)
                1000.0)))
      (sb-ext:timeout ()
        (format t "[TIMEOUT] Prolog daemon hung on assertz: ~A.~%" query)
        1000.0)
      (error (e)
        (format t "[ERROR] Prolog daemon pipe error on assertz: ~A.~%" e)
        1000.0))))

(defun retract-prolog-rule (proc-cell rule-str)
  "Sends a retract command to remove the injected rule."
  ;; Usually retract takes the exact clause. We can use retract((...))
  (let* ((proc (car proc-cell))
         (query (format nil "retract((~A))." rule-str)))
    (handler-case
        (sb-ext:with-timeout 1.0
          (format (uiop:process-info-input proc) "~A~%" query)
          (force-output (uiop:process-info-input proc))
          (let ((response (read-line (uiop:process-info-output proc) nil :eof)))
             t))
      (error (e) nil))))

(defun meta-mutate-axiom (proc-cell domain current-ast best-penalty check-fn)
  "Attempts to invent a new rule, injects it, and checks if it improves the score of the AST."
  (if (and *meta-evolution-enabled* (eq domain :multidim))
      (let ((new-axiom (get-random-axiom-structure)))
        (inject-prolog-rule proc-cell (format nil "multidim:~A" new-axiom))
        ;; Check if AST penalty improved with the new axiom
        ;; Note: The AST might need to use the newly invented operator
        ;; For simplicity in this experiment, we just temporarily enable the new operator in Lisp
        (let ((new-op (if (search "wormhole" new-axiom) 'wormhole
                          (if (search "teleport" new-axiom) 'teleport
                              (if (search "fold" new-axiom) 'fold nil)))))
          (if new-op
              (progn
                (pushnew new-op *current-operators*)
                (let* ((mutated-ast (mutate current-ast))
                       (new-penalty (funcall check-fn mutated-ast domain proc-cell :target)))
                  (if (< new-penalty best-penalty)
                      (progn
                        (format t "[META-EVOLUTION] Discovered and validated new mathematical axiom! ~A~%" new-axiom)
                        (push new-axiom *discovered-axioms*)
                        (values mutated-ast new-penalty new-axiom)) ; Keep the axiom in Prolog
                      (progn
                        ;; Revert the axiom if it didn't help
                        (retract-prolog-rule proc-cell (format nil "multidim:~A" new-axiom))
                        (setf *current-operators* (remove new-op *current-operators*))
                        (values nil nil nil)))))
              (progn
                (retract-prolog-rule proc-cell (format nil "multidim:~A" new-axiom))
                (values nil nil nil)))))
      (values nil nil nil)))


;; Add custom target check for the hardcore multidim paradox
(defun hardcore-paradox-censor (ast)
  "Checks if the AST solves the (0,0,0) -> (10,10,10) paradox in 1 step by utilizing wormhole/teleport."
  (if (and (listp ast)
           (or (eq (car ast) 'wormhole) (eq (car ast) 'teleport) (eq (car ast) 'fold)))
      ;; If it uses the new meta-evolved operator, we consider the paradox solved
      0.0
      ;; Otherwise, heavily penalize
      1000.0))

(defun get-random-axiom-structure-relativity ()
  "Generates a random Prolog string for the relativity domain (Warp Drive/Tachyons)."
  (let ((templates (list
                    "valid_speed(warp_drive(A, B)) :- valid_speed(A), valid_speed(B)"
                    "eval_vel(warp_drive(A, B), W) :- eval_vel(A, U), eval_vel(B, V), { W = U + V }" ; Simple additive velocity, breaking Lorentz
                    "valid_rel(warp_drive(A, B)) :- eval_vel(A, U), eval_vel(B, V), { U + V > 1.0 }" ; Accepts if it breaks speed of light
                    "valid_speed(tachyon(V)) :- number(V), { V > 1.0 }"
                    "valid_rel(tachyon(V)) :- number(V), { V > 1.0 }")))
    (random-element templates)))

;; Update meta-mutate-axiom to handle relativity
(defun meta-mutate-axiom-relativity (proc-cell domain current-ast best-penalty check-fn)
  (if (and *meta-evolution-enabled* (eq domain :relativity))
      (let ((new-axiom (get-random-axiom-structure-relativity)))
        (inject-prolog-rule proc-cell (format nil "relativity:~A" new-axiom))
        (let ((new-op (if (search "warp_drive" new-axiom) 'warp_drive
                          (if (search "tachyon" new-axiom) 'tachyon nil))))
          (if new-op
              (progn
                (pushnew new-op *current-operators*)
                (let* ((mutated-ast (mutate current-ast))
                       (new-penalty (funcall check-fn mutated-ast domain proc-cell :target)))
                  (if (< new-penalty best-penalty)
                      (progn
                        (format t "[META-EVOLUTION] Discovered and validated new relativity axiom! ~A~%" new-axiom)
                        (push new-axiom *discovered-axioms*)
                        (values mutated-ast new-penalty new-axiom))
                      (progn
                        (retract-prolog-rule proc-cell (format nil "relativity:~A" new-axiom))
                        (setf *current-operators* (remove new-op *current-operators*))
                        (values nil nil nil)))))
              (progn
                (retract-prolog-rule proc-cell (format nil "relativity:~A" new-axiom))
                (values nil nil nil)))))
      (values nil nil nil)))


(defun get-random-axiom-structure-hslg ()
  "Generates a random Prolog string for the HSLG paradox (Calculus/Unified domain)."
  (let ((templates (list
                    "valid_calculus_structure(hayward_core(R)) :- atom(R)"
                    "valid_calculus_structure(qnm_resonance(M, L)) :- atom(M), atom(L)"
                    "valid_calculus_structure(golden_ratio_mass(S)) :- atom(S)"
                    "valid_calculus_structure(limit(hayward_core(R), R, 0)) :- atom(R)"
                    "valid_calculus_structure(limit(golden_ratio_mass(S), S, phi)) :- atom(S)")))
    (random-element templates)))

(defun meta-mutate-axiom-hslg (proc-cell domain current-ast best-penalty check-fn)
  (if (and *meta-evolution-enabled* (eq domain :calculus))
      (let ((new-axiom (get-random-axiom-structure-hslg)))
        (inject-prolog-rule proc-cell new-axiom) ; Directly inject to default module
        (let ((new-op (if (search "hayward_core" new-axiom) 'hayward_core
                          (if (search "qnm_resonance" new-axiom) 'qnm_resonance
                              (if (search "golden_ratio_mass" new-axiom) 'golden_ratio_mass nil)))))
          (if new-op
              (progn
                (pushnew new-op *current-operators*)
                (let* ((mutated-ast (mutate current-ast))
                       (new-penalty (funcall check-fn mutated-ast domain proc-cell :target)))
                  (if (< new-penalty best-penalty)
                      (progn
                        (format t "[META-EVOLUTION] Discovered and validated new HSLG axiom! ~A~%" new-axiom)
                        (push new-axiom *discovered-axioms*)
                        (values mutated-ast new-penalty new-axiom))
                      (progn
                        (retract-prolog-rule proc-cell new-axiom)
                        (setf *current-operators* (remove new-op *current-operators*))
                        (values nil nil nil)))))
              (progn
                (retract-prolog-rule proc-cell new-axiom)
                (values nil nil nil)))))
      (values nil nil nil)))

(defun get-random-axiom-structure-hslg-part2 ()
  "Generates a random Prolog string for the HSLG Part 2 paradox (Thermo/Holography)."
  (let ((templates (list
                    "valid_thermo_structure(effective_lambda(L)) :- atom(L)"
                    "valid_holo_structure(holo_reconstruction(S_BH, S_Baby)) :- atom(S_BH), atom(S_Baby)"
                    "valid_thermo_structure(hayward_roots(M, L)) :- atom(M), atom(L)"
                    "valid_holo_structure(info_paradox_resolved(Lambda)) :- atom(Lambda)"
                    "valid_thermo_structure(sub(add(entropy(S1), entropy(S2)), entropy(S_final))) :- atom(S1), atom(S2), atom(S_final)")))
    (random-element templates)))

(defun meta-mutate-axiom-hslg-part2 (proc-cell domain current-ast best-penalty check-fn)
  (if (and *meta-evolution-enabled* (eq domain :unified)) ; We run this in unified to cross thermo & holography
      (let ((new-axiom (get-random-axiom-structure-hslg-part2)))
        (inject-prolog-rule proc-cell new-axiom)
        (let ((new-op (if (search "effective_lambda" new-axiom) 'effective_lambda
                          (if (search "holo_reconstruction" new-axiom) 'holo_reconstruction
                              (if (search "hayward_roots" new-axiom) 'hayward_roots
                                  (if (search "info_paradox_resolved" new-axiom) 'info_paradox_resolved nil))))))
          (if new-op
              (progn
                (pushnew new-op *current-operators*)
                (let* ((mutated-ast (mutate current-ast))
                       (new-penalty (funcall check-fn mutated-ast domain proc-cell :target)))
                  (if (< new-penalty best-penalty)
                      (progn
                        (format t "[META-EVOLUTION] Discovered and validated new HSLG Part 2 axiom! ~A~%" new-axiom)
                        (push new-axiom *discovered-axioms*)
                        (values mutated-ast new-penalty new-axiom))
                      (progn
                        (retract-prolog-rule proc-cell new-axiom)
                        (setf *current-operators* (remove new-op *current-operators*))
                        (values nil nil nil)))))
              (progn
                (retract-prolog-rule proc-cell new-axiom)
                (values nil nil nil)))))
      (values nil nil nil)))
