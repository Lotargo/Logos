% thermo.pl - Constraints for Thermodynamics
:- module(thermo, [thermo_censor/1]).

is_temp(t_hot).
is_temp(t_cold).

valid_thermo(T) :- is_temp(T).
valid_thermo(carnot(Th, Tc)) :-
    is_temp(Th),
    is_temp(Tc),
    Th \= 0,
    Tc \= 0,
    Th \= Tc. % Heat must flow between different temperatures
valid_thermo(delta_s(T)) :-
    is_temp(T),
    T \= 0.

thermo_censor(AST) :- valid_thermo(AST).
