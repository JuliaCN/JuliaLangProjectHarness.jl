"""Build a JuliaSyntax search index from explicit source roots.

Errors if any requested source root does not exist.
"""
function julia_lang_search_index(
    paths::Vector{<:AbstractString};
    config=default_julia_harness_config(),
)
    for path in paths
        ispath(path) || error("harness path does not exist: $(path)")
    end
    parsed_files = [parse_julia_file(path) for path in discover_julia_files(abspath.(String.(paths)), config)]
    julia_search_index(parsed_files)
end

"""Build a JuliaSyntax search index for a Project.toml-rooted package.

Errors if `project_root` does not name an existing package path.
"""
function julia_project_search_index(
    project_root::AbstractString;
    config=default_julia_harness_config(),
)
    ispath(project_root) || error("project path does not exist: $(project_root)")
    scope = julia_project_harness_scope(project_root, config)
    workspace_member_scopes = julia_workspace_member_scopes(scope, config)
    monitored_paths = vcat(
        scope_search_paths(scope),
        mapreduce(scope_search_paths, vcat, workspace_member_scopes; init=String[]),
    )
    parsed_files = [parse_julia_file(path) for path in discover_julia_files(monitored_paths, config)]
    julia_search_index(
        parsed_files;
        owner_scopes=vcat([scope], workspace_member_scopes),
        config,
    )
end

"""Resolve one concrete Julia owner within a project root.

An exact owner is a parser boundary. Callers must not widen a missing or
non-source selector into a project scan.
"""
function julia_exact_owner_source_path(
    owner_path::AbstractString,
    project_root::AbstractString,
)
    root = abspath(String(project_root))
    owner = String(owner_path)
    source_path = isabspath(owner) ? normpath(owner) : normpath(joinpath(root, owner))
    isfile(source_path) && endswith(lowercase(source_path), ".jl") ? source_path : nothing
end

"""Build syntax-search entries for one concrete Julia owner only."""
function julia_exact_owner_search_entries(
    owner_path::AbstractString,
    project_root::AbstractString;
    config=default_julia_harness_config(),
)
    source_path = julia_exact_owner_source_path(owner_path, project_root)
    isnothing(source_path) && return JuliaSearchIndexEntry[]
    julia_lang_search_index([source_path]; config)
end

"""Search explicit Julia source roots with optional syntax tag filters."""
function search_julia_lang(
    paths::Vector{<:AbstractString},
    query::AbstractString;
    config=default_julia_harness_config(),
    tags::Vector{<:AbstractString}=String[],
    limit::Int=25,
)
    entries = julia_lang_search_index(paths; config)
    search_julia_index(entries, query; tags, limit)
end

"""Search a Project.toml-rooted package with optional syntax tag filters."""
function search_julia_project(
    project_root::AbstractString,
    query::AbstractString;
    config=default_julia_harness_config(),
    tags::Vector{<:AbstractString}=String[],
    limit::Int=25,
)
    entries = julia_project_search_index(project_root; config)
    search_julia_index(entries, query; tags, limit)
end

"""Search prebuilt JuliaSyntax index entries with deterministic ranking.

Errors if `limit` is negative.
"""
function search_julia_index(
    entries::Vector{JuliaSearchIndexEntry},
    query::AbstractString;
    tags::Vector{<:AbstractString}=String[],
    limit::Int=25,
)
    limit >= 0 || error("search limit must be non-negative")
    limit == 0 && return JuliaSearchResult[]
    requested_tags = normalize_search_terms(tags)
    tokens = search_query_tokens(query)
    has_tag_filter = !isempty(requested_tags)
    results = JuliaSearchResult[]
    for entry in entries
        search_entry_matches_tags(entry, requested_tags) || continue
        score = search_entry_score(entry, tokens, has_tag_filter)
        score > 0 || continue
        push!(results, JuliaSearchResult(entry, score))
    end
    sort!(results; by=result -> (
        -result.score,
        something(result.entry.location.path, ""),
        result.entry.location.line,
        result.entry.location.column,
        result.entry.kind,
        result.entry.name,
    ))
    results[1:min(limit, length(results))]
end

function julia_search_index(
    parsed_files::Vector{ParsedJuliaFile};
    owner_scopes::Vector{JuliaProjectHarnessScope}=JuliaProjectHarnessScope[],
    config=default_julia_harness_config(),
)
    entries = JuliaSearchIndexEntry[]
    for owner_scope in owner_scopes
        owner_files = parsed_files_for_search_scope(owner_scope, parsed_files)
        policy_files = parsed_files_for_scope(owner_scope, parsed_files)
        append!(entries, owner_search_entries(owner_scope, owner_files))
        append!(entries, verification_search_entries(owner_scope, config, policy_files))
    end
    for parsed in parsed_files
        parsed.report.is_valid || continue
        origin_tags = search_origin_tags(owner_scopes, parsed.report.path)
        append!(entries, search_entries_with_origin_tags(parsed_search_entries(parsed), origin_tags))
    end
    sort!(entries; by=entry -> (
        something(entry.location.path, ""),
        entry.location.line,
        entry.location.column,
        entry.kind,
        entry.name,
    ))
