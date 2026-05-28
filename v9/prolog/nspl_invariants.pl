:- module(nspl_invariants, [verify_nspl_packet/3]).

%% =======================================================================
%% NSPL Invariants Validation for Prolog
%% Validates the semantic core and payload of NSPL binary packets.
%% =======================================================================

%% verify_nspl_packet(DomainID, ASTList, Penalty)
%% Domain mapping:
%% 1: arithmetic
%% 2: logic
%% 3: quantum

verify_nspl_packet(DomainID, ASTList, Penalty) :-
    validate_domain(DomainID, DomainName),
    validate_ast_syntax(ASTList),
    validate_domain_semantics(DomainName, ASTList, Penalty).

verify_nspl_packet(_, _, 1000.0). %% Fallback penalty if anything fails.

%% Domain ID validation
validate_domain(1, arithmetic).
validate_domain(2, logic).
validate_domain(3, quantum).
validate_domain(4, relativity).
validate_domain(5, thermo).

%% Basic Syntax checking:
%% - Must be a list
%% - Cannot contain 'unknown' (which means deserializer failed to map bytes)
validate_ast_syntax(ASTList) :-
    is_list(ASTList),
    \+ member('unknown', ASTList),
    \+ member(unknown, ASTList).

%% Domain Semantic Validation
%% For now, we perform a lightweight check ensuring operators match the domain.

%% Arithmetic Domain
validate_domain_semantics(arithmetic, [Op | _Args], 0.0) :-
    member(Op, [add, sub, mul, div]).

%% Logic Domain
validate_domain_semantics(logic, [Op | _Args], 0.0) :-
    member(Op, [and, or, not]).

%% Quantum Domain
validate_domain_semantics(quantum, [Op | _Args], 0.0) :-
    member(Op, [h, x_gate, cnot]).

%% Fallback if domain semantics are violated
validate_domain_semantics(_, _, 1000.0).
