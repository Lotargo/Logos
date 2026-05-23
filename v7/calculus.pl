% calculus.pl - Prolog Calculus invariants (Derivatives and Integrals)

calculus_censor(AST) :-
    valid_calculus_structure(AST).

% Define valid calculus structural bounds
valid_calculus_structure(X) :- atom(X).
valid_calculus_structure(X) :- integer(X).
valid_calculus_structure(add(X, Y)) :- valid_calculus_structure(X), valid_calculus_structure(Y).
valid_calculus_structure(sub(X, Y)) :- valid_calculus_structure(X), valid_calculus_structure(Y).
valid_calculus_structure(mul(X, Y)) :- valid_calculus_structure(X), valid_calculus_structure(Y).
valid_calculus_structure(div(X, Y)) :- valid_calculus_structure(X), valid_calculus_structure(Y).
valid_calculus_structure(sin(X)) :- valid_calculus_structure(X).
valid_calculus_structure(cos(X)) :- valid_calculus_structure(X).

% Deriv: deriv(Expression, Variable)
valid_calculus_structure(deriv(Expr, Var)) :-
    atom(Var), % Deriving with respect to a single variable
    valid_calculus_structure(Expr).

% Int: int(Expression, Variable)
valid_calculus_structure(int(Expr, Var)) :-
    atom(Var), % Integrating with respect to a single variable
    valid_calculus_structure(Expr).
