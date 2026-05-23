% daemon.pl - Persistent Prolog process for v7 worker threads
% Reads queries from stdin, evaluates them, prints 'true' or 'false' to stdout.

:- consult('rules.pl').

daemon :-
    read_line_to_string(user_input, Line),
    (   Line == end_of_file
    ->  halt
    ;   Line == "quit"
    ->  halt
    ;   (term_string(Query, Line) -> true ; Query = fail),
        (   catch(Query, Error, (print_message(error, Error), write(user_error, 'Error executing query\n'), fail))
        ->  write('true\n')
        ;   write('false\n')
        ),
        flush_output(user_output),
        daemon
    ).

:- initialization(daemon).
