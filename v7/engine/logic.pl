% logic.pl - Constraints for Boolean Logic
:- module(logic, [logic_censor/1, eval_bool/4]).

is_bool(true).
is_bool(false).
is_bool(p).
is_bool(q).
is_bool(and(A, B)) :- is_bool(A), is_bool(B).
is_bool(or(A, B)) :- is_bool(A), is_bool(B).
is_bool(xor(A, B)) :- is_bool(A), is_bool(B).
is_bool(implies(A, B)) :- is_bool(A), is_bool(B).
is_bool(not(A)) :- is_bool(A).

% Evaluate logic expressions for variables p and q bound to true/false
eval_bool(true, _, _, true) :- !.
eval_bool(false, _, _, false) :- !.
eval_bool(p, P, _, P) :- !.
eval_bool(q, _, Q, Q) :- !.
eval_bool(not(A), P, Q, Res) :-
    !,
    eval_bool(A, P, Q, ValA),
    negate(ValA, Res).
eval_bool(and(A, B), P, Q, Res) :-
    !,
    eval_bool(A, P, Q, ValA),
    eval_bool(B, P, Q, ValB),
    and_op(ValA, ValB, Res).
eval_bool(or(A, B), P, Q, Res) :-
    !,
    eval_bool(A, P, Q, ValA),
    eval_bool(B, P, Q, ValB),
    or_op(ValA, ValB, Res).
eval_bool(xor(A, B), P, Q, Res) :-
    !,
    eval_bool(A, P, Q, ValA),
    eval_bool(B, P, Q, ValB),
    xor_op(ValA, ValB, Res).
eval_bool(implies(A, B), P, Q, Res) :-
    !,
    eval_bool(A, P, Q, ValA),
    eval_bool(B, P, Q, ValB),
    implies_op(ValA, ValB, Res).

negate(true, false).
negate(false, true).

and_op(true, true, true).
and_op(true, false, false).
and_op(false, true, false).
and_op(false, false, false).

or_op(true, _, true).
or_op(false, X, X).

xor_op(true, false, true).
xor_op(false, true, true).
xor_op(true, true, false).
xor_op(false, false, false).

implies_op(true, X, X).
implies_op(false, _, true).

% A logic expression is a contradiction if it evaluates to false under ALL variable assignments
is_contradiction(AST) :-
    eval_bool(AST, true, true, false),
    eval_bool(AST, true, false, false),
    eval_bool(AST, false, true, false),
    eval_bool(AST, false, false, false).

% Occam's Razor: prune logical redundancies to force elegant tauteologies
is_logic_redundant(and(true, _)).
is_logic_redundant(and(_, true)).
is_logic_redundant(and(false, _)).
is_logic_redundant(and(_, false)).
is_logic_redundant(or(true, _)).
is_logic_redundant(or(_, true)).
is_logic_redundant(or(false, _)).
is_logic_redundant(or(_, false)).
is_logic_redundant(implies(true, _)).
is_logic_redundant(implies(_, true)).
is_logic_redundant(implies(false, _)).
is_logic_redundant(implies(_, false)).
is_logic_redundant(not(not(_))).
is_logic_redundant(xor(A, A)). % Property-Based Invariant Defense: A xor A = 0

is_logic_redundant(and(A, B)) :- is_logic_redundant(A) ; is_logic_redundant(B).
is_logic_redundant(or(A, B)) :- is_logic_redundant(A) ; is_logic_redundant(B).
is_logic_redundant(xor(A, B)) :- is_logic_redundant(A) ; is_logic_redundant(B).
is_logic_redundant(implies(A, B)) :- is_logic_redundant(A) ; is_logic_redundant(B).
is_logic_redundant(not(A)) :- is_logic_redundant(A).

% The logic censor accepts an AST if it is syntactically a bool,
% NOT a logical contradiction, and NOT algebraic/redundant.
logic_censor(AST) :-
    is_bool(AST),
    \+ is_contradiction(AST),
    \+ is_logic_redundant(AST).
