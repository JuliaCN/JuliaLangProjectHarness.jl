function evaluate_default_rule_packs(
    scope::Union{Nothing,JuliaProjectHarnessScope},
    parsed_files::Vector{ParsedJuliaFile},
    config::AspJuliaConfig,
    ;
    workspace_member_scopes=JuliaProjectHarnessScope[],
)
    findings = evaluate_syntax_rules(parsed_files)
    if !isnothing(scope)
        for scoped in vcat([scope], workspace_member_scopes)
            scoped_files = parsed_files_for_scope(scoped, parsed_files)
            append!(findings, evaluate_project_policy_rules(scoped, scoped_files, config))
            append!(findings, evaluate_modularity_rules(scoped, scoped_files))
            append!(findings, evaluate_agent_policy_rules(scoped, scoped_files))
        end
    end
    apply_config_to_findings(findings, config)
end

function parsed_files_for_scope(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
)
    [
        parsed for parsed in parsed_files if any(
            path -> is_path_under(parsed.report.path, path),
            scope_monitored_paths(scope),
        )
    ]
end

function evaluate_agent_policy_rules(
    scope::Union{Nothing,JuliaProjectHarnessScope},
    parsed_files::Vector{ParsedJuliaFile},
)
    isnothing(scope) && return AspJuliaFinding[]
    rules = rules_by_id()
    findings = verification_test_profile_findings(scope, parsed_files, rules)
    append!(findings, test_control_flow_shape_findings(scope, parsed_files, rules))
    append!(findings, moshi_policy_findings(scope, parsed_files, rules))
    public_names = package_public_names(parsed_files)
    function_docs_by_name = Dict{String,Vector{String}}()
    if !isempty(public_names)
        documented_names = package_documented_public_names(parsed_files)
        function_docs_by_name = package_function_docstrings_by_public_name(parsed_files)
        type_docs_by_name = package_type_docstrings_by_public_name(parsed_files)
        append!(findings, public_api_doc_findings(parsed_files, public_names, documented_names, rules))
        append!(findings, public_type_field_shape_findings(parsed_files, public_names, rules))
        append!(findings, public_type_stringly_field_findings(parsed_files, public_names, rules))
        append!(findings, public_abstract_field_type_findings(parsed_files, public_names, rules))
        append!(findings, public_mutable_type_contract_findings(
            parsed_files,
            public_names,
            type_docs_by_name,
            rules,
        ))
        append!(findings, public_mutating_method_contract_findings(
            parsed_files,
            public_names,
            function_docs_by_name,
            rules,
        ))
        append!(findings, public_mutating_method_test_findings(
            scope,
            parsed_files,
            public_names,
            function_docs_by_name,
            rules,
        ))
        append!(findings, public_return_contract_findings(
            parsed_files,
            public_names,
            function_docs_by_name,
            rules,
        ))
        append!(findings, public_return_contract_test_findings(
            scope,
            parsed_files,
            public_names,
            function_docs_by_name,
            rules,
        ))
        append!(findings, public_failure_contract_findings(
            parsed_files,
            public_names,
            function_docs_by_name,
            rules,
        ))
        append!(findings, public_failure_test_findings(
            scope,
            parsed_files,
            public_names,
            function_docs_by_name,
            rules,
        ))
        append!(findings, public_unsafe_evidence_test_findings(
            scope,
            parsed_files,
            public_names,
            rules,
        ))
        append!(findings, public_api_owner_conflict_findings(scope, parsed_files, public_names, rules))
        append!(findings, public_method_family_scattering_findings(
            scope,
            parsed_files,
            public_names,
            function_docs_by_name,
            rules,
        ))
        append!(findings, public_generic_type_coverage_findings(
            scope,
            parsed_files,
            public_names,
            rules,
        ))
        append!(findings, public_documenter_example_findings(scope, public_names, rules))
        append!(findings, moshi_domain_model_findings(scope, parsed_files, public_names, rules))
        append!(findings, moshi_domain_bridge_findings(scope, parsed_files, public_names, rules))
        append!(findings, public_method_shape_findings(
            parsed_files,
            public_names,
            function_docs_by_name,
            rules,
        ))
    end
    append!(findings, module_owner_fanout_findings(scope, parsed_files, rules))
    append!(findings, unsafe_construct_findings(scope, parsed_files, rules))
    append!(findings, external_method_extension_findings(scope, parsed_files, rules))
    append!(findings, mutable_global_state_findings(scope, parsed_files, rules))
    append!(findings, internal_traversal_shape_findings(scope, parsed_files, public_names, rules))
    findings
