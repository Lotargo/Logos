% nlp_vocab.pl - Lexicon and Semantic Ontology for Symbolic NLP

% Lexicon: word(Word, PartOfSpeech, SemanticTags).
word(i, pronoun, [entity, self, living]).
word(you, pronoun, [entity, other]).
word(am, verb, [state, identity, present]).
word(are, verb, [state, identity, present]).
word(is, verb, [state, identity, present]).
word(a, det, [grammar_article]).
word(the, det, [grammar_article]).
word(machine, noun, [entity, artificial, compute]).
word(human, noun, [entity, biological, living]).
word(think, verb, [action, cognitive, dynamic]).
word(process, verb, [action, cognitive, mechanical]).
word(data, noun, [concept, information]).
word(logic, noun, [concept, math, strict]).
word(hello, greeting, [social, start]).
word(yes, boolean, [affirmative]).
word(no, boolean, [negative]).
word(fast, adj, [property, speed]).
word(smart, adj, [property, cognitive]).
