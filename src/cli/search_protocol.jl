"""Agent-facing Julia search command parsing and compact seed rendering."""

struct JuliaSearchCliOptions
    pipes::Vector{String}
    render_view::String
    project_root::String
    json::Bool
    workspace::Bool
    query_terms::Vector{String}
end

const JULIA_SEARCH_TEST_TOKEN_STOPWORDS = Set([
    "ext",
    "jl",
    "julia",
    "lang",
    "project",
    "src",
    "test",
    "tests",
    "unit",
])

function parse_julia_search_args(args::Vector{String})
    pipes = String[]
    render_view = "graph"
    project_root = nothing
    json = false
    workspace = false
    query_terms = String[]
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg in ("owner", "tests", "items")
            isnothing(project_root) || error("expected pipes before --workspace")
            push!(pipes, arg)
        elseif arg == "--json"
            json = true
        elseif arg == "--workspace"
            index += 1
            index <= length(args) || error("--workspace requires a workspace root")
            workspace = true
            project_root = args[index]
        elseif arg == "--view"
            index += 1
            index <= length(args) || error("--view requires a render mode")
            render_view = args[index]
        elseif arg == "--query"
            index += 1
            index <= length(args) || error("--query requires a query")
            push!(query_terms, args[index])
        elseif startswith(arg, "--")
            error("unknown search option: $(arg)")
        else
            error("search does not accept positional WORKSPACE; use --workspace <workspace-root>")
        end
        index += 1
    end
    JuliaSearchCliOptions(pipes, render_view, something(project_root, pwd()), json, workspace, query_terms)
end

function julia_harness_agent_guide(project_root::AbstractString)
    root = abspath(String(project_root))
    """
    [julia-harness-guide] project=$(root)
    |cmd asp julia guide --workspace .
    |cmd asp julia agent doctor --workspace . --json
    |cmd asp julia search workspace --workspace . --view seeds
    |cmd asp julia search prime --workspace . --view seeds
    |cmd asp julia search pipe <query> --workspace . --view seeds
    |cmd asp julia search owner <owner-path> items [--query <symbol-or-prefix>] --workspace . --view seeds
    |cmd asp julia search owner <owner-path> items --query <symbol-or-prefix> --workspace <workspace-root> --view seeds
    |cmd asp julia search policy <rule-id-or-alias> owner tests --workspace . --view seeds
    |cmd asp julia evidence graph --json .
    |cmd asp julia evidence analyze --json .
    |cmd asp julia search lexical <query> owner tests --workspace . --view seeds
    |cmd asp julia search deps <dependency[@version][::api]> owner tests --workspace . --view seeds
    |cmd asp julia search env [term ...] --workspace . --view seeds
    |cmd asp julia search runtime-source [term ...] --workspace . --view seeds
    |cmd asp julia search lang [term ...] --workspace . --view seeds
    |cmd asp julia search std [term ...] --workspace . --view seeds
    |cmd asp julia search capability [term ...] --workspace . --view seeds
    |cmd asp julia search extension <extension> [term ...] --workspace . --view seeds
    |cmd asp julia search pattern <feature-or-extension> [term ...] --workspace . --view seeds
    |cmd asp julia search compare <axis> [left right] --workspace . --view seeds
    |cmd asp julia search query --from-hook direct-source-read --selector <glob-or-path> --term <term> --surface owner,tests --workspace <workspace-root> --view seeds
    |pipe <candidate-lines> | asp julia search ingest owner tests --workspace . --view seeds
    |cmd asp julia check --changed .
    |rule selector queries do not need a trailing project root; --workspace <workspace-root> is the independent workspace override
    |rule exact query is unavailable until Julia declares typed native exact projection; search returns structural locators/frontier
    |rule provider-knowledge-axes env/lang/std/pattern/runtime-source return facts or explicit frontier gaps; do not fill missing facts from memory
    |rule use the asp julia facade by default; run one command at a time; no raw Julia source reads
    """
end


include("search_protocol_render.jl")
include("search_protocol_receipt.jl")
include("search_protocol_query.jl")