end

function module_search_entries(parsed::ParsedJuliaFile)
    [
        search_index_entry(
            parsed,
            module_fact.line,
            module_fact.column,
            "module",
            module_fact.name;
            detail=module_fact.is_bare ? "baremodule" : "module",
            tags=module_fact.is_bare ? ["module", "baremodule"] : ["module"],
        ) for module_fact in parsed.syntax_facts.modules
    ]
end

function public_search_entries(parsed::ParsedJuliaFile)
    entries = JuliaSearchIndexEntry[]
    for public_fact in parsed.syntax_facts.exports
        for name in public_fact.names
            push!(
                entries,
                search_index_entry(
                    parsed,
                    public_fact.line,
                    public_fact.column,
                    public_fact.kind,
                    name;
                    detail="public Julia API symbol",
                    tags=["public", public_fact.kind],
                ),
            )
        end
    end
    entries
end

function import_search_entries(parsed::ParsedJuliaFile)
    entries = JuliaSearchIndexEntry[]
    for import_fact in parsed.syntax_facts.imports
        imported_names = isempty(import_fact.names) ? import_fact.root :
                         "$(import_fact.root):$(join(import_fact.names, ","))"
        push!(
            entries,
            search_index_entry(
                parsed,
                import_fact.line,
                import_fact.column,
                import_fact.kind,
                imported_names;
                detail=import_fact.expression,
                tags=["dependency", import_fact.kind, import_fact.root],
            ),
        )
    end
    entries
end

function type_search_entries(parsed::ParsedJuliaFile)
    [
        search_index_entry(
            parsed,
            type_fact.line,
            type_fact.column,
            type_fact.kind,
            type_fact.name;
            detail=display_type_search_detail(type_fact),
            tags=type_fact.is_mutable ? ["type", "mutable"] : ["type"],
        ) for type_fact in parsed.syntax_facts.types
    ]
end

function binding_search_entries(parsed::ParsedJuliaFile)
    [
        search_index_entry(
            parsed,
            binding_fact.line,
            binding_fact.column,
            binding_fact.kind,
            binding_fact.name;
            detail=display_binding_search_detail(binding_fact),
            tags=binding_fact.is_constant ? ["binding", "constant"] : ["binding"],
        ) for binding_fact in parsed.syntax_facts.bindings
    ]
end

function function_search_entries(parsed::ParsedJuliaFile)
    [
        search_index_entry(
            parsed,
            function_fact.line,
            function_fact.column,
            function_fact.kind,
            function_fact.name;
            detail=display_function_search_detail(function_fact),
            tags=function_search_tags(function_fact),
        ) for function_fact in parsed.syntax_facts.functions
    ]
end

function call_search_entries(parsed::ParsedJuliaFile)
    [
        search_index_entry(
            parsed,
            call_fact.line,
            call_fact.column,
            "call",
            call_fact.name;
            detail=display_call_search_detail(call_fact),
            tags=["call", call_fact.terminal_name],
        ) for call_fact in parsed.syntax_facts.calls
    ]
end

function docstring_search_entries(parsed::ParsedJuliaFile)
    [
        search_index_entry(
            parsed,
            docstring_fact.line,
            docstring_fact.column,
            "doc",
            docstring_fact.target_name;
            detail=display_docstring_search_detail(docstring_fact),
            tags=["doc", docstring_fact.target_kind, docstring_fact.target_name],
        ) for docstring_fact in parsed.syntax_facts.docstrings
    ]
end

function identifier_search_entries(parsed::ParsedJuliaFile)
    [
        search_index_entry(
            parsed,
            identifier_fact.line,
            identifier_fact.column,
            "identifier",
            identifier_fact.name;
            detail=display_identifier_search_detail(identifier_fact),
            tags=["identifier", identifier_fact.parent_kind],
        ) for identifier_fact in parsed.syntax_facts.identifiers
    ]
end

function include_search_entries(parsed::ParsedJuliaFile)
    [
        search_index_entry(
            parsed,
            include_fact.line,
            include_fact.column,
            "include",
            something(include_fact.target, include_fact.expression);
            detail=include_search_detail(include_fact),
            tags=include_fact.is_literal ? ["include", "literal"] : ["include", "dynamic"],
        ) for include_fact in parsed.syntax_facts.includes
    ]
