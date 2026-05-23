% holography.pl - Constraints for Holographic Principle (AdS/CFT)
:- module(holography, [holography_censor/1]).

is_area(area).

valid_holo(A) :- is_area(A).
valid_holo(entropy(A)) :-
    is_area(A).
valid_holo(info_bound(A)) :-
    is_area(A).

holography_censor(AST) :- valid_holo(AST).
