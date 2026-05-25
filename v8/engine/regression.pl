% regression.pl - Empirical Symbolic Regression using data from CSV
:- use_module(library(csv)).
:- use_module(root_axioms).

% Dynamic flag to allow Lisp to set the active dataset
:- dynamic active_dataset/1.
active_dataset('v8/engine/anomaly_data.csv'). % Default fallback

% We'll use a dynamic predicate for bindings so we can evaluate arbitrary variables
:- dynamic current_binding/2.

% Manually evaluate an AST by substituting variables dynamically
eval_with_context(Var, Val) :- atom(Var), current_binding(Var, Val), !.
eval_with_context(Num, Num) :- number(Num), !.

eval_with_context(add(A, B), R) :-
    eval_with_context(A, RA),
    eval_with_context(B, RB),
    number(RA), number(RB),
    R is RA + RB.
eval_with_context(sub(A, B), R) :-
    eval_with_context(A, RA),
    eval_with_context(B, RB),
    number(RA), number(RB),
    R is RA - RB.
eval_with_context(mul(A, B), R) :-
    eval_with_context(A, RA),
    eval_with_context(B, RB),
    number(RA), number(RB),
    R is RA * RB.
eval_with_context(div(A, B), R) :-
    eval_with_context(A, RA),
    eval_with_context(B, RB),
    number(RA), number(RB),
    RB =\= 0.0,
    R is RA / RB.

eval_with_context(sin(A), R) :-
    eval_with_context(A, RA),
    number(RA),
    R is sin(RA).
eval_with_context(cos(A), R) :-
    eval_with_context(A, RA),
    number(RA),
    R is cos(RA).
eval_with_context(sqrt(A), R) :-
    eval_with_context(A, RA),
    number(RA), RA >= 0,
    R is sqrt(RA).


% Bind a list of variables to a list of values
bind_vars([], []).
bind_vars([Var|Vars], [Val|Vals]) :-
    assertz(current_binding(Var, Val)),
    bind_vars(Vars, Vals).

clear_bindings :-
    retractall(current_binding(_, _)).

% We deduce what the columns are based on the active dataset filename
dataset_vars('v8/engine/gravity_data.csv', [m1, m2, r], targetF).
dataset_vars('v8/engine/anomaly_data.csv', [x1, x2, x3], targetY).
dataset_vars('v8/engine/regression_data.csv', [x], targetY).
dataset_vars('v8/engine/kepler_data.csv', [a], targetT2).
dataset_vars('v8/engine/relativity_data.csv', [v, c], targetGamma).

% General rule for unknown datasets (just use v1..vn)
dataset_vars(File, Vars, targetVal) :-
    \+ (dataset_vars_known(File, _, _)),
    Vars = [v1, v2, v3], targetVal = val.

dataset_vars_known('v8/engine/gravity_data.csv', _, _).
dataset_vars_known('v8/engine/anomaly_data.csv', _, _).
dataset_vars_known('v8/engine/regression_data.csv', _, _).
dataset_vars_known('v8/engine/kepler_data.csv', _, _).
dataset_vars_known('v8/engine/relativity_data.csv', _, _).


% Calculate sum of squared errors against CSV rows
calculate_error(_, [], _, 0.0).
calculate_error(AST, [RowTerm|T], Vars, Error) :-
    RowTerm =.. [row|Vals],
    % The last value is the target, all previous are inputs
    append(InputVals, [TargetVal], Vals),
    clear_bindings,
    bind_vars(Vars, InputVals),
    (   catch(eval_with_context(AST, PredVal), _, fail)
    ->  Diff is PredVal - TargetVal,
        SqErr is Diff * Diff,
        calculate_error(AST, T, Vars, RestError),
        Error is SqErr + RestError
    ;   % Evaluation failed (e.g. division by zero), return high penalty
        Error = 1000.0
    ).

% Entry point for regression domain censor
regression_censor(AST, Penalty) :-
    % First, apply Occam's Razor from root_axioms to ensure no trivial bloat
    root_axioms:count_redundancies(AST, Redundancies),
    (   Redundancies > 0
    ->  Penalty = 1000.0
    ;   % Read CSV and calculate error
        active_dataset(CsvFile),
        dataset_vars(CsvFile, Vars, _),
        length(Vars, NumVars), Arity is NumVars + 1,
        (   catch(csv_read_file(CsvFile, Rows, [functor(row), arity(Arity)]), _, fail)
        ->  calculate_error(AST, Rows, Vars, TotalError),
            (   TotalError > 1000.0
            ->  Penalty = 1000.0
            ;   % Add a small ast_size penalty if error is extremely low
                regression_ast_size(AST, Size),
                (TotalError < 0.1 -> Penalty is TotalError + (Size * 0.01) ; Penalty = TotalError)
            )
        ;   Penalty = 1000.0 % Fallback if file read fails
        )
    ).

% Simple AST node counter
regression_ast_size(AST, Size) :-
    (   atomic(AST)
    ->  Size = 1
    ;   compound(AST)
    ->  AST =.. [_|Args],
        regression_map_ast_size(Args, ArgSizes),
        sum_list(ArgSizes, Sum),
        Size is Sum + 1
    ).

regression_map_ast_size([], []).
regression_map_ast_size([H|T], [S|ST]) :-
    regression_ast_size(H, S),
    regression_map_ast_size(T, ST).
