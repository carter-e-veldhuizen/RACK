% Copyright (c) 2020-2022, Galois, Inc.
%
% All Rights Reserved
%
% This material is based upon work supported by the Defense Advanced Research
% Projects Agency (DARPA) under Contract No. FA8750-20-C-0203.
%
% Any opinions, findings and conclusions or recommendations expressed in this
% material are those of the author(s) and do not necessarily reflect the views
% of the Defense Advanced Research Projects Agency (DARPA).

:- ensure_loaded('../paths').

:- use_module(library(semweb/rdf11)).
:- use_module(rack(model)).

core_ontology_size(Size) :-
    findall(Class,
            (rdf(Class, rdf:type, owl:'Class'),
             rack_ontology_node(Class, _, _)),
            Classes),
    length(Classes, Size).

overlay_ontology_size(Size) :-
    findall(Class,
            (rdf(Class, rdf:type, owl:'Class'),
             \+ rack_ontology_node(Class, _, _),
             \+ rdf_bnode(Class)),
            Classes),
    length(Classes, Size).

num_instances(Count) :-
    findall(I, rack_data_instance(I), IS),
    length(IS, Count).

check_missing_notes(Class) :-
    rdf(Class, rdf:type, owl:'Class'),
    has_interesting_prefix(Class),
    \+ rdf(Class, rdfs:comment, _),
    \+ rdf_bnode(Class),
    print_message(warning, class_missing_note(Class)).

check_not_prov_s(Class) :-
    rdf(Class, rdf:type, owl:'Class'),
    has_interesting_prefix(Class),
    rack_ref('PROV-S#THING', Thing),
    \+ rdf_reachable(Class, rdfs:subClassOf, Thing),
    \+ rdf_bnode(Class),
    print_message(warning, not_prov_s_thing_class(Class)).

check_instance_types(I) :-
    % Get an instance
    rack_data_instance(I),
    % Exclude namespaces we aren't interested in
    has_interesting_prefix(I),
    findall(IT, rdf(I, rdf:type, IT), ITs),
    length(ITs, N),
    N > 1,
    print_message(error, multiple_types_for_instance(I, ITs)).

check_instance_property_violations(Property) :-
    % Get an instance
    rack_data_instance(I),
    % Exclude namespaces we aren't interested in
    has_interesting_prefix(I),
    % Find a required property defined on that instance type (or parent type)
    rdf(I, rdf:type, T),
    (check_cardinality_exact(Property, I, T);
     check_cardinality_min(Property, I, T);
     check_cardinality_max(Property, I, T);
     check_maybe_prop(Property, I, T);
     check_target_type(Property, I, T);
     check_values_from(Property, I, T);
     check_invalid_value(Property, I, T)).

check_cardinality_exact(Property, I, T) :-
    property_target(T, Property, _PUsage, _Target, cardinality(N)),
    has_interesting_prefix(Property),
    % How many actual values for that property on this instance
    findall(V, rdf(I, Property, V), VS),
    length(VS, VSLen),
    VSLen \= N,
    print_message(error, cardinality_violation(I, Property, N, VSLen)).

check_cardinality_min(Property, I, T) :-
    property_target(T, Property, _PUsage, _Target, min_cardinality(N)),
    has_interesting_prefix(Property),
    % How many actual values for that property on this instance
    findall(V, rdf(I, Property, V), VS),
    length(VS, VSLen),
    VSLen < N,
    print_message(error, min_cardinality_violation(I, Property, N, VSLen)).

check_cardinality_max(Property, I, T) :-
    property_target(T, Property, _PUsage, _Target, max_cardinality(N)),
    has_interesting_prefix(Property),
    % How many actual values for that property on this instance
    findall(V, rdf(I, Property, V), VS),
    length(VS, VSLen),
    VSLen > N,
    print_message(error, max_cardinality_violation(I, Property, N, VSLen)).

check_maybe_prop(Property, I, T) :-
    property_target(T, Property, _PUsage, _Target, maybe),
    has_interesting_prefix(Property),
    % How many actual values for that property on this instance
    findall(V, rdf(I, Property, V), VS),
    (length(VS, 0), !, fail; % fail: do not report during check
     length(VS, 1), !, fail; % fail: do not report during check
     length(VS, VSLen),
     print_message(error, maybe_restriction(I, Property, VSLen))).

check_target_type(Property, I, T) :-
    property_target(T, Property, _PUsage, Target, _Restr),
    has_interesting_prefix(Property),
    rdf(I, Property, Val),
    \+ rdf_is_literal(Val),  % TODO check these as well?
    rdf(Val, rdf:type, DefTy),
    DefTy \= Target,
    \+ rdf_reachable(DefTy, rdfs:subClassOf, Target),
    print_message(error, property_value_wrong_type(I, Property, DefTy, Val, Target)).

