% daemon.pl - Persistent Prolog process for Logos worker threads
% Reads queries from stdin, evaluates them, prints 'true' or 'false' to stdout.

:- consult('rules.pl').
:- consult('nspl_invariants.pl').

daemon :-
    read_line_to_string(user_input, Line),
    (   Line == end_of_file
    ->  halt
    ;   Line == "quit"
    ->  halt
    ;   (term_string(Query, Line) -> true ; Query = fail),
        (   catch(Query, Error, (print_message(error, Error), write(user_error, 'Error executing query\n'), fail))
        ->  % Extract the Penalty value from the unified censor(Domain, AST, Penalty) query and print it
            (   Query = censor(_, _, _, Penalty)
            ->  format('~w~n', [Penalty])
            ;   Query = nspl_invariants:verify_nspl_packet(_, _, Penalty)
            ->  format('~w~n', [Penalty])
            ;   Query = nspl_invariants:find_singularity(_, Root)
            ->  format('~w~n', [Root])
            ;   write('0.0\n')
            )
        ;   write('1000.0\n')
        ),
        flush_output(user_output),
        daemon
    ).


:- initialization(daemon).
