% arithmetic.pl - Prolog Arithmetic constraints using clp(r) & Heuristic Penalty Occam's Razor
:- use_module(library(clpr)).

% Evaluate constraints using clp(r) and return Heuristic Penalty
arithmetic_censor(AST, Penalty) :-
    (   (contains_div_zero(AST) ; contains_mul_zero(AST))
    ->  Penalty = 1000.0
    ;   (   \+ valid_arithmetic_structure(AST)
        ->  Penalty = 1000.0
        ;   (   \+ evaluable_in_r(AST)
            ->  Penalty = 950.0
            ;   count_redundancies(AST, Count),
                Penalty is Count * 20.0
            )
        )
    ).

% Invalid structures: Division by zero
contains_div_zero(div(_, 0)).
contains_div_zero(add(X, _)) :- contains_div_zero(X).
contains_div_zero(add(_, Y)) :- contains_div_zero(Y).
contains_div_zero(sub(X, _)) :- contains_div_zero(X).
contains_div_zero(sub(_, Y)) :- contains_div_zero(Y).
contains_div_zero(mul(X, _)) :- contains_div_zero(X).
contains_div_zero(mul(_, Y)) :- contains_div_zero(Y).
contains_div_zero(div(X, _)) :- contains_div_zero(X).
contains_div_zero(div(_, Y)) :- contains_div_zero(Y).

% Invalid structures: Multiplying by zero
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

% Recursive Redundancy Counter (Occam's soft constraints)
count_redundancies(add(0, X), N) :- !, count_redundancies(X, N1), N is N1 + 1.
count_redundancies(add(X, 0), N) :- !, count_redundancies(X, N1), N is N1 + 1.
count_redundancies(sub(X, 0), N) :- !, count_redundancies(X, N1), N is N1 + 1.
count_redundancies(sub(X, Y), N) :- X == Y, !, count_redundancies(X, N1), N is N1 + 1.
count_redundancies(mul(1, X), N) :- !, count_redundancies(X, N1), N is N1 + 1.
count_redundancies(mul(X, 1), N) :- !, count_redundancies(X, N1), N is N1 + 1.
count_redundancies(div(X, 1), N) :- !, count_redundancies(X, N1), N is N1 + 1.
count_redundancies(div(X, Y), N) :- X == Y, !, count_redundancies(X, N1), N is N1 + 1.
count_redundancies(Term, N) :-
    compound(Term),
    !,
    Term =.. [_|Args],
    map_redundancies(Args, N).
count_redundancies(_, 0).

map_redundancies([], 0).
map_redundancies([H|T], N) :-
    count_redundancies(H, N1),
    map_redundancies(T, N2),
    N is N1 + N2.

valid_arithmetic_structure(X) :- atom(X).
valid_arithmetic_structure(X) :- integer(X).
valid_arithmetic_structure(add(X, Y)) :- valid_arithmetic_structure(X), valid_arithmetic_structure(Y).
valid_arithmetic_structure(sub(X, Y)) :- valid_arithmetic_structure(X), valid_arithmetic_structure(Y).
valid_arithmetic_structure(mul(X, Y)) :- valid_arithmetic_structure(X), valid_arithmetic_structure(Y).
valid_arithmetic_structure(div(X, Y)) :- valid_arithmetic_structure(X), valid_arithmetic_structure(Y).

% Use clp(r) to ensure evaluating to a real number is physically possible
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
