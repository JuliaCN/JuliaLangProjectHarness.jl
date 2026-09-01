const EXTENSION_PATTERN_DOC_TOKENS = (
    "dispatch",
    "extension",
    "extensions",
    "fallback",
    "fallbacks",
    "method family",
    "overload",
    "overloads",
)
const SYNTAX_CONTRACT_DOC_TOKENS = ("syntax", "macro", "expansion", "generated", "contract")
const STRINGLY_DOMAIN_FIELD_NAME_PARTS = Set(["category", "mode", "status", "type"])
const STRINGLY_DOMAIN_FIELD_TYPE_NAMES = Set(["AbstractString", "String"])
const MUTATION_CONTRACT_DOC_TOKENS = (
    "invariant",
    "invariants",
    "lifecycle",
    "mutable",
    "mutate",
    "mutates",
    "mutation",
    "ownership",
    "state",
)

function public_api_doc_findings(
    parsed_files::Vector{ParsedJuliaFile},
    public_names::Set{String},
    documented_names::Set{String},
    rules::Dict{String,AspJuliaRule},
)
    findings = AspJuliaFinding[]
    reported = Set{Tuple{String,String}}()
    for parsed in parsed_files
        parsed.report.is_valid || continue
        append!(findings, public_type_doc_findings(parsed, public_names, documented_names, reported, rules))
        append!(findings, public_function_doc_findings(parsed, public_names, documented_names, reported, rules))
        append!(findings, public_binding_doc_findings(parsed, public_names, documented_names, reported, rules))
    end
    findings
end

function public_method_family_scattering_findings(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
    public_names::Set{String},
    function_docs_by_name::Dict{String,Vector{String}},
    rules::Dict{String,AspJuliaRule},
)
    records = public_api_definition_records(parsed_files, public_names)
    findings = AspJuliaFinding[]
    for (name, definitions) in sort(collect(records); by=first)
        method_definitions = PublicApiDefinitionRecord[]
        for definition in definitions
            definition.kind == "function" || continue
            push!(method_definitions, definition)
        end
        length(method_definitions) >= 2 || continue
        owner_paths = String[]
        for definition in method_definitions
            definition.path in owner_paths || push!(owner_paths, definition.path)
        end
        sort!(owner_paths)
        length(owner_paths) >= 2 || continue
        has_extension_pattern_doc(function_docs_by_name, name) && continue
        first_definition = first(sort(method_definitions; by=definition -> (
            definition.path,
            definition.line,
            definition.column,
        )))
        owner_summary = join(display_public_owner_path.(Ref(scope), owner_paths), ", ")
        push!(
            findings,
            finding_from_rule_typed(
                rules[AGENT_JL_R009],
                "Exported/public method family `$(name)` is implemented across $(length(owner_paths)) owner files without a documented dispatch pattern: $(owner_summary).",
                SourceLocation(
                    first_definition.path,
                    first_definition.line,
                    first_definition.column,
                ),
                first_definition.source_line,
                "document the Julia dispatch or extension pattern for this public method family",
            ),
        )
    end
    findings
end

function public_type_field_shape_findings(
    parsed_files::Vector{ParsedJuliaFile},
    public_names::Set{String},
    rules::Dict{String,AspJuliaRule},
)
    findings = AspJuliaFinding[]
    for parsed in parsed_files
        parsed.report.is_valid || continue
        append!(findings, public_type_field_shape_findings(parsed, public_names, rules))
    end
    findings
end

function public_type_field_shape_findings(
    parsed::ParsedJuliaFile,
    public_names::Set{String},
    rules::Dict{String,AspJuliaRule},
)
    findings = AspJuliaFinding[]
    for type_fact in parsed.syntax_facts.types
        type_fact.kind == "struct" || continue
        name = terminal_public_name(type_fact.name)
        name in public_names || continue
        untyped_fields = [
            field for field in type_fact.field_facts if isnothing(field.type_annotation)
        ]
        isempty(untyped_fields) && continue
        first_field = first(untyped_fields)
        field_names = join([field.name for field in untyped_fields], ", ")
        push!(
            findings,
            finding_from_rule_typed(
                rules[AGENT_JL_R011],
                "Exported/public struct `$(name)` has fields without type annotations: $(field_names).",
                SourceLocation(parsed.report.path, first_field.line, first_field.column),
                source_line(parsed.source, first_field.line),
                "add explicit field type annotations to the public struct",
            ),
        )
    end
    findings
