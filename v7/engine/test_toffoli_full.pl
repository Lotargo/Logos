:- consult('rules.pl').

test :-
    format('=== Testing Known Toffoli Decomposition ===~n~n'),

    % Standard Toffoli with T-count=7 (Nielsen & Chuang)
    % Toffoli(q1,q2,q3) = H q3 · T† q3 · CNOT q2,q3 · T q3 · CNOT q1,q3 · T† q3 · CNOT q2,q3 · T q3 · T† q2 · CNOT q1,q2 · T q2 · T q1 · H q3
    AST = seq(
        seq(seq(seq(seq(seq(seq(seq(seq(seq(seq(seq(
            h(q3),
            tdg(q3)),
            cnot(q2,q3)),
            t(q3)),
            cnot(q1,q3)),
            tdg(q3)),
            cnot(q2,q3)),
            t(q3)),
            tdg(q2)),
            cnot(q1,q2)),
            t(q2)),
            t(q1)),
        h(q3)),

    censor(target, synthesis, AST, Penalty),
    format('Known Toffoli decomposition: Penalty = ~f~n', [Penalty]),

    % Also test a fragment: just the H gates
    censor(target, synthesis, seq(seq(h(q1), h(q2)), h(q3)), P_3h),
    format('HHH (all 3 H gates): Penalty = ~f~n', [P_3h]),

    % Test another variant with fewer T gates (should be worse)
    censor(target, synthesis,
        seq(seq(seq(seq(seq(seq(seq(
            h(q3),
            cnot(q2,q3)),
            cnot(q1,q3)),
            cnot(q2,q3)),
            cnot(q1,q2)),
            t(q2)),
            t(q1)),
        h(q3)), P_partial),
    format('Partial (no T on q3): Penalty = ~f~n', [P_partial]),

    format('~n=== Done ===~n').

:- test, halt.
