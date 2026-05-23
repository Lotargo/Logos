% logic.pl - Constraints for Boolean Logic
:- module(logic, [logic_censor/1]).

is_bool(true).
is_bool(false).
is_bool(p).
is_bool(q).
is_bool(and(A, B)) :- is_bool(A), is_bool(B).
is_bool(or(A, B)) :- is_bool(A), is_bool(B).
is_bool(implies(A, B)) :- is_bool(A), is_bool(B).
is_bool(not(A)) :- is_bool(A).

logic_censor(AST) :- is_bool(AST).
