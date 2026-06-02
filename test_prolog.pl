:- consult('v7/engine/quantum.pl').
:- initialization(main, main).
main :-
    AST = seq(h(q1), seq(h(q1), cnot(q2, q3))),
    calc_quantum_penalty(AST, CCNOT_Penalty),
    format('CCNOT Penalty: ~w~n', [CCNOT_Penalty]),
    halt.
