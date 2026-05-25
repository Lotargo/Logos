% nlp.pl - Symbolic Natural Language Processing using Definite Clause Grammars
:- module(nlp, [nlp_censor/3, eval_nlp_ast/2]).
:- consult('nlp_vocab.pl').

% Context-Free Grammar for basic English (Prolog DCG)
% We use AST structures like sentence(np(pronoun(i)), vp(verb(am), np(det(a), noun(machine))))

sentence(sentence(NP, VP)) --> noun_phrase(NP), verb_phrase(VP).
sentence(sentence(Greeting, S)) --> greeting(Greeting), sentence(S).

noun_phrase(np(Pronoun)) --> pronoun(Pronoun).
noun_phrase(np(Det, Noun)) --> determiner(Det), noun(Noun).
noun_phrase(np(Adj, Noun)) --> adjective(Adj), noun(Noun).
noun_phrase(np(Noun)) --> noun(Noun).

verb_phrase(vp(Verb, NP)) --> verb(Verb), noun_phrase(NP).
verb_phrase(vp(Verb)) --> verb(Verb).

pronoun(pronoun(W)) --> [W], { word(W, pronoun, _) }.
verb(verb(W)) --> [W], { word(W, verb, _) }.
noun(noun(W)) --> [W], { word(W, noun, _) }.
determiner(det(W)) --> [W], { word(W, det, _) }.
adjective(adj(W)) --> [W], { word(W, adj, _) }.
greeting(greeting(W)) --> [W], { word(W, greeting, _) }.

% Extract flat list of words from AST
extract_words(sentence(A, B), Words) :- extract_words(A, W1), extract_words(B, W2), append(W1, W2, Words).
extract_words(np(A, B), Words) :- extract_words(A, W1), extract_words(B, W2), append(W1, W2, Words).
extract_words(vp(A, B), Words) :- extract_words(A, W1), extract_words(B, W2), append(W1, W2, Words).
extract_words(np(A), Words) :- extract_words(A, Words).
extract_words(vp(A), Words) :- extract_words(A, Words).
extract_words(pronoun(W), [W]).
extract_words(verb(W), [W]).
extract_words(noun(W), [W]).
extract_words(det(W), [W]).
extract_words(adj(W), [W]).
extract_words(greeting(W), [W]).
extract_words(W, [W]) :- atom(W). % Fallback

% Check if AST is grammatically valid
is_grammatical(AST) :-
    extract_words(AST, Words),
    phrase(sentence(ParsedAST), Words),
    AST = ParsedAST. % AST must exactly match the parsed structure

% Semantic Scoring (Continuous Fitness Gradient)
% We calculate how many required semantic tags are present in the sentence.
extract_semantics([], []).
extract_semantics([Word|T], Tags) :-
    ( word(Word, _, WordTags) -> true ; WordTags = [] ),
    extract_semantics(T, RestTags),
    append(WordTags, RestTags, RawTags),
    sort(RawTags, Tags). % Unique tags

count_matches([], _, 0).
count_matches([Tag|T], SentenceTags, Count) :-
    count_matches(T, SentenceTags, RestCount),
    ( member(Tag, SentenceTags) -> Count is RestCount + 1 ; Count = RestCount ).

% Penalty calculation: Distance to target semantic meaning
nlp_censor(AST, TargetTags, Penalty) :-
    (   \+ is_grammatical(AST)
    ->  Penalty = 1000.0 % Strict Grammar Invariant: ungrammatical = dead
    ;   extract_words(AST, Words),
        extract_semantics(Words, SentenceTags),
        % Calculate Jaccard-like distance for Semantics
        length(TargetTags, TargetLen),
        count_matches(TargetTags, SentenceTags, MatchCount),
        % We also penalize if the sentence contains semantics directly contradictory to the target
        % For example, if target is "machine" (artificial), but sentence contains "living" (human)
        % For simplicity, we just use the match ratio.
        (   TargetLen > 0
        ->  SemanticScore is MatchCount / TargetLen
        ;   SemanticScore = 0.0
        ),
        % Anti-Cheat: Penalize semantic noise (tags that are not in target)
        length(SentenceTags, TotalTags),
        NoiseCount is TotalTags - MatchCount,
        NoisePenalty is NoiseCount * 50.0,

        BasePenalty is (1000.0 * (1.0 - SemanticScore)) + NoisePenalty,

        % Occam's Razor: Reward shorter, elegant sentences if semantics are fully met
        ast_size(AST, Size),
        (   SemanticScore > 0.99
        ->  Penalty is BasePenalty + (Size * 2.0)
        ;   Penalty = BasePenalty
        )
    ).

% Helper: AST node counter
ast_size(AST, Size) :-
    (   atomic(AST) -> Size = 1
    ;   compound(AST) ->
        AST =.. [_|Args],
        map_ast_size(Args, ArgSizes),
        sum_list(ArgSizes, Sum),
        Size is Sum + 1
    ).

map_ast_size([], []).
map_ast_size([H|T], [S|ST]) :-
    ast_size(H, S),
    map_ast_size(T, ST).

% Fallback helper for dynamic execution in Lisp
eval_nlp_ast(AST, Words) :- extract_words(AST, Words).