check_values_from(Property, I, T) :-
    property_target(T, Property, _PUsage, _Target, value_from(Cls)),
    has_interesting_prefix(Property),
    rdf(I, Property, Val),
    \+ rdf_is_literal(Val),  % TODO check these as well?
    rdf(Val, rdf:type, DefTy),
    DefTy \= Cls,
    % Cls might be a direct type or a oneOf restriction to a list of types
    ( rdf_bnode(Cls), rdf(Cls, owl:oneOf, ClsLst), !,
      rdf_list(ClsLst, CList),
      ( member(CL, CList),
        rdf_reachable(DefTy, rdfs:subClassOf, CL), !  % matches, stop processing
      ; print_message(error,
                      property_value_wrong_type_in(I, Property, DefTy, Val, CList))
      )
    ; \+ rdf_reachable(DefTy, rdfs:subClassOf, Cls),
      print_message(error, property_value_wrong_type(I, Property, DefTy, Val, Cls))
    ).

check_invalid_value(Property, I, T) :-
    property_target(T, Property, _PUsage, _Target, _Restr),
    has_interesting_prefix(Property),
    rdf(I, Property, V),
    \+ rdf_is_literal(V),  % literals checked elsewhere
    \+ rdf(V, rdf:type, _),
    rdf(Property, rdfs:range, PTy),
    rdf(PTy, owl:equivalentClass, PTyEquiv),
    rdf(PTyEquiv, owl:oneOf, Enums), !,
    rdf_list(Enums,L),
    print_message(error, invalid_value_in_enum(I, Property, V, L)).

check_invalid_value(Property, I, T) :-
    property_target(T, Property, _PUsage, _Target, _Restr),
    has_interesting_prefix(Property),
    rdf(I, Property, V),
    rdf_is_literal(V),  % non-literals handled elsewhere
    rdf(Property, rdfs:range, R),
    rdf(R, owl:equivalentClass, REquiv),
    rdf(REquiv, owl:withRestrictions, RL),
    rdf(REquiv, owl:onDatatype, RT),
    rdf_list(RL, L),
    member(E,L),
    rdf(E, xsd:minInclusive, MinV),
    rdf(E, xsd:maxInclusive, MaxV),
    actual_val(MinV, RT, MinVal),
    actual_val(MaxV, RT, MaxVal),
    actual_val(V, RT, Val),
    (rdf_compare(<,Val,MinVal) ; rdf_compare(>,Val,MaxVal)),
    print_message(error, value_outside_range(I, Property, RT, Val, MinVal, MaxVal)).

% True for any SrcClass that has no Prop relationship to any target
% instance.  Returns the SrcInst that this occurs for as well as
% generating a warning.
check_has_no_rel(SrcClass, Prop, SrcInst) :-
    rack_data_instance(SrcClass, SrcInst),
    none_of(SrcInst, rack_instance_relationship(SrcClass, Prop)),
    rack_instance_ident(SrcInst, SrcName),
    print_message(warning, missing_any_tgt(SrcClass, SrcInst, SrcName, Prop)).

% True for any SrcClass that has no Prop relationship to an instance
% of the specific target class.  Returns the SrcInst that this occurs
% for as well as generating a warning.
check_has_no_rel(SrcClass, Prop, TgtClass, SrcInst) :-
    rack_data_instance(SrcClass, SrcInst),
    none_of(SrcInst, rack_instance_relationship(SrcClass, Prop, TgtClass)),
    rack_instance_ident(SrcInst, SrcName),
    print_message(warning, missing_tgt(SrcClass, SrcInst, SrcName, Prop, TgtClass)),
    % -- if the above fails, it's probably useful to see if there are
    % *any* targets of Src--[Rel]-->
    check_also_has_no_rel(SrcClass, Prop).

check_also_has_no_rel(SrcClass, SrcInst, Rel) :-
    check_has_no_rel(SrcClass, Rel, SrcInst), !.
check_also_has_no_rel(_, _).


actual_val((V^^VT),VT,(V^^VT)).  % normal
actual_val(V,VT,Val) :-
    rdf_equal(V, VS^^(xsd:string)),
    % OWL1 and older SADL doesn't specify the type for the
    % maxInclusive/minInclusive values, so they are interpreted as
    % strings.  Attempt to convert them to the target type here.  In
    % general, the OWL specification specifies using a "lexical value"
    % which is then converted at use sites to the "actual value" of
    % the desired type.
    \+ rdf_equal(xsd:string, VT),
    atom_string(VA,VS),
    % Note: converted based on representation, not VT because there is
    % no way to direct the conversion.
    atom_number(VA,VN),
    Val = VN^^VT.

has_interesting_prefix(I) :-
    member(Pfx, [ 'http://sadl.org/',
                  'http://com.ge.research/',
                  'http://demo/',
                  'http://research.ge.com/',
                  'http://semtk.research.ge.com/'
                ]),
    atom_concat(Pfx, _Local, I), !, fail.
has_interesting_prefix(_).

