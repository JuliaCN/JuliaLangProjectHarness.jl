function render_julia_search_packet_json(
    view::AbstractString;
    project_root::AbstractString,
    render_mode::AbstractString="seeds",
    query::Union{Nothing,AbstractString}=nothing,
    query_set::Vector{String}=String[],
    owner_path::Union{Nothing,AbstractString}=nothing,
    stdin_text::AbstractString="",
    selector::Union{Nothing,AbstractString}=nothing,
    terms::Vector{String}=String[],
    pipes::Vector{String}=String[],
    from_hook::Union{Nothing,AbstractString}=nothing,
    intent::Union{Nothing,AbstractString}=nothing,
)
    packet = if view == "workspace"
        julia_workspace_search_packet(project_root; render_mode)
    elseif view == "prime"
        julia_prime_search_packet(project_root; render_mode)
    elseif view == "owner"
        isnothing(owner_path) && error("search owner JSON requires an owner path")
        julia_owner_search_packet(owner_path, project_root; render_mode)
    elseif view == "lexical"
        isnothing(query) && error("search lexical JSON requires a query")
        packet = julia_lexical_search_packet(query, project_root; render_mode)
        if !isempty(query_set)
            packet["querySet"] = [
                Dict{String,Any}("value" => term, "kind" => "text", "selector" => "fuzzy")
                for term in query_set
            ]
        end
        packet
    elseif view == "deps"
        isnothing(query) && error("search deps JSON requires a dependency query")
        julia_dependency_search_packet(query, project_root; render_mode)
    elseif view in ["env", "runtime-source", "lang", "std", "capability", "extension", "pattern", "compare"]
        julia_knowledge_search_packet(view, isnothing(query) ? String[] : String.(split(String(query))), project_root; render_mode)
    elseif view == "ingest"
        julia_ingest_search_packet(stdin_text, project_root; render_mode)
    elseif view == "policy"
        isnothing(query) && error("search policy JSON requires a query")
        julia_policy_search_packet(query, project_root; render_mode)
    elseif view == "query"
        isnothing(selector) && error("search query JSON requires a selector")
        isempty(terms) && error("search query JSON requires terms")
        julia_search_query_packet(
            selector,
            terms,
            pipes,
            project_root;
            render_mode,
            from_hook=something(from_hook, "direct-source-read"),
            intent,
        )
    else
        error("unknown search JSON view: $(view)")
    end
    JSON3.write(packet)
end

function semantic_agent_protocol_binary()
    get(ENV, "SEMANTIC_AGENT_PROTOCOL_BIN", "asp")
end

function render_julia_fast_search_packet_json(view::AbstractString; kwargs...)
    packet = julia_fast_search_packet(view; kwargs...)
    isnothing(packet) ? nothing : JSON3.write(packet)
end

function julia_fast_search_packet(
    view::AbstractString;
    project_root::AbstractString,
    render_mode::AbstractString="seeds",
    query::Union{Nothing,AbstractString}=nothing,
    query_set::Vector{String}=String[],
    owner_path::Union{Nothing,AbstractString}=nothing,
    kwargs...,
)
    render_mode == "seeds" || return nothing
    if view == "workspace"
        return julia_fast_workspace_search_packet(project_root; render_mode)
    elseif view == "prime"
        return julia_fast_prime_search_packet(project_root; render_mode)
    elseif view == "owner"
        isnothing(owner_path) && error("search owner requires an owner path")
        return julia_fast_owner_search_packet(owner_path, project_root; render_mode)
    elseif view == "lexical"
        isnothing(query) && error("search lexical requires a query")
        return julia_fast_lexical_search_packet(query, project_root; render_mode, query_set)
    elseif view == "deps"
        isnothing(query) && error("search deps requires a dependency query")
        return julia_fast_dependency_search_packet(query, project_root; render_mode)
    end
    nothing
end

function render_julia_fast_search_graph(view::AbstractString; kwargs...)
    packet = julia_fast_search_packet(view; kwargs...)
    isnothing(packet) ? nothing : render_julia_fast_packet_graph(packet)
end

function render_julia_fast_packet_graph(packet::Dict{String,Any})
    view = String(packet["view"])
    synthesis = get(packet, "searchSynthesis", Dict{String,Any}())
    owners = String.(get(synthesis, "editFrontier", String[]))
    tests = String.(get(synthesis, "testFrontier", String[]))
    if view == "workspace" || view == "prime"
        return render_julia_fast_prime_like_graph(packet, owners, tests)
    elseif view == "owner"
        return render_julia_fast_owner_graph(packet, owners, tests)
    elseif view == "deps"
        return render_julia_fast_dependency_graph(packet, owners, tests)
    elseif view == "lexical"
        return render_julia_fast_lexical_graph(packet, owners)
    end
    error("unsupported Julia fast graph view: $(view)")
