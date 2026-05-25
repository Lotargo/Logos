% rules.pl - Universal Prolog Mathematical Censor
% Master file routing to specialized modules with Heuristic Penalty outputs

:- consult('root_axioms.pl').
:- consult('hardware.pl').
:- consult('regression.pl').
:- consult('adversarial.pl').
:- consult('curry_howard.pl').

% Dispatcher based on Domain returning float Penalty (0.0 is perfect, 1000.0 is worst)

:- dynamic novelty_archive/2.
:- dynamic unified_eval/2.

% Master dispatcher entry point from daemon
censor(Mode, Domain, AST, Penalty) :-
    (   Mode == target
    ->  target_censor(Domain, AST, Penalty)
    ;   novelty_censor(Domain, AST, Penalty)
    ).

% Open-Ended Evolution / Novelty Search Censor
novelty_censor(Domain, AST, Penalty) :-
    % First, verify it's a valid structure using the target_censor (expecting a valid penalty < 1000)
    target_censor(Domain, AST, BasePenalty),
    (   BasePenalty >= 1000.0
    ->  Penalty = 1000.0 % Invalid physics/math gets rejected
    ;   % Valid! Now check if we discovered a novel state (phenotype)
        (   get_state(Domain, AST, State)
        ->  (   novelty_archive(Domain, State)
            ->  % Already discovered. Still valid, but not novel.
                % Calculate AST size to give a slight gradient for golfing known states
                rules_ast_size(AST, Size),
                Penalty is 500.0 + (Size * 2.0)
            ;   % NEW DISCOVERY!
                assertz(novelty_archive(Domain, State)),
                rules_ast_size(AST, Size),
                % Small penalty for size to encourage elegant discoveries
                Penalty is 0.0 + (Size * 0.1)
            )
        ;   % Could not extract a clear state, just use base penalty
            Penalty = BasePenalty
        )
    ).

% Phenotype extraction: Map ASTs to concrete math/physics states
get_state(quantum, AST, State) :-
    root_axioms:build_unitary(AST, State).

get_state(arithmetic, AST, State) :-
    % Simplification acts as the state mapping for arithmetic
    root_axioms:full_simplify(AST, State).

get_state(logic, AST, State) :-
    % For logic, the state is its truth table (TT, TF, FT, FF)
    root_axioms:eval_bool(AST, true, true, S1),
    root_axioms:eval_bool(AST, true, false, S2),
    root_axioms:eval_bool(AST, false, true, S3),
    root_axioms:eval_bool(AST, false, false, S4),
    State = truth_table(S1, S2, S3, S4).

% Simple AST node counter
rules_ast_size(AST, Size) :-
    (   atomic(AST)
    ->  Size = 1
    ;   compound(AST)
    ->  AST =.. [_|Args],
        map_rules_ast_size(Args, ArgSizes),
        sum_list(ArgSizes, Sum),
        Size is Sum + 1
    ).

map_rules_ast_size([], []).
map_rules_ast_size([H|T], [S|ST]) :-
    rules_ast_size(H, S),
    map_rules_ast_size(T, ST).

target_censor(arithmetic, AST, Penalty) :-
    !,
    (   root_axioms:expr(AST)
    ->  root_axioms:count_redundancies(AST, Count),
        (   Count > 0
        ->  Penalty = 1000.0 % Strict Occam's Razor
        ;   Penalty = 0.0
        )
    ;   Penalty = 1000.0
    ).

target_censor(quantum, AST, Penalty) :-
    !,
    (   root_axioms:is_unitary_ast(AST)
    ->  Penalty = 0.0
    ;   Penalty = 1000.0
    ).

target_censor(regression, AST, Penalty) :-
    !,
    regression_censor(AST, Penalty).

target_censor(adversarial, AST, Penalty) :-
    !,
    adversarial_censor(AST, Penalty).

target_censor(curry_howard, AST, Penalty) :-
    !,
    curry_censor(AST, Penalty).

target_censor(logic, AST, Penalty) :-
    !,
    root_axioms:logic_censor(AST, Penalty).

target_censor(hardware, AST, Penalty) :-
    !,
    hardware:hardware_censor(AST, Penalty).

target_censor(unified, AST, Penalty) :-
    !,
    unified_censor(AST, Penalty).

unified_censor(AST, Penalty) :-
    unified_eval(AST, Penalty).

% Base cases
unified_eval(X, 0.0) :- atom(X), !.
unified_eval(X, 0.0) :- number(X), !.

% Quantum sub-expressions (evaluate as a whole quantum block)
unified_eval(AST, Penalty) :-
    is_quantum_expr(AST),
    !,
    (   root_axioms:is_unitary_ast(AST)
    ->  Penalty = 0.0
    ;   Penalty = 1000.0
    ).

% Logic sub-expressions
unified_eval(AST, Penalty) :-
    is_logic_expr(AST),
    !,
    root_axioms:logic_censor(AST, Penalty).

% Arithmetic operators (recursive traversal + soft Occam's Razor)
unified_eval(add(A, B), Penalty) :-
    !,
    unified_eval(A, PA),
    unified_eval(B, PB),
    (   (A == 0 ; B == 0)
    ->  PR = 20.0
    ;   PR = 0.0
    ),
    Penalty is PA + PB + PR.

unified_eval(sub(A, B), Penalty) :-
    !,
    unified_eval(A, PA),
    unified_eval(B, PB),
    (   (B == 0 ; A == B)
    ->  PR = 20.0
    ;   PR = 0.0
    ),
    Penalty is PA + PB + PR.

unified_eval(mul(A, B), Penalty) :-
    !,
    (   (A == 0 ; B == 0)
    ->  Penalty = 1000.0
    ;   unified_eval(A, PA),
        unified_eval(B, PB),
        (   (A == 1 ; B == 1)
        ->  PR = 20.0
        ;   PR = 0.0
        ),
        Penalty is PA + PB + PR
    ).

unified_eval(div(A, B), Penalty) :-
    !,
    (   B == 0
    ->  Penalty = 1000.0
    ;   unified_eval(A, PA),
        unified_eval(B, PB),
        (   (B == 1 ; A == B)
        ->  PR = 20.0
        ;   PR = 0.0
        ),
        Penalty is PA + PB + PR
    ).

% Catch-all fallback for other compound terms
unified_eval(AST, Penalty) :-
    compound(AST),
    !,
    AST =.. [_|Args],
    map_unified_eval(Args, Penalty).

map_unified_eval([], 0.0).
map_unified_eval([H|T], Penalty) :-
    unified_eval(H, P1),
    map_unified_eval(T, P2),
    Penalty is P1 + P2.

% Helper Domain Classifiers
is_quantum_expr(seq(_, _)).
is_quantum_expr(tensor(_, _)).
is_quantum_expr(h(_)).
is_quantum_expr(x_gate(_)).
is_quantum_expr(y_gate(_)).
is_quantum_expr(z_gate(_)).
is_quantum_expr(cnot(_, _)).
is_quantum_expr(oracle(_, _)).

is_logic_expr(and(_, _)).
is_logic_expr(or(_, _)).
is_logic_expr(xor(_, _)).
is_logic_expr(implies(_, _)).
is_logic_expr(not(_)).
