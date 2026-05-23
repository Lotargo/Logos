% relativity.pl - Constraints for Special Relativity
:- module(relativity, [relativity_censor/1]).

% Speeds strictly less than c
valid_v(v1).
valid_v(v2).
valid_v(0).
valid_v(add_vel(A, B)) :-
    valid_v(A),
    valid_v(B).

% c is the speed of light, massive particles cannot reach it.
% valid_v(c) is explicitly NOT defined.

valid_rel(V) :- valid_v(V).
valid_rel(gamma(V)) :-
    valid_v(V).

relativity_censor(AST) :- valid_rel(AST).
