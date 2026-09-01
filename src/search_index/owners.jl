const MAX_OWNER_SEARCH_ITEMS = 8

function owner_search_entries(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
)
    entries = [
        owner_search_entry(scope, parsed) for parsed in parsed_files
        if parsed.report.is_valid
    ]
    append!(entries, moshi_extension_search_entries(scope))
    entries
end

function owner_search_entry(scope::JuliaProjectHarnessScope, parsed::ParsedJuliaFile)
    role = owner_search_role(scope, parsed.report.path)
    tags = owner_search_tags(role, parsed)
    search_index_entry(
        parsed,
        1,
        0,
        "owner",
        owner_search_path(scope, parsed.report.path);
        detail=owner_search_detail(scope, parsed, role),
        tags,
    )
end

function owner_search_detail(
    scope::JuliaProjectHarnessScope,
    parsed::ParsedJuliaFile,
    role::AbstractString,
)
    segments = ["role=$(role)"]
    append_owner_search_segment!(segments, "modules", owner_module_names(parsed))
    append_owner_search_segment!(segments, "public", owner_public_names(parsed))
    append_owner_search_segment!(segments, "imports", owner_import_roots(parsed))
    append_owner_search_segment!(segments, "includes", owner_include_targets(scope, parsed))
    append_owner_search_segment!(segments, "types", owner_type_names(parsed))
    append_owner_search_segment!(segments, "bindings", owner_binding_names(parsed))
    append_owner_search_segment!(segments, "methods", owner_method_names(parsed))
    append_owner_search_segment!(segments, "tests", owner_test_labels(parsed))
    join(segments, " ")
end

function owner_search_role(scope::JuliaProjectHarnessScope, path::AbstractString)
    !isnothing(scope.package_entry_path) && path == scope.package_entry_path && return "entry"
    is_test_path(scope, path) && return "test"
    any(extension_path -> is_path_under(path, extension_path), scope.extension_paths) && return "extension"
    any(source_path -> is_path_under(path, source_path), scope.source_paths) && return "source"
    role = package_search_role(scope, path)
    !isnothing(role) && return role
    "owner"
end

function package_search_role(scope::JuliaProjectHarnessScope, path::AbstractString)
    for package_path in scope.package_paths
        is_path_under(path, package_path) || continue
        root = normpath(scope.project_root)
        package_root = normpath(String(package_path))
        relative_root = if package_root == root
            "."
        else
            prefix = root * string(Base.Filesystem.path_separator)
            startswith(package_root, prefix) || return nothing
            slash_path(String(SubString(package_root, nextind(package_root, lastindex(prefix)))))
        end
        top_segment = first(split(relative_root, '/'))
        top_segment == "docs" && return "docs"
        top_segment == "examples" && return "example"
        if relative_root in ("benchmark", "benchmarks", "perf", "test/perf")
            return "benchmark"
        end
        return "package"
    end
    nothing
end

function owner_search_tags(role::AbstractString, parsed::ParsedJuliaFile)
    tags = ["owner", "reasoning-tree", String(role)]
    !isempty(parsed.syntax_facts.exports) && push!(tags, "public")
    !isempty(parsed.syntax_facts.functions) && push!(tags, "method")
    !isempty(parsed.syntax_facts.tests) && push!(tags, "test")
    tags
end

function append_owner_search_segment!(
    segments::Vector{String},
    label::AbstractString,
    values::Vector{String},
)
    detail = compact_owner_search_items(values)
    isempty(detail) || push!(segments, "$(label)=$(detail)")
    segments
end

owner_module_names(parsed::ParsedJuliaFile) =
    [module_fact.name for module_fact in parsed.syntax_facts.modules]

function owner_public_names(parsed::ParsedJuliaFile)
    names = String[]
    for export_fact in parsed.syntax_facts.exports
        append!(names, export_fact.names)
    end
    names
end

owner_import_roots(parsed::ParsedJuliaFile) =
    [import_fact.root for import_fact in parsed.syntax_facts.imports]

function owner_include_targets(scope::JuliaProjectHarnessScope, parsed::ParsedJuliaFile)
    [
        owner_search_path(scope, include_fact.resolved_target) for include_fact in
        parsed.syntax_facts.includes
        if include_fact.is_literal && !isnothing(include_fact.resolved_target)
    ]
end

owner_type_names(parsed::ParsedJuliaFile) =
    [type_fact.name for type_fact in parsed.syntax_facts.types]

owner_binding_names(parsed::ParsedJuliaFile) =
    [binding_fact.terminal_name for binding_fact in parsed.syntax_facts.bindings]

owner_method_names(parsed::ParsedJuliaFile) =
    [function_fact.terminal_name for function_fact in parsed.syntax_facts.functions]

function owner_test_labels(parsed::ParsedJuliaFile)
    labels = String[
        display_owner_test_label(test_fact.label) for test_fact in parsed.syntax_facts.tests
        if test_fact.kind == "testset" && !isnothing(test_fact.label)
    ]
    direct_count = count(test_fact -> test_fact.kind != "testset", parsed.syntax_facts.tests)
    direct_count == 0 ? labels : vcat(labels, ["direct=$(direct_count)"])
end

function compact_owner_search_items(values::Vector{String})
    compact_values = sort!(unique(filter(value -> !isempty(value), values)))
    isempty(compact_values) && return ""
    length(compact_values) <= MAX_OWNER_SEARCH_ITEMS && return join(compact_values, ",")
    kept = compact_values[1:MAX_OWNER_SEARCH_ITEMS]
    push!(kept, "+$(length(compact_values) - MAX_OWNER_SEARCH_ITEMS)")
    join(kept, ",")
end

function display_owner_test_label(label::AbstractString)
    "\"$(replace(String(label), "\"" => "\\\"", "\n" => " "))\""
end

function owner_search_path(scope::JuliaProjectHarnessScope, path::AbstractString)
    root = normpath(scope.project_root)
    owner = normpath(String(path))
    owner == root && return "."
    prefix = root * string(Base.Filesystem.path_separator)
    startswith(owner, prefix) ||
        throw(ArgumentError("owner search path escaped project root: $owner"))
    slash_path(String(SubString(owner, nextind(owner, lastindex(prefix)))))
end