end

function render_julia_fast_prime_like_graph(
    packet::Dict{String,Any},
    owners::Vector{String},
    tests::Vector{String},
)
    view = String(packet["view"])
    root = String(packet["projectRoot"])
    selected_owners = owners[1:min(length(owners), 12)]
    selected_tests = tests[1:min(length(tests), max(12 - length(selected_owners), 0))]
    owner_ids = julia_compact_ids("O", length(selected_owners))
    test_ids = julia_compact_ids("T", length(selected_tests))
    ids = vcat(owner_ids, test_ids)
    rank = join(ids, ",")
    frontier = join(julia_compact_frontier(owner_ids, "owner", test_ids, "tests"), ",")
    lines = String[
        "[search-$(view)] root=$(root) view=$(view) alg=budgeted-prime-frontier-v1 budget=handles:12",
        "|decision purpose=decision-primer answer=false code=false capabilities=pipe,lexical,fd-query,rg-query,owner-items,selector-code,treesitter-query ladder=pipe>lexical>fd-query|rg-query>owner-items>selector-code history=asp-artifacts:directReadRisk,repeatedPrime,repeatedPipe,bestPath risk=broad-direct-read,manual-window-scan,repeat-prime next=\"asp julia search pipe '<question-or-feature-term>' --workspace . --view seeds\"",
        "legend: ID=kind:role(value)!next; entries profile(selectors=>returns); frontier ID.next",
        "aliases: graph:{G=search,O=owner,T=test}",
    ]
    julia_push_compact_node_line!(lines, owner_ids, "owner", "path", selected_owners, "owner")
    julia_push_compact_node_line!(lines, test_ids, "test", "path", selected_tests, "tests")
    edge_parts = vcat(["$(id):selects" for id in owner_ids], ["$(id):covers" for id in test_ids])
    push!(lines, "G>{" * join(edge_parts, ",") * "}")
    push!(lines, "rank=$(rank) frontier=$(frontier)")
    push!(lines, "entries=owner-tests(O=>covering-tests+test-entrypoints+fixtures)")
    push!(lines, "omit=items,blocks,code,full-test-list")
    push!(lines, "avoid=raw-read,full-json,broad-lexical")
    join(lines, "\n") * "\n"
end

function render_julia_fast_owner_graph(
    packet::Dict{String,Any},
    owners::Vector{String},
    tests::Vector{String},
)
    query = String(get(packet, "query", ""))
    selected_owners = owners[1:min(length(owners), 1)]
    selected_tests = tests[1:min(length(tests), 11)]
    owner_ids = julia_compact_ids("O", length(selected_owners))
    test_ids = julia_compact_ids("T", length(selected_tests))
    lines = String[
        "[search-owner] q=$(query) view=owner alg=julia-owner-index",
        "legend: ID=kind:role(value)!next; edge SRC>{DST:rel}; frontier ID.next",
        "aliases: graph:{G=search,O=owner,T=test}",
    ]
    julia_push_compact_node_line!(lines, owner_ids, "owner", "path", selected_owners, "owner")
    julia_push_compact_node_line!(lines, test_ids, "test", "path", selected_tests, "tests")
    edge_parts = vcat(["$(id):selects" for id in owner_ids], ["$(id):covers" for id in test_ids])
    ids = vcat(owner_ids, test_ids)
    rank = join(ids, ",")
    frontier = join(julia_compact_frontier(owner_ids, "owner", test_ids, "tests"), ",")
    push!(lines, "G>{" * join(edge_parts, ",") * "}")
    push!(lines, "rank=$(rank) frontier=$(frontier)")
    push!(lines, "entries=owner-tests(O=>covering-tests+test-entrypoints+fixtures)")
    join(lines, "\n") * "\n"
end

