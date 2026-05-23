% quantum.pl - Prolog Quantum Physics invariants

quantum_censor(AST) :-
    \+ is_quantum_redundant(AST),
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

% Occam's Razor: prune physical self-inverse gate redundancies (H^2 = I, X^2 = I, Y^2 = I, Z^2 = I)
is_quantum_redundant(h(h(_))).
is_quantum_redundant(x_gate(x_gate(_))).
is_quantum_redundant(y_gate(y_gate(_))).
is_quantum_redundant(z_gate(z_gate(_))).

% Redundant operations in sequence chains
is_quantum_redundant(seq(A, B)) :- A == B, is_self_inverse(A).

% Propagate redundancy checks down the AST
is_quantum_redundant(h(X)) :- is_quantum_redundant(X).
is_quantum_redundant(x_gate(X)) :- is_quantum_redundant(X).
is_quantum_redundant(y_gate(X)) :- is_quantum_redundant(X).
is_quantum_redundant(z_gate(X)) :- is_quantum_redundant(X).
is_quantum_redundant(cnot(C, _)) :- is_quantum_redundant(C).
is_quantum_redundant(cnot(_, T)) :- is_quantum_redundant(T).
is_quantum_redundant(seq(A, _)) :- is_quantum_redundant(A).
is_quantum_redundant(seq(_, B)) :- is_quantum_redundant(B).
is_quantum_redundant(tensor(A, _)) :- is_quantum_redundant(A).
is_quantum_redundant(tensor(_, B)) :- is_quantum_redundant(B).

is_self_inverse(h(_)).
is_self_inverse(x_gate(_)).
is_self_inverse(y_gate(_)).
is_self_inverse(z_gate(_)).
