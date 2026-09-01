using JSON
using TOML

const JULIA_EVIDENCE_GRAPH_SCHEMA_ID =
    "agent.semantic-protocols.semantic-evidence-graph"
const JULIA_EVIDENCE_GRAPH_PROTOCOL_ID =
    "agent.semantic-protocols.evidence-graph"
const JULIA_GRAPH_TURBO_REQUEST_SCHEMA_ID =
    "agent.semantic-protocols.semantic-graph-turbo-request"
const JULIA_SEMANTIC_LANGUAGE_PROTOCOL_ID =
    "agent.semantic-protocols.semantic-language"

function julia_evidence_graph_packet(project_root::AbstractString=pwd())
    root = abspath(String(project_root))
    owner_path = julia_evidence_owner_path(root)
    owner_id = evidence_node_id("julia:owner", owner_path)
    claim_id = evidence_node_id("julia:claim", owner_path)
    receipt_id = evidence_node_id("julia:receipt", "policy-api")
    action_id = evidence_node_id("julia:action", "attach-policy-api-receipt")
    gap_id = evidence_node_id("julia:gap", "$(owner_path):receipt")
    nodes = Dict{String,Any}[
        Dict{String,Any}(
            "nodeId" => owner_id,
            "kind" => "owner",
            "label" => owner_path,
            "ownerPath" => owner_path,
            "status" => "current",
            "location" => Dict{String,Any}(
                "path" => owner_path,
                "line" => 1,
                "column" => 0,
            ),
            "fields" => Dict{String,Any}(
                "languageId" => JULIA_INDEX_EXPORT_LANGUAGE_ID,
                "source" => "provider-project",
            ),
        ),
        Dict{String,Any}(
            "nodeId" => claim_id,
            "kind" => "invariant-candidate",
            "label" => "Julia provider behavior needs executable evidence",
            "ownerPath" => owner_path,
            "candidateId" => "julia.evidence.project-harness",
            "status" => "needs-injection",
            "summary" =>
                "Project-level Julia policy and semantic search behavior should be linked to verification receipts.",
            "location" => Dict{String,Any}(
                "path" => owner_path,
                "line" => 1,
                "column" => 0,
            ),
            "fields" => Dict{String,Any}(
                "sourceRuleId" => "JL-EVIDENCE-GRAPH",
                "receiptKind" => "policy-evaluation",
            ),
        ),
        Dict{String,Any}(
            "nodeId" => receipt_id,
            "kind" => "verification-receipt",
            "label" => "Julia dependency policy API receipt",
            "receiptId" => "julia.policy.api",
            "status" => "needs-injection",
            "summary" =>
                "Attach the receipt emitted by the Julia dependency policy API before treating the claim as verified.",
            "fields" => Dict{String,Any}(
                "authority" => "AspJulia-api",
                "trigger" => "Pkg.test",
            ),
        ),
        Dict{String,Any}(
            "nodeId" => action_id,
            "kind" => "review-action",
            "label" => "Attach Julia dependency policy API receipt",
            "actionId" => "julia.attach-policy-api-receipt",
            "status" => "missing",
            "summary" => "run-receipt",
            "fields" => Dict{String,Any}(
                "priority" => "p0",
                "targetId" => "julia.evidence.project-harness",
            ),
        ),
    ]
    edges = Dict{String,Any}[
        evidence_edge("julia:edge:owner-claim", "supports-claim", owner_id, claim_id),
        evidence_edge("julia:edge:claim-receipt", "requires-evidence", claim_id, receipt_id),
        evidence_edge("julia:edge:action-claim", "requires-evidence", action_id, claim_id),
    ]
    gaps = Dict{String,Any}[
        Dict{String,Any}(
            "gapId" => gap_id,
            "ownerPath" => owner_path,
            "summary" => "No attached Julia dependency policy API receipt for this evidence graph.",
            "severity" => "warning",
            "fields" => Dict{String,Any}("requiredReceiptId" => "julia.policy.api"),
        ),
    ]
    Dict{String,Any}(
        "schemaId" => JULIA_EVIDENCE_GRAPH_SCHEMA_ID,
        "schemaVersion" => "1",
        "protocolId" => JULIA_EVIDENCE_GRAPH_PROTOCOL_ID,
        "protocolVersion" => "1",
        "graphId" => "julia.evidence.graph",
        "producer" => julia_evidence_producer(),
        "project" => julia_evidence_project(root),
        "summary" => evidence_summary(nodes, edges, gaps),
        "nodes" => nodes,
        "edges" => edges,
        "gaps" => gaps,
        "fields" => Dict{String,Any}(
            "next" => "pipe JSON to `asp graph render --packet - --view seeds`",
        ),
    )
end

function render_julia_evidence_graph(packet::Dict{String,Any})
    summary = packet["summary"]
    "evidence-graph nodes=$(summary["nodes"]) edges=$(summary["edges"]) owners=$(summary["owners"]) claims=$(summary["claims"]) stale-items=$(summary["staleItems"]) gaps=$(summary["gaps"])\n"
