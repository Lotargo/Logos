% quantum.pl - Prolog Quantum Physics invariants & Dynamic N-Qubit Hilbert Space Simulator

quantum_censor(AST) :-
    valid_quantum_structure(AST),
    \+ is_quantum_redundant(AST),
    find_qubits(AST, RawQubits),
    (   RawQubits = []
    ->  Qubits = [q1, q2]
    ;   (   length(RawQubits, 1)
        ->  union(RawQubits, [q2], Qubits)
        ;   Qubits = RawQubits
        )
    ),
    sort_qubits(Qubits, SortedQs),
    length(SortedQs, N),
    create_ground_state(N, GroundVec),
    GroundState = [amp(c(1, 0), GroundVec)],
    eval_quantum(AST, SortedQs, GroundState, FinalState),
    is_bell_state(FinalState, SortedQs).

% Qubit name format is q followed by integer
valid_quantum_structure(X) :- atom(X), atom_concat(q, _, X), !.

% Quantum Gates structure
valid_quantum_structure(h(X)) :- valid_quantum_structure(X).
valid_quantum_structure(x_gate(X)) :- valid_quantum_structure(X).
valid_quantum_structure(y_gate(X)) :- valid_quantum_structure(X).
valid_quantum_structure(z_gate(X)) :- valid_quantum_structure(X).
valid_quantum_structure(cnot(Control, Target)) :-
    valid_quantum_structure(Control),
    valid_quantum_structure(Target),
    Control \= Target.

% Sequences and tensors
valid_quantum_structure(seq(A, B)) :-
    valid_quantum_structure(A),
    valid_quantum_structure(B).
valid_quantum_structure(tensor(A, B)) :-
    valid_quantum_structure(A),
    valid_quantum_structure(B).

% Occam's Razor: prune physical self-inverse gate redundancies
is_quantum_redundant(h(h(_))).
is_quantum_redundant(x_gate(x_gate(_))).
is_quantum_redundant(y_gate(y_gate(_))).
is_quantum_redundant(z_gate(z_gate(_))).
is_quantum_redundant(seq(A, B)) :- A == B, is_self_inverse(A).

% Propagate redundancy checks
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

% =======================================================================
% Dynamic Qubit List Extractors & Sorters
% =======================================================================

find_qubits(Q, [Q]) :- atom(Q), atom_concat(q, _, Q), !.
find_qubits(h(Q), Qs) :- !, find_qubits(Q, Qs).
find_qubits(x_gate(Q), Qs) :- !, find_qubits(Q, Qs).
find_qubits(y_gate(Q), Qs) :- !, find_qubits(Q, Qs).
find_qubits(z_gate(Q), Qs) :- !, find_qubits(Q, Qs).
find_qubits(cnot(C, T), Qs) :-
    !,
    find_qubits(C, QsC),
    find_qubits(T, QsT),
    union(QsC, QsT, Qs).
find_qubits(seq(A, B), Qs) :-
    !,
    find_qubits(A, QsA),
    find_qubits(B, QsB),
    union(QsA, QsB, Qs).
find_qubits(tensor(A, B), Qs) :-
    !,
    find_qubits(A, QsA),
    find_qubits(B, QsB),
    union(QsA, QsB, Qs).
find_qubits(_, []).

sort_qubits(Qs, Sorted) :-
    predsort(compare_qubits, Qs, Sorted).

compare_qubits(Delta, Q1, Q2) :-
    (   atom_concat(q, NumStr1, Q1),
        atom_concat(q, NumStr2, Q2),
        atom_number(NumStr1, N1),
        atom_number(NumStr2, N2)
    ->  compare(Delta, N1, N2)
    ;   compare(Delta, Q1, Q2)
    ).

qubit_position(Q, [Q|_], 0) :- !.
qubit_position(Q, [_|T], Index) :-
    qubit_position(Q, T, Index1),
    Index is Index1 + 1.

create_ground_state(0, []) :- !.
create_ground_state(N, [0|T]) :-
    N > 0,
    N1 is N - 1,
    create_ground_state(N1, T).

% =======================================================================
% Symbolic Hilbert Space Simulator
% =======================================================================

get_bit([B|_], 0, B) :- !.
get_bit([_|T], I, B) :- I > 0, I1 is I - 1, get_bit(T, I1, B).

set_bit([_|T], 0, Val, [Val|T]) :- !.
set_bit([H|T], I, Val, [H|R]) :- I > 0, I1 is I - 1, set_bit(T, I1, Val, R).

simplify_state([], []).
simplify_state([H|T], Out) :-
    simplify_state(T, Mid),
    add_to_state(H, Mid, Out).