end

const MAX_INTERNAL_TRAVERSAL_CONTROL_FLOW_DEPTH = 4
const MAX_INTERNAL_TRAVERSAL_LOOP_NESTING_DEPTH = 2
const MIN_INTERNAL_TRAVERSAL_BRANCH_COUNT = 2
const MAX_UNDOCUMENTED_MODULE_OWNER_INCLUDES = 4

function internal_traversal_shape_findings(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
    public_names::Set{String},
    rules::Dict{String,AspJuliaRule},
)
    findings = AspJuliaFinding[]
    for parsed in parsed_files
        parsed.report.is_valid || continue
        is_test_path(scope, parsed.report.path) && continue
        for function_fact in parsed.syntax_facts.functions
            function_fact.kind == "function" || continue
            function_fact.terminal_name in public_names && continue
            is_nested_internal_traversal(function_fact) || continue
            push!(
                findings,
                finding_from_rule_typed(
                    rules[AGENT_JL_R015],
                    "Internal method `$(function_fact.terminal_name)` nests traversal shape: $(julia_algorithm_shape_summary(function_fact))",
                    SourceLocation(parsed.report.path, function_fact.line, function_fact.column),
                    source_line(parsed.source, function_fact.line),
                    "extract traversal into named iterator, predicate, or data-processing helpers",
                ),
            )
        end
    end
    findings
end

function is_nested_internal_traversal(function_fact::JuliaFunctionSyntax)
    function_fact.control_flow_depth >= MAX_INTERNAL_TRAVERSAL_CONTROL_FLOW_DEPTH &&
        function_fact.loop_nesting_depth >= MAX_INTERNAL_TRAVERSAL_LOOP_NESTING_DEPTH &&
        function_fact.branch_count >= MIN_INTERNAL_TRAVERSAL_BRANCH_COUNT
end

function julia_algorithm_shape_summary(function_fact::JuliaFunctionSyntax)
    "branches=$(function_fact.branch_count), loops=$(function_fact.loop_count), loop_depth=$(function_fact.loop_nesting_depth)"
end

function module_owner_fanout_findings(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
    rules::Dict{String,AspJuliaRule},
)
    findings = AspJuliaFinding[]
    for parsed in parsed_files
        parsed.report.is_valid || continue
        isempty(parsed.syntax_facts.modules) && continue
        literal_local_includes = [
            include for include in parsed.syntax_facts.includes if is_local_owner_include(scope, include)
        ]
        length(literal_local_includes) >= MAX_UNDOCUMENTED_MODULE_OWNER_INCLUDES || continue
        has_module_intent_doc(parsed) && continue
        module_fact = first(parsed.syntax_facts.modules)
        owner_targets = [
            display_public_owner_path(scope, include.resolved_target) for include in
            literal_local_includes
        ]
        push!(
            findings,
            finding_from_rule_typed(
                rules[AGENT_JL_R006],
                "Module owner `$(module_fact.name)` includes $(length(literal_local_includes)) local owners without a Julia docstring: $(join(owner_targets, ", ")).",
                SourceLocation(parsed.report.path, module_fact.line, module_fact.column),
                source_line(parsed.source, module_fact.line),
                "add a module docstring that explains the include owner boundary",
            ),
        )
    end
    findings
end

function is_local_owner_include(scope::JuliaProjectHarnessScope, include::JuliaIncludeSyntax)
    include.is_literal || return false
    isnothing(include.resolved_target) && return false
    any(root -> is_path_under(include.resolved_target, root), scope.source_paths)
end

function has_module_intent_doc(parsed::ParsedJuliaFile)
    module_names = Set(module_fact.name for module_fact in parsed.syntax_facts.modules)
    any(
        docstring_fact -> docstring_fact.target_kind == "module" &&
                          docstring_fact.target_name in module_names,
        parsed.syntax_facts.docstrings,
    )
end