end

function public_type_stringly_field_findings(
    parsed_files::Vector{ParsedJuliaFile},
    public_names::Set{String},
    rules::Dict{String,AspJuliaRule},
)
    findings = AspJuliaFinding[]
    for parsed in parsed_files
        parsed.report.is_valid || continue
        append!(findings, public_type_stringly_field_findings(parsed, public_names, rules))
    end
    findings
end

function public_type_stringly_field_findings(
    parsed::ParsedJuliaFile,
    public_names::Set{String},
    rules::Dict{String,AspJuliaRule},
)
    findings = AspJuliaFinding[]
    for type_fact in parsed.syntax_facts.types
        type_fact.kind == "struct" || continue
        name = terminal_public_name(type_fact.name)
        name in public_names || continue
        stringly_fields = [
            field for field in type_fact.field_facts if is_stringly_domain_field(field)
        ]
        isempty(stringly_fields) && continue
        first_field = first(stringly_fields)
        field_names = join([field.name for field in stringly_fields], ", ")
        push!(
            findings,
            finding_from_rule_typed(
                rules[AGENT_JL_R012],
                "Exported/public struct `$(name)` exposes stringly domain fields: $(field_names).",
                SourceLocation(parsed.report.path, first_field.line, first_field.column),
                source_line(parsed.source, first_field.line),
                "replace stringly domain fields with Symbol, enum, or named value carriers",
            ),
        )
    end
    findings
end

function is_stringly_domain_field(field::JuliaTypeFieldSyntax)
    isnothing(field.type_annotation) && return false
    is_stringly_field_type(field.type_annotation) || return false
    is_stringly_domain_field_name(field.name)
end

function is_stringly_field_type(type_annotation::AbstractString)
    tokens = split(replace(String(type_annotation), r"[^A-Za-z0-9_]+" => " "))
    any(token -> token in STRINGLY_DOMAIN_FIELD_TYPE_NAMES, tokens)
end

function is_stringly_domain_field_name(name::AbstractString)
    parts = split(lowercase(String(name)), "_")
    any(part -> part in STRINGLY_DOMAIN_FIELD_NAME_PARTS, parts)
end

function public_mutable_type_contract_findings(
    parsed_files::Vector{ParsedJuliaFile},
    public_names::Set{String},
    type_docs_by_name::Dict{String,Vector{String}},
    rules::Dict{String,AspJuliaRule},
)
    findings = AspJuliaFinding[]
    for parsed in parsed_files
        parsed.report.is_valid || continue
        append!(
            findings,
            public_mutable_type_contract_findings(
                parsed,
                public_names,
                type_docs_by_name,
                rules,
            ),
        )
    end
    findings
end

function public_mutable_type_contract_findings(
    parsed::ParsedJuliaFile,
    public_names::Set{String},
    type_docs_by_name::Dict{String,Vector{String}},
    rules::Dict{String,AspJuliaRule},
)
    findings = AspJuliaFinding[]
    for type_fact in parsed.syntax_facts.types
        type_fact.kind == "struct" || continue
        type_fact.is_mutable || continue
        name = terminal_public_name(type_fact.name)
        name in public_names || continue
        haskey(type_docs_by_name, name) || continue
        has_mutation_contract_doc(type_docs_by_name, name) && continue
        push!(
            findings,
            finding_from_rule_typed(
                rules[AGENT_JL_R013],
                "Exported/public mutable struct `$(name)` is documented without a mutation contract.",
                SourceLocation(parsed.report.path, type_fact.line, type_fact.column),
                source_line(parsed.source, type_fact.line),
                "document mutation ownership, lifecycle, or invariants for this public mutable type",
            ),
        )
    end
    findings
end

function has_mutation_contract_doc(
    docs_by_name::Dict{String,Vector{String}},
    name::AbstractString,
)
    any(get(docs_by_name, String(name), String[])) do text
        lower_text = lowercase(text)
        any(token -> occursin(token, lower_text), MUTATION_CONTRACT_DOC_TOKENS)
    end
end

function has_extension_pattern_doc(
    docs_by_name::Dict{String,Vector{String}},
    name::AbstractString,
)
    any(get(docs_by_name, String(name), String[])) do text
        lower_text = lowercase(text)
        any(token -> occursin(token, lower_text), EXTENSION_PATTERN_DOC_TOKENS)
    end
end