warn_if_nonzero(What, Count) :-
    Count > 0, !,
    print_message(warning, num_classes(What, Count)).
warn_if_nonzero(_, _).

warn_all_nonzero([]).
warn_all_nonzero([(C,N)|CNS]) :- warn_if_nonzero(C,N), warn_all_nonzero(CNS).

sum_all_nonzero([], 0).
sum_all_nonzero([(_,N)|CNS], Sum) :-
    sum_all_nonzero(CNS, SubSum),
    Sum is N + SubSum.


prolog:message(class_missing_note(Class)) -->
    [ 'No Note/Description for class ~w'-[Class] ].
prolog:message(not_prov_s_thing_class(Class)) -->
    [ 'Not a subclass of PROV-S#THING: ~w'-[Class] ].
prolog:message(num_classes(What, Count)) -->
    [ 'There are ~:d RACK definitions ~w.'-[Count, What] ].
prolog:message(cardinality_violation(Instance, Property, Specified, Actual)) -->
    { prefix_shorten(Instance, SI),
      prefix_shorten(Property, SP)
    },
    [ '~w . ~w has ~d values but an allowed cardinality of ~d~n'-[
          SI, SP, Actual, Specified] ].
prolog:message(min_cardinality_violation(Instance, Property, Specified, Actual)) -->
    { prefix_shorten(Instance, SI),
      prefix_shorten(Property, SP)
    },
    [ '~w . ~w has ~d values but a minimum allowed cardinality of ~d~n'-[
          SI, SP, Actual, Specified] ].
prolog:message(max_cardinality_violation(Instance, Property, Specified, Actual)) -->
    { prefix_shorten(Instance, SI),
      prefix_shorten(Property, SP)
    },
    [ '~w . ~w has ~d values but a maximum allowed cardinality of ~d~n'-[
          SI, SP, Actual, Specified] ].
prolog:message(maybe_restriction(Instance, Property, Actual)) -->
    { prefix_shorten(Instance, SI),
      prefix_shorten(Property, SP)
    },
    [ '~w . ~w must have only zero or one instance, but has ~d~n'-[
          SI, SP, Actual] ].
prolog:message(invalid_value_in_enum(Instance, Property, Value, Valid)) -->
    { prefix_shorten(Instance, SI),
      prefix_shorten(Property, SP),
      prefix_shorten(Value, SV),
      maplist(prefix_shorten, Valid, SL)
    },
    [ '~w . ~w value of ~w is invalid, allowed enumerations: ~w~n'-[
          SI, SP, SV, SL] ].
prolog:message(value_outside_range(Instance, Property, Ty, V, MinV, MaxV)) -->
    { prefix_shorten(Instance, SI),
      prefix_shorten(Property, SP),
      (rdf_equal(xsd:T, Ty) ; T = Ty),
      (rdf_equal(Val^^Ty, V) ; Val = V),
      (rdf_equal(Min^^Ty, MinV) ; Min = MinV),
      (rdf_equal(Max^^Ty, MaxV) ; Max = MaxV)
    },
    [ '~w . ~w value of ~w is outside ~w range [~w .. ~w]~n'-[
          SI, SP, Val, T, Min, Max ] ].
prolog:message(multiple_types_for_instance(Instance, Types)) -->
    { prefix_shorten(Instance, SI),
      maplist(prefix_shorten, Types, STys)
    },
    [ 'Instance ~w has multiple types: ~w~n'-[SI, STys] ].
prolog:message(property_value_wrong_type(Instance, Property, DefType, Val, ValType)) -->
    { prefix_shorten(Instance, SI),
      prefix_shorten(Property, SP),
      prefix_shorten(DefType, SDTy),
      prefix_shorten(ValType, SVTy),
      prefix_shorten(Val, SV)
    },
    [ 'Instance property ~w . ~w of ~w should be a ~w but is a ~w'-[
          SI, SP, SV, SVTy, SDTy ] ].
prolog:message(property_value_wrong_type_in(Instance, Property, DefType, Val, ValTypes)) -->
    { prefix_shorten(Instance, SI),
      prefix_shorten(Property, SP),
      prefix_shorten(DefType, SDTy),
      findall(SVT, (member(VT, ValTypes), prefix_shorten(VT, SVT)), SVTys),
      prefix_shorten(Val, SV)
    },
    [ 'Instance property ~w . ~w of ~w should be one of ~w but is a ~w'-[
          SI, SP, SV, SVTys, SDTy ] ].
prolog:message(missing_any_tgt(SrcClass, SrcInst, SrcIdent, Rel)) -->
    [ '~w ~w (~w) has no ~w target relationships'-[
          SrcClass, SrcInst, SrcIdent, Rel] ].
prolog:message(missing_tgt(SrcClass, SrcInst, SrcIdent, Rel, TgtClass)) -->
    [ '~w ~w (~w) missing the ~w target of type ~w'-[
          SrcClass, SrcInst, SrcIdent, Rel, TgtClass] ].