function public_api_owner_conflict_findings(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
    public_names::Set{String},
    rules::Dict{String,AspJuliaRule},
)
    records = public_api_definition_records(parsed_files, public_names)
    findings = AspJuliaFinding[]
    for (name, definitions) in sort(collect(records); by=first)
        owner_paths = sort(unique(definition.path for definition in definitions))
        syntax_families = sort(unique(definition.kind for definition in definitions))
        syntax_families == ["function"] && continue
        length(owner_paths) > 1 || length(syntax_families) > 1 || continue
        documented_same_owner_constructor_family(definitions) && continue
        first_definition = first(sort(definitions; by=definition -> (
            definition.path,
            definition.line,
            definition.column,
        )))
        owner_summary = join(display_public_owner_path.(Ref(scope), owner_paths), ", ")
        family_summary = join(syntax_families, ", ")
        shape_hint = length(owner_paths) == 1 && "struct" in syntax_families && "function" in syntax_families ?
                     " For same-file `struct` plus outer constructor families, document the constructor with a dispatch or constructor extension pattern." :
                     " Document the extension pattern on the owning public method or move the family behind one owner file."
        push!(
            findings,
            finding_from_rule_typed(
                rules[AGENT_JL_R005],
                "Exported/public API `$(name)` spans owners: $(owner_summary); syntax families: $(family_summary).$(shape_hint)",
                SourceLocation(
                    first_definition.path,
                    first_definition.line,
                    first_definition.column,
                ),
                first_definition.source_line,
                "move the public API family behind one owner file or document the exact dispatch/constructor extension pattern",
            ),
        )
    end
    findings
end

const PublicApiDefinitionRecord = NamedTuple{
    (:kind, :path, :line, :column, :source_line),
    Tuple{String,String,Int,Int,Union{Nothing,SubString{String}}},
}

function documented_same_owner_constructor_family(
    definitions::Vector{PublicApiDefinitionRecord},
)
    owner_paths = unique(definition.path for definition in definitions)
    length(owner_paths) == 1 || return false
    syntax_families = Set(definition.kind for definition in definitions)
    ("struct" in syntax_families && "function" in syntax_families) || return false
    any(definition -> definition.kind == "function", definitions) || return false
    any(definition -> definition.kind == "struct", definitions) || return false
    # The docstring detector already records constructor docs as function docs.
    # At this stage only the syntax records are available, so accept same-owner
    # constructor families and rely on R001/R026/R027 to enforce constructor
    # documentation and tests where needed.
    true
end

function public_api_definition_records(
    parsed_files::Vector{ParsedJuliaFile},
    public_names::Set{String},
)
    records = Dict{String,Vector{PublicApiDefinitionRecord}}()
    for parsed in parsed_files
        parsed.report.is_valid || continue
        for type_fact in parsed.syntax_facts.types
            name = terminal_public_name(type_fact.name)
            name in public_names || continue
            push_public_api_definition!(
                records,
                name,
                type_fact.kind,
                parsed,
                type_fact.line,
                type_fact.column,
            )
        end
        for binding_fact in parsed.syntax_facts.bindings
            name = binding_fact.terminal_name
            name in public_names || continue
            push_public_api_definition!(
                records,
                name,
                binding_fact.kind,
                parsed,
                binding_fact.line,
                binding_fact.column,
            )
        end
        for function_fact in parsed.syntax_facts.functions
            name = function_fact.terminal_name
            name in public_names || continue
            push_public_api_definition!(
                records,
                name,
                function_fact.kind,
                parsed,
                function_fact.line,
                function_fact.column,
            )
        end
    end
    records
end

function push_public_api_definition!(
    records::Dict{String,Vector{PublicApiDefinitionRecord}},
    name::AbstractString,
    kind::AbstractString,
    parsed::ParsedJuliaFile,
    line::Int,
    column::Int,
)
    definitions = get!(records, String(name), PublicApiDefinitionRecord[])
    push!(
        definitions,
        (
            kind=String(kind),
            path=parsed.report.path,
            line=line,
            column=column,
            source_line=source_line(parsed.source, line),
        ),
    )
end

function display_public_owner_path(scope::JuliaProjectHarnessScope, path::AbstractString)
    normalized_path = normalized_absolute_path(path)
    normalized_root = normalized_absolute_path(scope.project_root)
    if path_has_root_prefix(normalized_path, normalized_root)
        normalized_path == normalized_root && return "."
        separator = string(Base.Filesystem.path_separator)
        root_prefix = endswith(normalized_root, separator) ?
                      normalized_root :
                      normalized_root * separator
        return replace(String(chopprefix(normalized_path, root_prefix)), '\\' => '/')
    end
    replace(String(path), '\\' => '/')
end

terminal_public_name(name::AbstractString) = last(split(String(name), "."))
