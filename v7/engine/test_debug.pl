:- consult('rules.pl').

test :-
    format('Test 1: synthesis_censor directly~n', []),
    (   synthesis_censor(seq(h(q1), h(q2)), P1)
    ->  format('  OK: Penalty = ~f~n', [P1])
    ;   format('  FAIL: synthesis_censor failed~n', [])
    ),

    format('Test 2: find_qubits on h(q1)~n', []),
    find_qubits(h(q1), Q),
    format('  ~p~n', [Q]),

    format('Test 3: find_qubits on seq~n', []),
    find_qubits(seq(h(q1), h(q2)), Qs),
    format('  ~p~n', [Qs]),

    format('Test 4: valid_quantum_structure~n', []),
    (   valid_quantum_structure(seq(h(q1), h(q2)))
    ->  format('  OK~n', [])
    ;   format('  FAIL~n', [])
    ),

    format('Test 5: build_synthesis_unitary seq~n', []),
    build_synthesis_unitary(seq(h(q1), h(q2)), 3, U),
    format('  OK: ~p~n', [U]),

    format('Test 6: toffoli_target and fidelity~n', []),
    toffoli_target(T),
    build_synthesis_unitary(seq(h(q1), h(q2)), 3, U2),
    gate_fidelity(T, U2, 8, F),
    format('  Fidelity = ~f~n', [F]),

    format('Done.~n', []).

:- test, halt.
