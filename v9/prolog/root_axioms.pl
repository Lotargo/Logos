:- module(root_axioms, [
    % Arithmetic & Simplification (Ockham's Razor)
    full_simplify/2, count_redundancies/2, expr/1,
    % Boolean Logic (Core Information processing)
    logic_censor/2, eval_bool/4, is_bool/1, is_logic_redundant/1,
    % Quantum Unitarity (Information Conservation)
    is_unitary_ast/1, build_unitary/2
]).

% =======================================================================
% Part 1: Arithmetic & Occam's Razor (First-Principle Simplification)
% =======================================================================

% Basic expressions
expr(X) :- integer(X).
expr(X) :- atom(X).
expr(add(A, B)) :- expr(A), expr(B).
expr(sub(A, B)) :- expr(A), expr(B).
expr(mul(A, B)) :- expr(A), expr(B).
expr(div(A, B)) :- expr(A), expr(B).
expr(sin(A)) :- expr(A).
expr(cos(A)) :- expr(A).
expr(deriv(A, V)) :- expr(A), atom(V).
expr(int(A, V)) :- expr(A), atom(V).
expr(eq(A, B)) :- expr(A), expr(B).
expr(solve(Eq, V)) :- expr(Eq), atom(V).

% Helper: Variable check
has_var(Expr, Var) :- Expr == Var, !.
has_var(Expr, Var) :- compound(Expr), Expr =.. [_|Args], member(Arg, Args), has_var(Arg, Var), !.

% Simplification rules (Property-Based Invariant Defense)
simplify(add(A, 0), B) :- A = B.
simplify(add(0, A), B) :- A = B.
simplify(sub(A, 0), B) :- A = B.
simplify(sub(A, B), 0) :- A == B.
simplify(mul(_, 0), 0).
simplify(mul(0, _), 0).
simplify(mul(A, 1), B) :- A = B.
simplify(mul(1, A), B) :- A = B.
simplify(div(A, 1), B) :- A = B.
simplify(div(0, _), 0).

% Evaluate basic numeric operations directly
simplify(add(A, B), C) :- number(A), number(B), C is A + B.
simplify(sub(A, B), C) :- number(A), number(B), C is A - B.
simplify(mul(A, B), C) :- number(A), number(B), C is A * B.
simplify(div(A, B), C) :- number(A), number(B), B \= 0, (integer(A), integer(B), A mod B =:= 0 -> C is A // B ; C is A / B).

% Substitutes Var with Replacement in Expr
substitute(Var, Replacement, Expr, Replacement) :- Expr == Var, !.
substitute(_, _, Expr, Expr) :- atomic(Expr), !.
substitute(Var, Replacement, Expr, Replaced) :-
    Expr =.. [Op|Args],
    maplist(substitute(Var, Replacement), Args, ReplacedArgs),
    Replaced =.. [Op|ReplacedArgs].

% Derivative from first principles (Limit definition)
simplify(deriv(F, Var), limit(div(sub(F_h, F), Var_h), Var_h, 0)) :-
    atom(Var),
    % Choose a fresh variable name for h (e.g. h_val) to avoid clashes
    Var_h = h_val,
    substitute(Var, add(Var, Var_h), F, F_h).

% Trigonometric expansion axioms
simplify(sin(add(X, Y)), add(mul(sin(X), cos(Y)), mul(cos(X), sin(Y)))).
simplify(cos(add(X, Y)), sub(mul(cos(X), cos(Y)), mul(sin(X), sin(Y)))).

% Algebraic grouping rules to isolate limits
simplify(sub(add(mul(sin(X), cos(H)), mul(cos(X), sin(H))), sin(X)),
         add(mul(sin(X), sub(cos(H), 1)), mul(cos(X), sin(H)))).
simplify(sub(sub(mul(cos(X), cos(H)), mul(sin(X), sin(H))), cos(X)),
         add(mul(cos(X), sub(cos(H), 1)), mul(mul(-1, sin(X)), sin(H)))).

% Distributing division over addition and multiplication
simplify(div(add(A, B), C), add(div(A, C), div(B, C))).
simplify(div(mul(A, B), C), mul(A, div(B, C))) :- \+ has_var(A, C).

% Limit evaluation and distribution rules as H -> 0
simplify(limit(add(A, B), H, Val), add(limit(A, H, Val), limit(B, H, Val))).
simplify(limit(sub(A, B), H, Val), sub(limit(A, H, Val), limit(B, H, Val))).
simplify(limit(mul(A, B), H, Val), mul(limit(A, H, Val), limit(B, H, Val))).
simplify(limit(div(A, B), H, Val), div(limit(A, H, Val), limit(B, H, Val))) :- \+ has_var(B, H).

simplify(limit(X, H, _), X) :- \+ has_var(X, H).

% Special continuous limit derivatives
simplify(limit(div(sin(H), H), H, 0), 1).
simplify(limit(div(sub(cos(H), 1), H), H, 0), 0).

% Differentiation rules (Computer Algebra System)
simplify(deriv(C, Var), 0) :- atomic(C), C \== Var.
simplify(deriv(Var, Var), 1) :- atom(Var).
simplify(deriv(add(A, B), Var), add(deriv(A, Var), deriv(B, Var))).
simplify(deriv(sub(A, B), Var), sub(deriv(A, Var), deriv(B, Var))).
simplify(deriv(mul(C, A), Var), mul(C, deriv(A, Var))) :- atomic(C), C \== Var.
simplify(deriv(mul(A, C), Var), mul(C, deriv(A, Var))) :- atomic(C), C \== Var.
simplify(deriv(mul(A, B), Var), add(mul(deriv(A, Var), B), mul(A, deriv(B, Var)))).

% Integration rules (Computer Algebra System)
simplify(int(0, _), 0).
simplify(int(C, Var), mul(C, Var)) :- atomic(C), C \== Var.
simplify(int(Var, Var), div(mul(Var, Var), 2)) :- atom(Var).
simplify(int(add(A, B), Var), add(int(A, Var), int(B, Var))).
simplify(int(sub(A, B), Var), sub(int(A, Var), int(B, Var))).
simplify(int(mul(C, A), Var), mul(C, int(A, Var))) :- atomic(C), C \== Var.
simplify(int(mul(A, C), Var), mul(C, int(A, Var))) :- atomic(C), C \== Var.

% Equation Solving (Isolating a variable)
% solve(eq(LHS, RHS), Var) -> eq(Var, Solution)
simplify(solve(eq(Var, RHS), Var), eq(Var, RHS)) :- atom(Var), \+ has_var(RHS, Var).
simplify(solve(eq(LHS, Var), Var), eq(Var, LHS)) :- atom(Var), \+ has_var(LHS, Var).
simplify(solve(eq(add(A, B), RHS), Var), solve(eq(A, sub(RHS, B)), Var)) :- has_var(A, Var), \+ has_var(B, Var).
simplify(solve(eq(add(A, B), RHS), Var), solve(eq(B, sub(RHS, A)), Var)) :- has_var(B, Var), \+ has_var(A, Var).
simplify(solve(eq(sub(A, B), RHS), Var), solve(eq(A, add(RHS, B)), Var)) :- has_var(A, Var), \+ has_var(B, Var).
simplify(solve(eq(sub(A, B), RHS), Var), solve(eq(B, sub(A, RHS)), Var)) :- has_var(B, Var), \+ has_var(A, Var).
simplify(solve(eq(mul(A, B), RHS), Var), solve(eq(A, div(RHS, B)), Var)) :- has_var(A, Var), \+ has_var(B, Var).
simplify(solve(eq(mul(A, B), RHS), Var), solve(eq(B, div(RHS, A)), Var)) :- has_var(B, Var), \+ has_var(A, Var).
simplify(solve(eq(div(A, B), RHS), Var), solve(eq(A, mul(RHS, B)), Var)) :- has_var(A, Var), \+ has_var(B, Var).

% Division rule for solve
simplify(solve(eq(div(A, B), RHS), Var), solve(eq(B, div(A, RHS)), Var)) :- has_var(B, Var), \+ has_var(A, Var).

% Recursive simplification logic
full_simplify(X, X) :- atomic(X), !.
full_simplify(Expr, Simplified) :-
    Expr =.. [Op | Args],
    maplist(full_simplify, Args, SimplifiedArgs),
    NewExpr =.. [Op | SimplifiedArgs],
    ( simplify(NewExpr, Simp1) ->
        full_simplify(Simp1, Simplified)
    ; Simplified = NewExpr ).

% AST Bloat Penalty: Calculate how many redundancies exist
count_redundancies(X, 0) :- atomic(X), !.
count_redundancies(Expr, Count) :-
    Expr =.. [_Op | Args],
    maplist(count_redundancies, Args, Counts),
    sum_list(Counts, SubCount),
    ( simplify(Expr, _) ->
        Count is SubCount + 1
    ; Count = SubCount ).

% =======================================================================
% Part 2: Boolean Logic (Strict Typed Information)
% =======================================================================

is_bool(true).
is_bool(false).
is_bool(p).
is_bool(q).
is_bool(and(A, B)) :- is_bool(A), is_bool(B).
is_bool(or(A, B)) :- is_bool(A), is_bool(B).
is_bool(xor(A, B)) :- is_bool(A), is_bool(B).
is_bool(implies(A, B)) :- is_bool(A), is_bool(B).
is_bool(not(A)) :- is_bool(A).

eval_bool(true, _, _, true) :- !.
eval_bool(false, _, _, false) :- !.
eval_bool(p, P, _, P) :- !.
eval_bool(q, _, Q, Q) :- !.
eval_bool(not(A), P, Q, Res) :- !, eval_bool(A, P, Q, ValA), negate(ValA, Res).
eval_bool(and(A, B), P, Q, Res) :- !, eval_bool(A, P, Q, ValA), eval_bool(B, P, Q, ValB), and_op(ValA, ValB, Res).
eval_bool(or(A, B), P, Q, Res) :- !, eval_bool(A, P, Q, ValA), eval_bool(B, P, Q, ValB), or_op(ValA, ValB, Res).
eval_bool(xor(A, B), P, Q, Res) :- !, eval_bool(A, P, Q, ValA), eval_bool(B, P, Q, ValB), xor_op(ValA, ValB, Res).
eval_bool(implies(A, B), P, Q, Res) :- !, eval_bool(A, P, Q, ValA), eval_bool(B, P, Q, ValB), implies_op(ValA, ValB, Res).

negate(true, false). negate(false, true).
and_op(true, true, true). and_op(true, false, false). and_op(false, true, false). and_op(false, false, false).
or_op(true, _, true). or_op(false, X, X).
xor_op(true, false, true). xor_op(false, true, true). xor_op(true, true, false). xor_op(false, false, false).
implies_op(true, X, X). implies_op(false, _, true).

is_logic_redundant(and(true, _)). is_logic_redundant(and(_, true)).
is_logic_redundant(and(false, _)). is_logic_redundant(and(_, false)).
is_logic_redundant(or(true, _)). is_logic_redundant(or(_, true)).
is_logic_redundant(or(false, _)). is_logic_redundant(or(_, false)).
is_logic_redundant(implies(true, _)). is_logic_redundant(implies(_, true)).
is_logic_redundant(implies(false, _)). is_logic_redundant(implies(_, false)).
is_logic_redundant(not(not(_))).
is_logic_redundant(xor(A, B)) :- A == B. % Property-Based Invariant Defense: A xor A = 0

is_logic_redundant(and(A, B)) :- is_logic_redundant(A) ; is_logic_redundant(B).
is_logic_redundant(or(A, B)) :- is_logic_redundant(A) ; is_logic_redundant(B).
is_logic_redundant(xor(A, B)) :- is_logic_redundant(A) ; is_logic_redundant(B).
is_logic_redundant(implies(A, B)) :- is_logic_redundant(A) ; is_logic_redundant(B).
is_logic_redundant(not(A)) :- is_logic_redundant(A).

hamming_distance(AST, TargetTT, TargetTF, TargetFT, TargetFF, Distance) :-
    eval_bool(AST, true, true, R1), eval_bool(AST, true, false, R2),
    eval_bool(AST, false, true, R3), eval_bool(AST, false, false, R4),
    (R1 == TargetTT -> D1 = 0 ; D1 = 1), (R2 == TargetTF -> D2 = 0 ; D2 = 1),
    (R3 == TargetFT -> D3 = 0 ; D3 = 1), (R4 == TargetFF -> D4 = 0 ; D4 = 1),
    Distance is D1 + D2 + D3 + D4.

logic_censor(AST, Penalty) :-
    ( \+ is_bool(AST) -> Penalty = 1000.0
    ; ( is_logic_redundant(AST) -> Penalty = 1000.0
        ; hamming_distance(AST, false, true, true, false, Dist), Penalty is Dist * 250.0 )
    ).

% =======================================================================
% Part 3: Quantum Unitarity (Information Conservation)
% =======================================================================

build_unitary(matrix(row(A, B), row(C, D)), [[A, B], [C, D]]) :-
    number(A), number(B), number(C), number(D), !.
build_unitary(seq(A, B), M) :-
    build_unitary(A, M_A), build_unitary(B, M_B),
    length(M_A, L_A), length(M_B, L_B),
    ( L_A =:= L_B -> matrix_multiply(M_B, M_A, M) ; M = [[1.0, 0.0], [0.0, 1.0]] ).
build_unitary(_, [[1.0, 0.0], [0.0, 1.0]]).

dot_product([], [], 0.0).
dot_product([H1|T1], [H2|T2], Result) :-
    dot_product(T1, T2, Rest), Result is H1 * H2 + Rest.

get_column([], _, []).
get_column([Row|Matrix], ColIndex, [Elem|ColRest]) :-
    nth0(ColIndex, Row, Elem), get_column(Matrix, ColIndex, ColRest).

matrix_multiply(M1, M2, Result) :-
    M2 = [Row1|_], length(Row1, NumCols),
    numlist(0, NumCols, ColIndicesExt), append(ColIndices, [_], ColIndicesExt),
    maplist(multiply_row(M2, ColIndices), M1, Result).

multiply_row(M2, ColIndices, Row, ResultRow) :- maplist(multiply_cell(M2, Row), ColIndices, ResultRow).
multiply_cell(M2, Row, ColIndex, Result) :- get_column(M2, ColIndex, Col), dot_product(Row, Col, Result).

transpose([[]|_], []).
transpose(Matrix, [Col|T]) :- matrix_first_col(Matrix, Col, RestMatrix), transpose(RestMatrix, T).
matrix_first_col([], [], []).
matrix_first_col([[H|T]|Rows], [H|Hs], [T|Ts]) :- matrix_first_col(Rows, Hs, Ts).

round_matrix([], []).
round_matrix([Row|T], [RRow|RT]) :- maplist(round_elem, Row, RRow), round_matrix(T, RT).
round_elem(E, RE) :- RE is round(E * 100000.0) / 100000.0.

is_identity_matrix(M) :-
    length(M, N), numlist(0, N, IndicesExt), append(Indices, [_], IndicesExt),
    maplist(check_identity_row(N), Indices, M).
check_identity_row(N, RowIndex, Row) :- length(Row, N), nth0(RowIndex, Row, 1.0), sum_list(Row, 1.0).

is_unitary_ast(AST) :-
    build_unitary(AST, U), transpose(U, UT),
    matrix_multiply(U, UT, Product), round_matrix(Product, RoundedProduct),
    is_identity_matrix(RoundedProduct).
