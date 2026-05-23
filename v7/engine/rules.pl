% rules.pl - Universal Prolog Mathematical Censor
% Master file routing to specialized modules

:- consult('arithmetic.pl').
:- consult('calculus.pl').
:- consult('quantum.pl').
:- consult('multidim.pl').

% Dispatcher based on Domain
censor(arithmetic, AST) :-
    arithmetic_censor(AST).

censor(calculus, AST) :-
    calculus_censor(AST).

censor(quantum, AST) :-
    quantum_censor(AST).

censor(multidim, AST) :-
    multidim:multidim_censor(AST).
