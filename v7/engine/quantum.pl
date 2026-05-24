% quantum.pl - Prolog Quantum Physics invariants & Heuristic Penalty Quantum Simulator

quantum_censor(AST, Penalty) :-
    (   \+ valid_quantum_structure(AST)
    ->  Penalty = 1000.0
    ;   (   \+ is_unitary_ast(AST)
        ->  Penalty = 1000.0
        ;   (   is_quantum_redundant(AST)
            ->  Penalty = 900.0
            ;   find_qubits(AST, RawQubits),
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
                % Initial state for Grover's should be equal superposition,
                % but standard practice is starting from |00> and engine must apply H gates itself
                GroundState = [amp(c(1, 0), GroundVec)],
                (   catch(eval_quantum(AST, SortedQs, GroundState, FinalState), _, fail)
                ->  quantum_fidelity(FinalState, SortedQs, Fidelity),
                    BasePenalty is 1000.0 * (1.0 - Fidelity),
                    % Occam's Razor: If fidelity is very high (> 0.99), apply minor penalty for AST size
                    (   Fidelity > 0.99
                    ->  ast_size(AST, Size),
                        Penalty is BasePenalty + (Size * 0.01)
                    ;   Penalty = BasePenalty
                    )
                ;   Penalty = 1000.0
                )
            )
        )
    ).

% Simple AST node counter
ast_size(AST, Size) :-
    (   atomic(AST)
    ->  Size = 1
    ;   compound(AST)
    ->  AST =.. [_|Args],
        map_ast_size(Args, ArgSizes),
        sum_list(ArgSizes, Sum),
        Size is Sum + 1
    ).

map_ast_size([], []).
map_ast_size([H|T], [S|ST]) :-
    ast_size(H, S),
    map_ast_size(T, ST).

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
valid_quantum_structure(oracle(Control, Target)) :-
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
is_quantum_redundant(oracle(oracle(_, _))).
is_quantum_redundant(seq(A, B)) :- A == B, is_self_inverse(A).

% Propagate redundancy checks
is_quantum_redundant(h(X)) :- is_quantum_redundant(X).
is_quantum_redundant(x_gate(X)) :- is_quantum_redundant(X).
is_quantum_redundant(y_gate(X)) :- is_quantum_redundant(X).
is_quantum_redundant(z_gate(X)) :- is_quantum_redundant(X).
is_quantum_redundant(cnot(C, _)) :- is_quantum_redundant(C).
is_quantum_redundant(cnot(_, T)) :- is_quantum_redundant(T).
is_quantum_redundant(oracle(Q1, _)) :- is_quantum_redundant(Q1).
is_quantum_redundant(oracle(_, Q2)) :- is_quantum_redundant(Q2).
is_quantum_redundant(seq(A, _)) :- is_quantum_redundant(A).
is_quantum_redundant(seq(_, B)) :- is_quantum_redundant(B).
is_quantum_redundant(tensor(A, _)) :- is_quantum_redundant(A).
is_quantum_redundant(tensor(_, B)) :- is_quantum_redundant(B).

is_self_inverse(h(_)).
is_self_inverse(x_gate(_)).
is_self_inverse(y_gate(_)).
is_self_inverse(z_gate(_)).
is_self_inverse(oracle(_, _)).

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
find_qubits(oracle(Q1, Q2), Qs) :-
    !,
    find_qubits(Q1, Qs1),
    find_qubits(Q2, Qs2),
    union(Qs1, Qs2, Qs).
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

apply_oracle_to_state(Index1, Index2, InState, OutState) :-
    apply_oracle_loop(InState, Index1, Index2, RawState),
    simplify_state(RawState, OutState).

apply_oracle_loop([], _, _, []).
apply_oracle_loop([amp(c(N, R), Vec)|T], Index1, Index2, [amp(c(SignN, R), Vec)|Rrest]) :-
    get_bit(Vec, Index1, Bit1),
    get_bit(Vec, Index2, Bit2),
    (   (Bit1 =:= 1, Bit2 =:= 1) % Target state is |11>
    ->  SignN is -N
    ;   SignN = N
    ),
    apply_oracle_loop(T, Index1, Index2, Rrest).

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

eval_quantum(oracle(Q1, Q2), SortedQs, InState, OutState) :-
    !,
    qubit_position(Q1, SortedQs, Index1),
    qubit_position(Q2, SortedQs, Index2),
    apply_oracle_to_state(Index1, Index2, InState, OutState).

eval_quantum(seq(A, B), SortedQs, InState, OutState) :-
    !,
    eval_quantum(A, SortedQs, InState, MidState),
    eval_quantum(B, SortedQs, MidState, OutState).

eval_quantum(tensor(A, B), SortedQs, InState, OutState) :-
    !,
    eval_quantum(A, SortedQs, InState, MidState),
    eval_quantum(B, SortedQs, MidState, OutState).

% =======================================================================
% Continuous Quantum Fidelity Gradients
% =======================================================================

coeff_to_float(c(N, R), Val) :-
    Val is N / (sqrt(2) ** R).

