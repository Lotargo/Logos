% rules.pl - Universal Prolog Mathematical Censor
% Master file routing to specialized modules with Heuristic Penalty outputs

:- consult('arithmetic.pl').
:- consult('calculus.pl').
:- consult('quantum.pl').
:- consult('multidim.pl').
:- consult('relativity.pl').
:- consult('thermo.pl').
:- consult('holography.pl').
:- consult('logic.pl').

% Dispatcher based on Domain returning float Penalty (0.0 is perfect, 1000.0 is worst)
censor(arithmetic, AST, Penalty) :-
    !,
    arithmetic_censor(AST, Penalty).

censor(quantum, AST, Penalty) :-
    !,
    quantum_censor(AST, Penalty).

censor(calculus, AST, Penalty) :-
    !,
    (   calculus_censor(AST)
    ->  Penalty = 0.0
    ;   Penalty = 1000.0
    ).

censor(multidim, AST, Penalty) :-
    !,
    (   multidim:multidim_censor(AST)
    ->  Penalty = 0.0
    ;   Penalty = 1000.0
    ).

censor(relativity, AST, Penalty) :-
    !,
    (   relativity:relativity_censor(AST)
    ->  Penalty = 0.0
    ;   Penalty = 1000.0
    ).

censor(thermo, AST, Penalty) :-
    !,
    (   thermo:thermo_censor(AST)
    ->  Penalty = 0.0
    ;   Penalty = 1000.0
    ).

censor(holography, AST, Penalty) :-
    !,
    (   holography:holography_censor(AST)
    ->  Penalty = 0.0
    ;   Penalty = 1000.0
    ).

censor(logic, AST, Penalty) :-
    !,
    (   logic:logic_censor(AST)
    ->  Penalty = 0.0
    ;   Penalty = 1000.0
    ).

censor(unified, AST, Penalty) :-
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
    quantum_censor(AST, Penalty).

% Thermodynamics sub-expressions
unified_eval(AST, Penalty) :-
    is_thermo_expr(AST),
    !,
    (   thermo:thermo_censor(AST)
    ->  Penalty = 0.0
    ;   Penalty = 1000.0
    ).

% Relativity sub-expressions
unified_eval(AST, Penalty) :-
    is_rel_expr(AST),
    !,
    (   relativity:relativity_censor(AST)
    ->  Penalty = 0.0
    ;   Penalty = 1000.0
    ).

% Holography sub-expressions
unified_eval(AST, Penalty) :-
    is_holo_expr(AST),
    !,
    (   holography:holography_censor(AST)
    ->  Penalty = 0.0
    ;   Penalty = 1000.0
    ).

% Multidimensional sub-expressions
unified_eval(AST, Penalty) :-
    is_multidim_expr(AST),
    !,
    (   multidim:multidim_censor(AST)
    ->  Penalty = 0.0
    ;   Penalty = 1000.0
    ).

% Calculus sub-expressions
unified_eval(AST, Penalty) :-
    is_calc_expr(AST),
    !,
    (   calculus_censor(AST)
    ->  Penalty = 0.0
    ;   Penalty = 1000.0
    ).

% Logic sub-expressions
unified_eval(AST, Penalty) :-
    is_logic_expr(AST),
    !,
    (   logic:logic_censor(AST)
    ->  Penalty = 0.0
    ;   Penalty = 1000.0
    ).

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

is_thermo_expr(carnot(_, _)).
is_thermo_expr(delta_s(_)).

is_rel_expr(gamma(_)).
is_rel_expr(add_vel(_, _)).

is_holo_expr(entropy(_)).
is_holo_expr(info_bound(_)).

is_multidim_expr(matmul(_, _)).
is_multidim_expr(transpose(_)).
is_multidim_expr(cross(_, _)).
is_multidim_expr(dot(_, _)).
is_multidim_expr(scale(_, _)).
is_multidim_expr(norm(_)).

is_calc_expr(deriv(_, _)).
is_calc_expr(int(_, _)).
is_calc_expr(sin(_)).
is_calc_expr(cos(_)).

is_logic_expr(and(_, _)).
is_logic_expr(or(_, _)).
is_logic_expr(implies(_, _)).
is_logic_expr(not(_)).

