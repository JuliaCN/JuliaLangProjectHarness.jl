function run_julia_harness_query_cli(args::Vector{String}; out::IO=stdout)
    from_hook = nothing
    selector = nothing
    terms = String[]
    surfaces = String[]
    render_view = "hits"
    code_only = false
    json = false
    names_only = false
    match_limit = 25
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
        elseif arg == "--term"
            index == length(args) && error("--term requires a value")
            push!(terms, args[index + 1])
            index += 2
        elseif arg == "--query"
            index == length(args) && error("--query requires a value")
            push!(terms, args[index + 1])
            index += 2
        elseif arg == "--surface"
            index == length(args) && error("--surface requires owner,tests style surfaces")
            append!(surfaces, normalize_julia_query_surfaces(args[index + 1]))
            index += 2
        elseif arg == "--view"
            index == length(args) && error("--view requires graph, hits, both, seeds, or read-packet")
            render_view = args[index + 1]
            index += 2
        elseif arg == "--code"
            code_only = true
            index += 1
        elseif arg == "--json"
            json = true
            index += 1
        elseif arg == "--names-only"
            names_only = true
            index += 1
        elseif arg == "--limit"
            index == length(args) && error("--limit requires an integer")
            match_limit = Base.parse(Int, args[index + 1])
            index += 2
        elseif startswith(arg, "-")
            error("unknown query option: $(arg)")
        else
            push!(positionals, arg)
            index += 1
        end
    end
    if !isnothing(from_hook)
        return run_julia_harness_hook_query_cli(
            from_hook,
            selector,
            terms,
            surfaces,
            render_view,
            code_only,
            json,
            positionals;
            out,
        )
    end
    run_julia_harness_owner_items_query_cli(
        positionals,
        terms,
        render_view,
        code_only,
        json,
        names_only,
        match_limit;
        out,
    )
end

function run_julia_harness_hook_query_cli(
    from_hook,
    selector,
    terms::Vector{String},
    surfaces::Vector{String},
    render_view::String,
    code_only::Bool,
    json::Bool,
    positionals::Vector{String};
    out::IO,
)
    from_hook == "direct-source-read" || error("unsupported query hook route: $(from_hook)")
    isnothing(selector) && error("--from-hook requires --selector")
    length(positionals) <= 1 || error("query direct-source-read expects at most one PROJECT_ROOT")
    project_root = isempty(positionals) ? pwd() : first(positionals)
    if json
        render_view == "read-packet" || error("query direct-source-read --json requires --view read-packet")
        code_only || error("query direct-source-read read-packet requires --code")
        isempty(terms) || error("query direct-source-read read-packet does not support --term")
        print(out, render_julia_query_read_packet_selector(selector, project_root))
        return 0
    end
    if !isempty(terms)
        isempty(surfaces) && append!(surfaces, ["owner", "tests"])
        return run_julia_harness_search_cli(
            vcat(
                ["query", "--from-hook", from_hook, "--selector", selector],
                map(term -> ["--term", term], terms)...,
                surfaces,
                ["--view", render_view, project_root],
            );
            out,
        )
    end
    code_only || error("query direct-source-read requires --term or --code")
    print(out, render_julia_query_code_selector(selector, project_root))
    return 0
end

function run_julia_harness_owner_items_query_cli(
    positionals::Vector{String},
    terms::Vector{String},
    render_view::String,
    code_only::Bool,
    json::Bool,
    names_only::Bool,
    match_limit::Int;
    out::IO,
)
    isempty(positionals) && error("query/owner-items requires an owner path")
    length(positionals) <= 2 || error("query/owner-items expects OWNER_PATH and optional PROJECT_ROOT")
    owner_path = first(positionals)
    project_root = length(positionals) == 2 ? positionals[2] : pwd()
    render_view == "names" && (names_only = true)
    render_view == "code" && (code_only = true)
    if json
        print(
            out,
            render_julia_query_owner_items_json(
                owner_path,
                terms;
                project_root,
                names_only,
                code=code_only,
                match_limit,
            ),
        )
        print(out, "\n")
    else
        print(
            out,
            render_julia_query_owner_items(
                owner_path,
                terms;
                project_root,
                names_only,
                code=code_only,
                match_limit,
            ),
        )
    end
    return 0
end

function normalize_julia_query_surfaces(value::String)::Vector{String}
    pipes = String[]
    for surface in split(value, ",")
        normalized = strip(surface)
        isempty(normalized) && continue
        pipe = normalized == "owners" ? "owner" : normalized
        pipe in ("owner", "tests", "items") || error("unknown query surface: $(normalized)")
        push!(pipes, pipe)
    end
    isempty(pipes) && error("--surface requires at least one surface")
    return pipes
end

function julia_query_owner_selector(selector::String)::String
    path = replace(selector, r"^owner:" => "")
    return replace(path, r":[0-9]+([:-][0-9]+)?$" => "")
end