get_state_amplitude(Vec, State, Amp) :-
    (   member(amp(Coeff, Vec), State)
    ->  coeff_to_float(Coeff, Amp)
    ;   Amp = 0.0
    ).

quantum_fidelity(State, SortedQs, Fidelity) :-
    length(SortedQs, N),
    (   N < 2
    ->  Fidelity = 0.0
    ;   % Grover's Algorithm goal: Maximize amplitude of |11...1> state
        create_grover_target(N, TargetVec),
        get_state_amplitude(TargetVec, State, Amp),
        Fidelity is Amp * Amp % Probability of measuring target state
    ).

create_grover_target(0, []) :- !.
create_grover_target(N, [1|T]) :-
    N > 0,
    N1 is N - 1,
    create_grover_target(N1, T).

all_zeros([]).
all_zeros([0|T]) :- all_zeros(T).


% =======================================================================
% Semantic Unitary Verification (Algebraic Matrices)
% =======================================================================

% Map Gates to Real Matrices
gate_matrix(h(_), [[0.70710678, 0.70710678], [0.70710678, -0.70710678]]).
gate_matrix(x_gate(_), [[0.0, 1.0], [1.0, 0.0]]).
gate_matrix(y_gate(_), [[0.0, -1.0], [1.0, 0.0]]). % Assuming Real representation for PoC (iY)
gate_matrix(z_gate(_), [[1.0, 0.0], [0.0, -1.0]]).
gate_matrix(cnot(_, _), [[1.0, 0.0, 0.0, 0.0], [0.0, 1.0, 0.0, 0.0], [0.0, 0.0, 0.0, 1.0], [0.0, 0.0, 1.0, 0.0]]).
gate_matrix(oracle(_, _), [[1.0, 0.0, 0.0, 0.0], [0.0, 1.0, 0.0, 0.0], [0.0, 0.0, 1.0, 0.0], [0.0, 0.0, 0.0, -1.0]]). % Flips sign of |11>

build_unitary(X, M) :- gate_matrix(X, M), !.
build_unitary(seq(A, B), M) :-
    build_unitary(A, M_A),
    build_unitary(B, M_B),
    length(M_A, L_A),
    length(M_B, L_B),
    (   L_A =:= L_B
    ->  matrix_multiply(M_B, M_A, M) % For sequential gates, matrices must be same size
    ;   M = [[1.0, 0.0], [0.0, 1.0]] % Mismatch size fallback
    ).
build_unitary(tensor(_, _), [[1.0, 0.0, 0.0, 0.0], [0.0, 1.0, 0.0, 0.0], [0.0, 0.0, 1.0, 0.0], [0.0, 0.0, 0.0, 1.0]]). % Fallback identity 4x4
build_unitary(_, [[1.0, 0.0], [0.0, 1.0]]). % Fallback identity 2x2

% Vector dot product
dot_product([], [], 0.0).
dot_product([H1|T1], [H2|T2], Result) :-
    dot_product(T1, T2, Rest),
    Result is H1 * H2 + Rest.

% Get column from matrix
get_column([], _, []).
get_column([Row|Matrix], ColIndex, [Elem|ColRest]) :-
    nth0(ColIndex, Row, Elem),
    get_column(Matrix, ColIndex, ColRest).

% Matrix multiplication
matrix_multiply(M1, M2, Result) :-
    M2 = [Row1|_],
    length(Row1, NumCols),
    numlist(0, NumCols, ColIndicesExt),
    append(ColIndices, [_], ColIndicesExt),
    maplist(multiply_row(M2, ColIndices), M1, Result).

multiply_row(M2, ColIndices, Row, ResultRow) :-
    maplist(multiply_cell(M2, Row), ColIndices, ResultRow).

multiply_cell(M2, Row, ColIndex, Result) :-
    get_column(M2, ColIndex, Col),
    dot_product(Row, Col, Result).

% Matrix transpose (Conjugate Transpose for Real matrices)
transpose([[]|_], []).
transpose(Matrix, [Col|T]) :-
    matrix_first_col(Matrix, Col, RestMatrix),
    transpose(RestMatrix, T).

matrix_first_col([], [], []).
matrix_first_col([[H|T]|Rows], [H|Hs], [T|Ts]) :-
    matrix_first_col(Rows, Hs, Ts).

% Round matrix elements to handle float inaccuracies
round_matrix([], []).
round_matrix([Row|T], [RRow|RT]) :-
    maplist(round_elem, Row, RRow),
    round_matrix(T, RT).

round_elem(E, RE) :- RE is round(E * 1000000.0) / 1000000.0.

% Check Identity matrix
is_identity_matrix(M) :-
    length(M, N),
    numlist(0, N, IndicesExt),
    append(Indices, [_], IndicesExt),
    maplist(check_identity_row(N), Indices, M).

check_identity_row(N, RowIndex, Row) :-
    length(Row, N),
    nth0(RowIndex, Row, 1.0),
    sum_list(Row, 1.0).

% Full Unitary Check (U * U^T = I)
is_unitary_ast(AST) :-
    build_unitary(AST, U),
    transpose(U, UT),
    matrix_multiply(U, UT, Product),
    round_matrix(Product, RoundedProduct),
    is_identity_matrix(RoundedProduct).
