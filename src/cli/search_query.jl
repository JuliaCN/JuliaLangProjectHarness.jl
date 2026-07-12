"""Hook-rerouted Julia search query parsing and compact rendering."""

struct JuliaSearchQueryCliOptions
    from_hook::String
    selector::String
    terms::Vector{String}
    pipes::Vector{String}
    render_view::String
    project_root::String
    json::Bool
    workspace::Bool
    intent::Union{Nothing,String}
end

function parse_julia_search_query_args(args::Vector{String})
    from_hook = nothing
    selector = nothing
    terms = String[]
    pipes = String[]
    render_view = "seeds"
    project_root = pwd()
    json = false
    workspace = false
    intent = nothing
    positionals = String[]
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--from-hook"
            index == length(args) && error("--from-hook requires a hook reason")
            from_hook = args[index + 1]
            index += 2
        elseif arg == "--selector"
            index == length(args) && error("--selector requires a selector")
            selector = args[index + 1]
            index += 2
        elseif arg in ("--term", "--query")
            index == length(args) && error("$(arg) requires a value")
            push!(terms, args[index + 1])
            index += 2
        elseif arg == "--surface"
            index == length(args) && error("--surface requires owner,tests style surfaces")
            append!(pipes, julia_search_query_surfaces(args[index + 1]))
            index += 2
        elseif arg == "--intent"
            index == length(args) && error("--intent requires a value")
            intent = args[index + 1]
            index += 2
        elseif arg == "--view"
            index == length(args) && error("--view requires graph, hits, both, or seeds")
            render_view = args[index + 1]
            index += 2
        elseif arg == "--json"
            json = true
            index += 1
        elseif arg == "--workspace"
            workspace = true
            index == length(args) && error("--workspace requires a workspace root")
            project_root = args[index + 1]
            index += 2
        elseif arg in ("owner", "tests", "items")
            push!(pipes, arg)
            index += 1
        elseif startswith(arg, "--")
            error("unknown search query option: $(arg)")
        else
            push!(positionals, arg)
            index += 1
        end
    end
    isempty(positionals) ||
        error("search query does not accept positional WORKSPACE; use --workspace <workspace-root>")
    normalized_terms = julia_query_terms(terms)
    isempty(pipes) && append!(pipes, ["owner", "tests"])
    options = JuliaSearchQueryCliOptions(
        something(from_hook, ""),
        something(selector, ""),
        normalized_terms,
        unique_julia_search_query_values(pipes),
        render_view,
        project_root,
        json,
        workspace,
        intent,
    )
    validate_julia_search_query_options(options)
end

function validate_julia_search_query_options(options::JuliaSearchQueryCliOptions)
    options.from_hook == "direct-source-read" ||
        error("unsupported search query hook route: $(options.from_hook)")
    isempty(options.selector) && error("search query --from-hook requires --selector")
    isempty(options.terms) && error("search query requires at least one --term")
    options
end

function julia_search_query_surfaces(value::AbstractString)
    surfaces = String[]
    for surface in split(String(value), ",")
        normalized = strip(surface)
        isempty(normalized) && continue
        pipe = normalized == "owners" ? "owner" :
               normalized == "test" ? "tests" :
               normalized
        pipe in ("owner", "tests", "items") || error("unknown search query surface: $(normalized)")
        push!(surfaces, pipe)
    end
    isempty(surfaces) && error("--surface requires at least one surface")
    surfaces
end

function unique_julia_search_query_values(values::Vector{String})
    seen = Set{String}()
    unique_values = String[]
    for value in values
        value in seen && continue
        push!(seen, value)
        push!(unique_values, value)
    end
    unique_values
end

function julia_search_query_text(terms::Vector{String})
    join(terms, ",")
end

function julia_search_query_filter_results(
    results::Vector{JuliaSearchResult},
    pipes::Vector{String},
)
    include_owner = "owner" in pipes || "items" in pipes
    include_tests = "tests" in pipes
    [
        result for result in results
        if is_julia_test_entry(result.entry) ? include_tests : include_owner
    ]
end

function render_julia_hook_query_search(
    selector::AbstractString,
    terms::Vector{String},
    pipes::Vector{String};
    project_root::AbstractString,
    from_hook::AbstractString="direct-source-read",
    intent::Union{Nothing,AbstractString}=nothing,
)
    query = julia_search_query_text(terms)
    results = julia_search_query_filter_results(
        julia_hook_query_search_results(selector, query, project_root),
        pipes,
    )
    owners = search_results_to_owner_paths(results, project_root)
    tests = search_results_to_test_paths(results, project_root)
    pipe_text = isempty(pipes) ? "-" : join(pipes, ",")
    lines = String[
        "[search-query] hook=$(from_hook) selector=\"$(compact_cli_value(selector))\" q=\"$(compact_cli_value(query))\" owner=$(length(owners)) tests=$(length(tests)) hit=$(length(results)) pipes=$(pipe_text)",
        "|flow hook-query->owner|tests pipe=text:owner,tests selector=\"$(compact_cli_value(selector))\"",
    ]
    isnothing(intent) || push!(lines, "|intent $(compact_cli_value(intent))")
    push!(
        lines,
        "|query $(query) status=$(isempty(results) ? "miss" : "hit") hit=$(length(results)) selector=\"$(compact_cli_value(selector))\"",
    )
    for owner in owners
        push!(lines, "|seed owner:$(owner)")
    end
    !isempty(tests) && push!(lines, "|seed tests:$(join(tests, ","))")
    push!(
        lines,
        "|synthesis algorithm=julia-hook-query-index scope=query selectedOwners=$(length(owners)) testFrontier=$(search_seed_frontier(tests)) windowSet=$(search_window_set(owners, tests))",
    )
    isempty(results) && push!(lines, "|note kind=not-found message=$(query)")
    join(lines, "\n") * "\n"
end

function julia_hook_query_search_results(
    selector::AbstractString,
    query::AbstractString,
    project_root::AbstractString,
)
    owner_path, _ = julia_query_selector_range(selector)
    source_path = isabspath(owner_path) ? owner_path : joinpath(project_root, owner_path)
    if isfile(source_path)
        return search_julia_lang([source_path], query; limit=16)
    end
    search_julia_project(project_root, query; limit=16)
end