function public_type_doc_findings(
    parsed::ParsedJuliaFile,
    public_names::Set{String},
    documented_names::Set{String},
    reported::Set{Tuple{String,String}},
    rules::Dict{String,AspJuliaRule},
)
    findings = AspJuliaFinding[]
    for type_fact in parsed.syntax_facts.types
        name = terminal_public_name(type_fact.name)
        name in public_names || continue
        name in documented_names && continue
        key = ("type", name)
        key in reported && continue
        push!(reported, key)
        push!(findings, finding_from_rule_typed(
            rules[AGENT_JL_R001],
            "Exported/public type `$(name)` lacks a Julia docstring that states its agent-facing intent.",
            SourceLocation(parsed.report.path, type_fact.line, type_fact.column),
            source_line(parsed.source, type_fact.line),
            "add a Julia docstring before the public type definition",
        ))
    end
    findings
end

function public_function_doc_findings(
    parsed::ParsedJuliaFile,
    public_names::Set{String},
    documented_names::Set{String},
    reported::Set{Tuple{String,String}},
    rules::Dict{String,AspJuliaRule},
)
    findings = AspJuliaFinding[]
    for function_fact in parsed.syntax_facts.functions
        name = function_fact.terminal_name
        name in public_names || continue
        name in documented_names && continue
        key = ("function", name)
        key in reported && continue
        push!(reported, key)
        push!(findings, finding_from_rule_typed(
            rules[AGENT_JL_R001],
            "Exported/public function `$(name)` lacks a Julia docstring that states its agent-facing intent.",
            SourceLocation(parsed.report.path, function_fact.line, function_fact.column),
            source_line(parsed.source, function_fact.line),
            "add a Julia docstring before the public function definition",
        ))
    end
    findings
end

function public_binding_doc_findings(
    parsed::ParsedJuliaFile,
    public_names::Set{String},
    documented_names::Set{String},
    reported::Set{Tuple{String,String}},
    rules::Dict{String,AspJuliaRule},
)
    findings = AspJuliaFinding[]
    for binding_fact in parsed.syntax_facts.bindings
        name = binding_fact.terminal_name
        name in public_names || continue
        name in documented_names && continue
        key = ("binding", name)
        key in reported && continue
        push!(reported, key)
        push!(findings, finding_from_rule_typed(
            rules[AGENT_JL_R001],
            "Exported/public binding `$(name)` lacks a Julia docstring that states its agent-facing intent.",
            SourceLocation(parsed.report.path, binding_fact.line, binding_fact.column),
            source_line(parsed.source, binding_fact.line),
            "add a Julia docstring before the public binding definition",
        ))
    end
    findings
end

function package_public_names(parsed_files::Vector{ParsedJuliaFile})
    names = Set{String}()
    for parsed in parsed_files
        for export_fact in parsed.syntax_facts.exports
            union!(names, export_fact.names)
        end
    end
    names
end

function package_documented_public_names(parsed_files::Vector{ParsedJuliaFile})
    names = Set{String}()
    for parsed in parsed_files
        parsed.report.is_valid || continue
        for docstring_fact in parsed.syntax_facts.docstrings
            push!(names, terminal_public_name(docstring_fact.target_name))
        end
    end
    names
end

function package_function_docstrings_by_public_name(parsed_files::Vector{ParsedJuliaFile})
    docs = Dict{String,Vector{String}}()
    for parsed in parsed_files
        parsed.report.is_valid || continue
        for docstring_fact in parsed.syntax_facts.docstrings
            docstring_fact.target_kind == "function" || continue
            name = terminal_public_name(docstring_fact.target_name)
            push!(get!(docs, name, String[]), docstring_fact.text)
        end
    end
    docs
end

function package_type_docstrings_by_public_name(parsed_files::Vector{ParsedJuliaFile})
    docs = Dict{String,Vector{String}}()
    for parsed in parsed_files
        parsed.report.is_valid || continue
        for docstring_fact in parsed.syntax_facts.docstrings
            docstring_fact.target_kind == "struct" || continue
            name = terminal_public_name(docstring_fact.target_name)
            push!(get!(docs, name, String[]), docstring_fact.text)
        end
    end
    docs
end

function has_syntax_contract_doc(
    docs_by_name::Dict{String,Vector{String}},
    name::AbstractString,
)
    any(get(docs_by_name, String(name), String[])) do text
        lower_text = lowercase(text)
        any(token -> occursin(token, lower_text), SYNTAX_CONTRACT_DOC_TOKENS)
    end
end
