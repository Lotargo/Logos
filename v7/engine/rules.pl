% rules.pl - Universal Prolog Mathematical Censor
% Master file routing to specialized modules

:- consult('arithmetic.pl').
:- consult('calculus.pl').
:- consult('quantum.pl').
:- consult('multidim.pl').
:- consult('relativity.pl').
:- consult('thermo.pl').
:- consult('holography.pl').
:- consult('logic.pl').

% Dispatcher based on Domain
censor(arithmetic, AST) :-
    arithmetic_censor(AST).

censor(calculus, AST) :-
    calculus_censor(AST).

censor(quantum, AST) :-
    quantum_censor(AST).

censor(multidim, AST) :-
    multidim:multidim_censor(AST).

censor(relativity, AST) :-
    relativity:relativity_censor(AST).

censor(thermo, AST) :-
    thermo:thermo_censor(AST).

censor(holography, AST) :-
    holography:holography_censor(AST).

censor(logic, AST) :-
    logic:logic_censor(AST).
