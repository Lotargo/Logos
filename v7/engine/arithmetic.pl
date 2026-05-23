% arithmetic.pl - Prolog Arithmetic constraints using clp(r)
:- use_module(library(clpr)).

% Evaluate constraints using clp(r)
arithmetic_censor(AST) :-
    % Check structural invalidities first
    \+ contains_div_zero(AST),
    \+ contains_mul_zero(AST),
    valid_arithmetic_structure(AST),
    % Prove it can be evaluated in R without contradictions
    evaluable_in_r(AST).

% Invalid structures
contains_div_zero(div(_, 0)).
contains_div_zero(add(X, _)) :- contains_div_zero(X).
contains_div_zero(add(_, Y)) :- contains_div_zero(Y).
contains_div_zero(sub(X, _)) :- contains_div_zero(X).
contains_div_zero(sub(_, Y)) :- contains_div_zero(Y).
contains_div_zero(mul(X, _)) :- contains_div_zero(X).
contains_div_zero(mul(_, Y)) :- contains_div_zero(Y).
contains_div_zero(div(X, _)) :- contains_div_zero(X).
contains_div_zero(div(_, Y)) :- contains_div_zero(Y).

contains_mul_zero(mul(0, _)).
contains_mul_zero(mul(_, 0)).
contains_mul_zero(add(X, _)) :- contains_mul_zero(X).
contains_mul_zero(add(_, Y)) :- contains_mul_zero(Y).
contains_mul_zero(sub(X, _)) :- contains_mul_zero(X).
contains_mul_zero(sub(_, Y)) :- contains_mul_zero(Y).
contains_mul_zero(mul(X, _)) :- contains_mul_zero(X).
contains_mul_zero(mul(_, Y)) :- contains_mul_zero(Y).
contains_mul_zero(div(X, _)) :- contains_mul_zero(X).
contains_mul_zero(div(_, Y)) :- contains_mul_zero(Y).

valid_arithmetic_structure(X) :- atom(X).
valid_arithmetic_structure(X) :- integer(X).
valid_arithmetic_structure(add(X, Y)) :- valid_arithmetic_structure(X), valid_arithmetic_structure(Y).
valid_arithmetic_structure(sub(X, Y)) :- valid_arithmetic_structure(X), valid_arithmetic_structure(Y).
valid_arithmetic_structure(mul(X, Y)) :- valid_arithmetic_structure(X), valid_arithmetic_structure(Y).
valid_arithmetic_structure(div(X, Y)) :- valid_arithmetic_structure(X), valid_arithmetic_structure(Y).

% Use clp(r) to ensure evaluating to a real number is physically possible
% (we bind variables to free reals)
eval_term(X, X) :- integer(X).
eval_term(X, _) :- atom(X). % Variables evaluate generically
eval_term(add(X, Y), R) :- eval_term(X, RX), eval_term(Y, RY), number(RX), number(RY), {R = RX + RY}.
eval_term(add(X, Y), _) :- \+ (eval_term(X, RX), eval_term(Y, RY), number(RX), number(RY)).
eval_term(sub(X, Y), R) :- eval_term(X, RX), eval_term(Y, RY), number(RX), number(RY), {R = RX - RY}.
eval_term(sub(X, Y), _) :- \+ (eval_term(X, RX), eval_term(Y, RY), number(RX), number(RY)).
eval_term(mul(X, Y), R) :- eval_term(X, RX), eval_term(Y, RY), number(RX), number(RY), {R = RX * RY}.
eval_term(mul(X, Y), _) :- \+ (eval_term(X, RX), eval_term(Y, RY), number(RX), number(RY)).
eval_term(div(X, Y), R) :- eval_term(X, RX), eval_term(Y, RY), number(RX), number(RY), {RY \= 0, R = RX / RY}.
eval_term(div(X, Y), _) :- \+ (eval_term(X, RX), eval_term(Y, RY), number(RX), number(RY)).

evaluable_in_r(AST) :- eval_term(AST, _).