end

"""Render the provider-owned Julia evidence graph JSON packet for agent receipts."""
function render_julia_evidence_graph_json(project_root::AbstractString=pwd())
    JSON.json(julia_evidence_graph_packet(project_root))
end

function julia_evidence_analysis_request_packet(project_root::AbstractString=pwd())
    root = abspath(String(project_root))
    graph = julia_evidence_graph_packet(root)
    analysis_graph = evidence_analysis_graph(graph)
    graph_summary = graph["summary"]
    request_summary = Dict{String,Any}(
        "graphs" => 1,
        "nodes" => graph_summary["nodes"],
        "edges" => graph_summary["edges"],
        "owners" => graph_summary["owners"],
        "claims" => graph_summary["claims"],
        "staleItems" => graph_summary["staleItems"],
        "gaps" => graph_summary["gaps"],
    )
    Dict{String,Any}(
        "schemaId" => JULIA_GRAPH_TURBO_REQUEST_SCHEMA_ID,
        "schemaVersion" => "1",
        "protocolId" => JULIA_SEMANTIC_LANGUAGE_PROTOCOL_ID,
        "protocolVersion" => "1",
        "packetKind" => "graph-turbo-request",
        "requestId" =>
            "julia.evidence.analysis.graphs-$(request_summary["graphs"]).nodes-$(request_summary["nodes"]).gaps-$(request_summary["gaps"])",
        "surface" => "evidence-analyze",
        "queryTerms" => ["julia evidence quality"],
        "profile" => "evidence-quality",
        "algorithm" => "typed-ppr-diverse",
        "seedIds" => evidence_analysis_seed_ids(analysis_graph),
        "budget" => 8,
        "producer" => julia_evidence_producer(),
        "project" => julia_evidence_analysis_project(root),
        "summary" => request_summary,
        "graphs" => [analysis_graph],
        "fields" => Dict{String,Any}(
            "next" => "pipe JSON to `asp graph render --packet - --view seeds`",
        ),
    )
end

function render_julia_evidence_analysis_request(packet::Dict{String,Any})
    summary = packet["summary"]
    "evidence-analysis profile=$(packet["profile"]) graphs=$(summary["graphs"]) nodes=$(summary["nodes"]) edges=$(summary["edges"]) owners=$(summary["owners"]) claims=$(summary["claims"]) stale-items=$(summary["staleItems"]) gaps=$(summary["gaps"]) next=\"asp graph render --packet - --view seeds\"\n"
end

"""Render the Julia evidence graph-turbo request JSON for evidence-quality ranking."""
function render_julia_evidence_analysis_request_json(project_root::AbstractString=pwd())
    JSON.json(julia_evidence_analysis_request_packet(project_root))
end

function run_julia_harness_evidence_cli(args::Vector{String}; out=stdout)
    isempty(args) && error("expected evidence <graph|analyze>")
    action = args[1]
    action in ("graph", "analyze", "analysis") ||
        error("expected evidence <graph|analyze>")
    json = false
    positionals = String[]
    for arg in args[2:end]
        if arg == "--json"
            json = true
        elseif arg in ("--help", "-h")
            print(out, "asp-julia evidence graph [--json] [PROJECT_ROOT]\n")
            print(out, "asp-julia evidence analyze [--json] [PROJECT_ROOT]\n")
            return 0
        elseif startswith(arg, "--")
            error("unknown evidence option: $(arg)")
        else
            push!(positionals, arg)
        end
    end
    length(positionals) <= 1 ||
        error("expected at most one PROJECT_ROOT argument")
    project_root = isempty(positionals) ? pwd() : only(positionals)
    if action == "graph"
        packet = julia_evidence_graph_packet(project_root)
        if json
            print(out, JSON.json(packet))
            print(out, "\n")
        else
            print(out, render_julia_evidence_graph(packet))
        end
    else
        packet = julia_evidence_analysis_request_packet(project_root)
        if json
            print(out, JSON.json(packet))
            print(out, "\n")
        else
            print(out, render_julia_evidence_analysis_request(packet))
        end
    end
    0
end

function evidence_analysis_graph(graph::Dict{String,Any})
    Dict{String,Any}(
        "graphId" => graph["graphId"],
        "summary" => graph["summary"],
        "nodes" => [evidence_analysis_node(node) for node in graph["nodes"]],
        "edges" => [evidence_analysis_edge(edge) for edge in graph["edges"]],
        "gaps" => graph["gaps"],
    )
end

