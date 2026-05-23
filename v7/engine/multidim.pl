% multidim.pl - Constraints for Multi-Dimensional Spaces & Tensor Calculus
% Dimensionality type system: 0 is scalar, N>0 is a vector of dimension N.

:- module(multidim, [multidim_censor/1]).

% Ground truth variables and constants
dim_of(s1, 0).
dim_of(s2, 0).
dim_of(0, 0).
dim_of(1, 0).
dim_of(v2_a, 2).
dim_of(v2_b, 2).
dim_of(v3_a, 3).
dim_of(v3_b, 3).
dim_of(v4_a, 4).

% Numbers are scalars
dim_of(X, 0) :- number(X).

% Addition / Subtraction: Both sides must be of the SAME dimension.
% The result is of that same dimension.
dim_of(add(A, B), Dim) :-
    dim_of(A, Dim),
    dim_of(B, Dim).

dim_of(sub(A, B), Dim) :-
    dim_of(A, Dim),
    dim_of(B, Dim).

% Dot product: Both must be vectors of the SAME dimension. Result is a scalar (0).
dim_of(dot(A, B), 0) :-
    dim_of(A, Dim),
    dim_of(B, Dim),
    Dim > 0.

% Cross product: Mathematically defined primarily for 3D space.
% Returns a 3D vector.
dim_of(cross(A, B), 3) :-
    dim_of(A, 3),
    dim_of(B, 3).

% Scale (scalar multiplication): A must be a scalar, B must be a vector.
dim_of(scale(A, B), Dim) :-
    dim_of(A, 0),
    dim_of(B, Dim),
    Dim > 0.

% Norm (length): Argument must be a vector. Result is a scalar.
dim_of(norm(A), 0) :-
    dim_of(A, Dim),
    Dim > 0.

% The censor accepts the AST if it resolves to a valid mathematical object
% (i.e., its dimensionality can be proven without contradictions).
multidim_censor(AST) :-
    dim_of(AST, _).