function render_julia_fast_dependency_graph(
    packet::Dict{String,Any},
    owners::Vector{String},
    tests::Vector{String},
)
    query = String(get(packet, "query", ""))
    selected_owners = owners[1:min(length(owners), 1)]
    selected_tests = tests[1:min(length(tests), 10)]
    owner_ids = julia_compact_ids("O", length(selected_owners))
    test_ids = julia_compact_ids("T", length(selected_tests))
    ids = vcat(["D"], owner_ids, test_ids)
    rank = join(ids, ",")
    frontier = join(vcat(["D.dependency"], julia_compact_frontier(owner_ids, "owner", test_ids, "tests")), ",")
    lines = String[
        "[search-dependency] q=$(query) querySet=1 view=deps alg=julia-dependency-search-index",
        "legend: ID=kind:role(value)!next; edge SRC>{DST:rel}; frontier ID.next",
        "aliases: graph:{G=search,D=dependency,O=owner,T=test}",
        "D=dependency:pkg($(query))!dependency",
    ]
    julia_push_compact_node_line!(lines, owner_ids, "owner", "path", selected_owners, "owner")
    julia_push_compact_node_line!(lines, test_ids, "test", "path", selected_tests, "tests")
    edge_parts = vcat(["D:uses"], ["$(id):selects" for id in owner_ids], ["$(id):covers" for id in test_ids])
    push!(lines, "G>{" * join(edge_parts, ",") * "}")
    push!(lines, "rank=$(rank) frontier=$(frontier)")
    join(lines, "\n") * "\n"
end

function render_julia_fast_lexical_graph(packet::Dict{String,Any}, owners::Vector{String})
    query = String(get(packet, "query", ""))
    query_set = get(packet, "querySet", Any[])
    selected = owners[1:min(length(owners), 11)]
    owner_ids = julia_compact_ids("O", length(selected))
    ids = vcat(["Q"], owner_ids)
    rank = join(ids, ",")
    frontier = join(vcat(["Q.lexical"], ["$(id).owner" for id in owner_ids]), ",")
    header = "[search-lexical] q=$(query)"
    if length(query_set) > 1
        header *= " querySet=$(length(query_set))"
    end
    lines = String[
        "$(header) view=lexical alg=julia-fast-lexical-frontier-v1",
        "legend: ID=kind:role(value)!next; edge SRC>{DST:rel}; frontier ID.next",
        "aliases: graph:{G=search,Q=query,O=owner}",
        "Q=query:term($(query))!lexical",
    ]
    julia_push_compact_node_line!(lines, owner_ids, "owner", "path", selected, "owner")
    edge_parts = vcat(["Q:matches"], ["$(id):selects" for id in owner_ids])
    push!(lines, "G>{" * join(edge_parts, ",") * "}")
    push!(lines, "rank=$(rank) frontier=$(frontier)")
    push!(lines, "entries=owner-query(O,Q=>items+tests+dependency-usage),owner-tests(O=>covering-tests+test-entrypoints+fixtures)")
    join(lines, "\n") * "\n"
end

function julia_compact_ids(prefix::AbstractString, count::Int)
    [index == 1 ? String(prefix) : "$(prefix)$(index)" for index in 1:count]
end

function julia_compact_node_lines(
    ids::Vector{String},
    kind::AbstractString,
    role::AbstractString,
    values::Vector{String},
    next::AbstractString,
)
    ["$(id)=$(kind):$(role)($(value))!$(next)" for (id, value) in zip(ids, values)]
end

function julia_push_compact_node_line!(
    lines::Vector{String},
    ids::Vector{String},
    kind::AbstractString,
    role::AbstractString,
    values::Vector{String},
    next::AbstractString,
)
    node_lines = julia_compact_node_lines(ids, kind, role, values, next)
    isempty(node_lines) || push!(lines, join(node_lines, ";"))
    lines
end

function julia_compact_frontier(
    owner_ids::Vector{String},
    owner_role::AbstractString,
    test_ids::Vector{String},
    test_role::AbstractString,
)
    vcat(["$(id).$(owner_role)" for id in owner_ids], ["$(id).$(test_role)" for id in test_ids])
end

"""Render a Julia search packet through the shared ASP graph renderer.

Safety contract: the external command is fixed to `asp graph render`, the stdin
payload is provider-owned JSON, and CLI search smoke tests verify the graph
rendering path.
"""
function render_julia_search_graph(view::AbstractString; kwargs...)
    fast_graph = render_julia_fast_search_graph(view; kwargs...)
    !isnothing(fast_graph) && return fast_graph
    packet_json = render_julia_search_packet_json(view; kwargs...)
    command = `$(semantic_agent_protocol_binary()) graph render --packet - --view seeds`
    try
        read(pipeline(IOBuffer(String(packet_json)), command), String)
    catch error
        error(
            "failed to render Julia search through shared asp graph renderer: " *
            sprint(showerror, error),
        )
    end
end