function evidence_analysis_node(node::Dict{String,Any})
    location = get(node, "location", Dict{String,Any}())
    path = get(node, "ownerPath", get(location, "path", nothing))
    rendered = Dict{String,Any}(
        "id" => node["nodeId"],
        "kind" => node["kind"],
        "role" => evidence_node_role(String(node["kind"])),
        "value" => node["label"],
        "fields" => copy(get(node, "fields", Dict{String,Any}())),
    )
    if !isnothing(path)
        rendered["path"] = path
        rendered["ownerPath"] = get(node, "ownerPath", path)
    end
    line = get(location, "line", nothing)
    if !isnothing(path) && line isa Integer
        rendered["locator"] = "$(path):$(line):$(line)"
        rendered["startLine"] = line
        rendered["endLine"] = line
    end
    fields = rendered["fields"]
    for key in ("candidateId", "receiptId", "actionId", "summary", "status")
        haskey(node, key) && (fields[key] = string(node[key]))
    end
    rendered
end

function evidence_analysis_edge(edge::Dict{String,Any})
    Dict{String,Any}(
        "source" => edge["fromNodeId"],
        "target" => edge["toNodeId"],
        "relation" => edge["kind"],
        "fields" => Dict{String,Any}("edgeId" => edge["edgeId"]),
    )
end

function evidence_analysis_seed_ids(graph::Dict{String,Any})
    seeds = [node["id"] for node in graph["nodes"] if node["kind"] == "owner"]
    isempty(seeds) && !isempty(graph["nodes"]) && push!(seeds, first(graph["nodes"])["id"])
    seeds
end

function julia_evidence_producer()
    Dict{String,Any}(
        "languageId" => JULIA_INDEX_EXPORT_LANGUAGE_ID,
        "providerId" => JULIA_INDEX_EXPORT_PROVIDER_ID,
        "namespace" => JULIA_AGENT_PROVIDER_NAMESPACE,
    )
end

function julia_evidence_project(root::AbstractString)
    package_name = julia_evidence_package_name(root)
    project = Dict{String,Any}("root" => String(root), "fields" => Dict{String,Any}())
    isnothing(package_name) || (project["package"] = package_name)
    project
end

function julia_evidence_analysis_project(root::AbstractString)
    Dict{String,Any}(
        "root" => String(root),
        "package" => julia_evidence_package_name(root),
        "fields" => Dict{String,Any}(),
    )
end

function evidence_summary(
    nodes::Vector{Dict{String,Any}},
    edges::Vector{Dict{String,Any}},
    gaps::Vector{Dict{String,Any}},
)
    Dict{String,Any}(
        "nodes" => length(nodes),
        "edges" => length(edges),
        "owners" => count(node -> node["kind"] == "owner", nodes),
        "claims" => count(node -> node["kind"] == "invariant-candidate", nodes),
        "staleItems" => count(
            node -> get(node, "status", "") in ("stale", "expired"),
            nodes,
        ),
        "gaps" => length(gaps),
    )
end

function evidence_edge(
    edge_id::AbstractString,
    kind::AbstractString,
    from_node_id::AbstractString,
    to_node_id::AbstractString,
)
    Dict{String,Any}(
        "edgeId" => String(edge_id),
        "kind" => String(kind),
        "fromNodeId" => String(from_node_id),
        "toNodeId" => String(to_node_id),
    )
end

function evidence_node_role(kind::AbstractString)
    kind == "owner" && return "path"
    kind == "invariant-candidate" && return "claim"
    kind == "verification-receipt" && return "receipt"
    kind == "review-action" && return "action"
    "evidence"
end

function julia_evidence_owner_path(root::AbstractString)
    for candidate in ("Project.toml", "JuliaProject.toml")
        isfile(joinpath(root, candidate)) && return candidate
    end
    for source_root in ("src", ".")
        base = joinpath(root, source_root)
        isdir(base) || continue
        found = first_julia_source_file(root, base)
        isnothing(found) || return found
    end
    "."
end

function first_julia_source_file(root::AbstractString, directory::AbstractString)
    entries = sort!(readdir(directory; join=false))
    for entry in entries
        startswith(entry, ".") && continue
        entry_path = joinpath(directory, entry)
        if isdir(entry_path)
            entry in ("deps", "build") && continue
            nested = first_julia_source_file(root, entry_path)
            isnothing(nested) || return nested
        elseif endswith(entry, ".jl")
            return slash_path(relpath(entry_path, root))
        end
    end
    nothing
end

function julia_evidence_package_name(root::AbstractString)
    manifest = joinpath(root, "Project.toml")
    isfile(manifest) || return nothing
    try
        value = TOML.parsefile(manifest)
        name = get(value, "name", nothing)
        isnothing(name) ? nothing : string(name)
    catch
        nothing
    end
end

function evidence_node_id(prefix::AbstractString, raw::AbstractString)
    "$(String(prefix)):$(sanitize_evidence_id_part(raw))"
end

function sanitize_evidence_id_part(raw::AbstractString)
    output = IOBuffer()
    for character in String(raw)
        if isascii(character) &&
           (isletter(character) || isdigit(character) || character in ('.', '_', ':', '-'))
            print(output, lowercase(string(character)))
        else
            print(output, ".")
        end
    end
    rendered = String(take!(output))
    while occursin("..", rendered)
        rendered = replace(rendered, ".." => ".")
    end
    rendered = strip(rendered, ['.'])
    isempty(rendered) ? "root" : rendered
end
