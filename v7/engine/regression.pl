% regression.pl - Empirical Symbolic Regression using data from CSV
:- use_module(library(csv)).

% Manually evaluate an AST by substituting 'x' with a specific X_val
eval_with_context(x, X_val, X_val) :- !.
eval_with_context(Num, _, Num) :- number(Num), !.
eval_with_context(Atom, _, Atom) :- atom(Atom), Atom \= x, !.

eval_with_context(add(A, B), X_val, R) :-
    eval_with_context(A, X_val, RA),
    eval_with_context(B, X_val, RB),
    number(RA), number(RB),
    R is RA + RB.
eval_with_context(sub(A, B), X_val, R) :-
    eval_with_context(A, X_val, RA),
    eval_with_context(B, X_val, RB),
    number(RA), number(RB),
    R is RA - RB.
eval_with_context(mul(A, B), X_val, R) :-
    eval_with_context(A, X_val, RA),
    eval_with_context(B, X_val, RB),
    number(RA), number(RB),
    R is RA * RB.
eval_with_context(div(A, B), X_val, R) :-
    eval_with_context(A, X_val, RA),
    eval_with_context(B, X_val, RB),
    number(RA), number(RB),
    RB =\= 0.0,
    R is RA / RB.

% Calculate sum of squared errors against CSV rows
calculate_error(_, [], 0.0).
calculate_error(AST, [row(X, TargetY)|T], Error) :-
    (   catch(eval_with_context(AST, X, PredY), _, fail)
    ->  Diff is PredY - TargetY,
        SqErr is Diff * Diff,
        calculate_error(AST, T, RestError),
        Error is SqErr + RestError
    ;   % Evaluation failed (e.g. division by zero), return high penalty
        Error = 1000.0
    ).

% Entry point for regression domain censor
regression_censor(AST, Penalty) :-
    (   catch(csv_read_file('v7/engine/regression_data.csv', Rows, [functor(row), arity(2)]), _, fail)
    ->  calculate_error(AST, Rows, TotalError),
        (   TotalError > 1000.0
        ->  Penalty = 1000.0
        ;   Penalty = TotalError
        )
    ;   Penalty = 1000.0 % Fallback if file read fails
    ).
