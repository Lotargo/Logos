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