end

function search_index_entry(
    parsed::ParsedJuliaFile,
    line::Int,
    column::Int,
    kind::AbstractString,
    name::AbstractString;
    detail::AbstractString="",
    tags::Vector{String}=String[],
)
    line_text = something(source_line(parsed.source, line), "")
    search_text = join(
        filter(!isempty, [String(kind), String(name), String(detail), line_text]),
        " ",
    )
    JuliaSearchIndexEntry(
        SourceLocation(parsed.report.path, line, column),
        String(kind),
        String(name),
        String(detail),
        search_text,
        copy(tags),
    )
end

function normalize_search_terms(terms::Vector{<:AbstractString})
    [normalize_search_text(term) for term in terms if !isempty(normalize_search_text(term))]
end

function normalize_search_text(text::AbstractString)
    lowercase(strip(String(text)))
end

function search_query_tokens(query::AbstractString)
    normalized_query = normalize_search_text(query)
    isempty(normalized_query) && return String[]
    tokens = split(normalized_query, r"[^a-z0-9_!.]+")
    unique([String(token) for token in tokens if !isempty(token)])
end

function search_entry_matches_tags(entry::JuliaSearchIndexEntry, requested_tags::Vector{String})
    isempty(requested_tags) && return true
    entry_tags = Set(normalize_search_terms(vcat(entry.tags, [entry.kind])))
    all(tag -> tag in entry_tags, requested_tags)
end

function search_entry_score(
    entry::JuliaSearchIndexEntry,
    tokens::Vector{String},
    has_tag_filter::Bool,
)
    isempty(tokens) && return has_tag_filter ? 1 : 0
    name = normalize_search_text(entry.name)
    detail = normalize_search_text(entry.detail)
    search_text = normalize_search_text(entry.search_text)
    tags = normalize_search_terms(vcat(entry.tags, [entry.kind]))
    score = 0
    for token in tokens
        name == token && (score += 100)
        occursin(token, name) && (score += 40)
        any(tag -> tag == token, tags) && (score += 30)
        occursin(token, detail) && (score += 20)
        occursin(token, search_text) && (score += 10)
    end
    score
end

function display_type_search_detail(type_fact::JuliaTypeSyntax)
    kind = type_fact.kind == "struct" && type_fact.is_mutable ? "mutable struct" :
           type_fact.kind
    parameter_suffix = isempty(type_fact.parameters) ? "" : "{$(join(type_fact.parameters, ","))}"
    supertype_suffix = isnothing(type_fact.supertype) ? "" : " <: $(type_fact.supertype)"
    field_suffix = isempty(type_fact.fields) ? "" : " fields=$(join(type_fact.fields, ","))"
    typed_suffix = isempty(type_fact.typed_fields) ? "" : " typed=$(join(type_fact.typed_fields, ","))"
    default_suffix = isempty(type_fact.defaulted_fields) ? "" :
                     " defaults=$(join(type_fact.defaulted_fields, ","))"
    "$(kind) $(type_fact.name)$(parameter_suffix)$(supertype_suffix)$(field_suffix)$(typed_suffix)$(default_suffix)"
end

function display_binding_search_detail(binding_fact::JuliaBindingSyntax)
    type_suffix = isnothing(binding_fact.type_annotation) ? "" :
                  "::$(binding_fact.type_annotation)"
    initializer_suffix = isnothing(binding_fact.initializer_name) ? "" :
                         " init=$(binding_fact.initializer_name)"
    "$(binding_fact.kind) $(binding_fact.name)$(type_suffix)$(initializer_suffix)"
end

function display_call_search_detail(call_fact::JuliaCallSyntax)
    keyword_suffix = isempty(call_fact.keyword_args) ? "" :
                     ";$(join(call_fact.keyword_args, ","))"
    "call $(call_fact.name)(args=$(call_fact.argument_count)$(keyword_suffix))"
end

function display_docstring_search_detail(docstring_fact::JuliaDocstringSyntax)
    "doc $(docstring_fact.target_kind) $(docstring_fact.target_name): " *
    first_docstring_line(docstring_fact.text)
end

function first_docstring_line(text::AbstractString)
    lines = split(text, '\n'; keepempty=false)
    isempty(lines) ? "" : strip(first(lines))
end

function display_identifier_search_detail(identifier_fact::JuliaIdentifierSyntax)
    "identifier $(identifier_fact.name) in $(identifier_fact.parent_kind): " *
    identifier_fact.parent_expression
end

function include_search_detail(include_fact::JuliaIncludeSyntax)
    if include_fact.is_literal
        target = something(include_fact.resolved_target, include_fact.target)
        return "literal include $(target)"
    end
    "dynamic include"
end
