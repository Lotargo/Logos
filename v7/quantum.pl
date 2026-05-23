% quantum.pl - Prolog Quantum Physics invariants

quantum_censor(AST) :-
    valid_quantum_structure(AST).

% Atoms are qubits
valid_quantum_structure(X) :- atom(X).

% Quantum Gates
valid_quantum_structure(h(X)) :- valid_quantum_structure(X).
valid_quantum_structure(x_gate(X)) :- valid_quantum_structure(X).
valid_quantum_structure(y_gate(X)) :- valid_quantum_structure(X).
valid_quantum_structure(z_gate(X)) :- valid_quantum_structure(X).
valid_quantum_structure(cnot(Control, Target)) :-
    valid_quantum_structure(Control),
    valid_quantum_structure(Target),
    Control \= Target. % Control and Target qubits cannot be the same.

% Sequences of operations seq(Op1, Op2, ... ) is not trivial in AST, we will treat seq(A, B) as chaining
valid_quantum_structure(seq(A, B)) :-
    valid_quantum_structure(A),
    valid_quantum_structure(B).

% Tensor product of two states
valid_quantum_structure(tensor(A, B)) :-
    valid_quantum_structure(A),
    valid_quantum_structure(B).