add_to_state(amp(c(N, R), Vec), [], [amp(c(N, R), Vec)]) :- !.
add_to_state(amp(c(N1, R), Vec), [amp(c(N2, R), Vec)|T], Out) :-
    !,
    N3 is N1 + N2,
    (   N3 =:= 0
    ->  Out = T
    ;   Out = [amp(c(N3, R), Vec)|T]
    ).
add_to_state(amp(c(N1, R1), Vec), [amp(c(N2, R2), Vec)|T], Out) :-
    !,
    MaxR is max(R1, R2),
    scale_amp(c(N1, R1), MaxR, c(Scal1, MaxR)),
    scale_amp(c(N2, R2), MaxR, c(Scal2, MaxR)),
    N3 is Scal1 + Scal2,
    (   N3 =:= 0
    ->  Out = T
    ;   Out = [amp(c(N3, MaxR), Vec)|T]
    ).
add_to_state(Term, [H|T], [H|R]) :-
    add_to_state(Term, T, R).

scale_amp(c(N, R), TargetR, c(Scal, TargetR)) :-
    Diff is TargetR - R,
    (   Diff =:= 0
    ->  Scal = N
    ;   (   Diff mod 2 =:= 0
        ->  Power is Diff // 2,
            Scal is N * (2 ** Power)
        ;   Scal = N
        )
    ).

% Gate Applications
apply_h_to_state(Index, InState, OutState) :-
    apply_h_loop(InState, Index, RawState),
    simplify_state(RawState, OutState).

apply_h_loop([], _, []).
apply_h_loop([amp(c(N, R), Vec)|T], Index, [amp(c(N, R1), Vec0), amp(c(SignN, R1), Vec1)|Rrest]) :-
    R1 is R + 1,
    get_bit(Vec, Index, Bit),
    set_bit(Vec, Index, 0, Vec0),
    set_bit(Vec, Index, 1, Vec1),
    (   Bit =:= 0
    ->  SignN = N
    ;   SignN is -N
    ),
    apply_h_loop(T, Index, Rrest).

apply_x_to_state(Index, InState, OutState) :-
    apply_x_loop(InState, Index, RawState),
    simplify_state(RawState, OutState).

apply_x_loop([], _, []).
apply_x_loop([amp(Coeff, Vec)|T], Index, [amp(Coeff, NewVec)|Rrest]) :-
    get_bit(Vec, Index, Bit),
    (   Bit =:= 0
    ->  NewBit = 1
    ;   NewBit = 0
    ),
    set_bit(Vec, Index, NewBit, NewVec),
    apply_x_loop(T, Index, Rrest).

apply_cnot_to_state(IndexC, IndexT, InState, OutState) :-
    apply_cnot_loop(InState, IndexC, IndexT, RawState),
    simplify_state(RawState, OutState).

apply_cnot_loop([], _, _, []).
apply_cnot_loop([amp(Coeff, Vec)|T], IndexC, IndexT, [amp(Coeff, NewVec)|Rrest]) :-
    get_bit(Vec, IndexC, BitC),
    (   BitC =:= 1
    ->  get_bit(Vec, IndexT, BitT),
        (   BitT =:= 0
        ->  NewBitT = 1
        ;   NewBitT = 0
        ),
        set_bit(Vec, IndexT, NewBitT, NewVec)
    ;   NewVec = Vec
    ),
    apply_cnot_loop(T, IndexC, IndexT, Rrest).

% eval_quantum(AST, SortedQs, InState, OutState)
eval_quantum(X, _, State, State) :- atom(X), !.

eval_quantum(h(Q), SortedQs, InState, OutState) :-
    !,
    qubit_position(Q, SortedQs, Index),
    apply_h_to_state(Index, InState, OutState).

eval_quantum(x_gate(Q), SortedQs, InState, OutState) :-
    !,
    qubit_position(Q, SortedQs, Index),
    apply_x_to_state(Index, InState, OutState).

eval_quantum(cnot(C, T), SortedQs, InState, OutState) :-
    !,
    qubit_position(C, SortedQs, IndexC),
    qubit_position(T, SortedQs, IndexT),
    apply_cnot_to_state(IndexC, IndexT, InState, OutState).

eval_quantum(seq(A, B), SortedQs, InState, OutState) :-
    !,
    eval_quantum(A, SortedQs, InState, MidState),
    eval_quantum(B, SortedQs, MidState, OutState).

eval_quantum(tensor(A, B), SortedQs, InState, OutState) :-
    !,
    eval_quantum(A, SortedQs, InState, MidState),
    eval_quantum(B, SortedQs, MidState, OutState).

is_bell_state(State, SortedQs) :-
    length(SortedQs, N),
    length(State, 2),
    member(amp(c(1, 1), V0), State),
    member(amp(c(1, 1), V1), State),
    V0 = [0, 0 | Rest],
    V1 = [1, 1 | Rest],
    all_zeros(Rest).

all_zeros([]).
all_zeros([0|T]) :- all_zeros(T).
