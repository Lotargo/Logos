% regression.pl - Empirical Symbolic Regression using data from CSV
:- use_module(library(csv)).
:- use_module(root_axioms).

% Dynamic flag to allow Lisp to set the active dataset
:- dynamic active_dataset/1.
active_dataset('v9/data/anomaly_data.csv'). % Default fallback

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

:- dynamic regression_vars/1.
:- dynamic dataset_stats/3. % dataset_stats(CsvFile, TargetVariance, Lambda)

% Generate a generic variable list [v1, v2, ..., vN]
generate_var_list(0, []) :- !.
generate_var_list(N, Vars) :-
    N > 0,
    N1 is N - 1,
    generate_var_list(N1, Rest),
    atom_concat(v, N, Var),
    append(Rest, [Var], Vars).

% Get active variables dynamically (custom variables asserted by Lisp, or fallback)
get_vars(CsvFile, Arity, Vars) :-
    (   regression_vars(V), length(V, NumVars), NumVars is Arity - 1
    ->  Vars = V
    ;   NumVars is Arity - 1,
        generate_var_list(NumVars, Vars)
    ).

% Calculate target variance and scale lambda dynamically
get_dataset_lambda(CsvFile, Lambda) :-
    dataset_stats(CsvFile, _, Lambda), !.
get_dataset_lambda(CsvFile, Lambda) :-
    (   catch(csv_read_file(CsvFile, Rows, [functor(row)]), _, fail),
        Rows = [_|_]
    ->  maplist(get_row_target, Rows, Targets),
        sum_list(Targets, Sum),
        length(Targets, N),
        (   N > 0
        ->  Mean is Sum / N,
            maplist(sq_diff(Mean), Targets, SqDiffs),
            sum_list(SqDiffs, SumSqDiff),
            Var is SumSqDiff / N,
            % Scale lambda proportionally with variance
            Lambda is 0.01 * log(1.0 + sqrt(Var)),
            assertz(dataset_stats(CsvFile, Var, Lambda))
        ;   Lambda = 0.01
        )
    ;   Lambda = 0.01
    ).

get_row_target(Row, Target) :-
    Row =.. [row|Vals],
    last(Vals, Target).

sq_diff(Mean, Val, SqDiff) :-
    SqDiff is (Val - Mean) * (Val - Mean).

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
        (   catch(csv_read_file(CsvFile, Rows, [functor(row)]), _, fail)
        ->  (   Rows = [FirstRow|_]
            ->  functor(FirstRow, row, Arity),
                get_vars(CsvFile, Arity, Vars),
                calculate_error(AST, Rows, Vars, TotalError),
                (   TotalError > 1000.0
                ->  Penalty = 1000.0
                ;   regression_ast_size(AST, Size),
                    get_dataset_lambda(CsvFile, Lambda),
                    Penalty is TotalError + (Size * Lambda)
                )
            ;   Penalty = 1000.0
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
