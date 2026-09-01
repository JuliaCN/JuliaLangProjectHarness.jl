const JULIA_FLOW_LITE_CATALOG_ID = "flow-lite"
const JULIA_FLOW_LITE_FLOW_KIND = "local-source-sink"

function julia_flow_lite_project_result(
    project_root::AbstractString,
    where::Dict{String,String},
)
    root = abspath(String(project_root))
    config = project_toml_harness_config(root, default_julia_harness_config())
    files = discover_julia_files([root], config)
    scanned_functions = 0
    best_partial = nothing
    for path in files
        parsed = parse_julia_file(path)
        parsed.report.is_valid || continue
        owner_path = relpath(parsed.report.path, root)
        for function_fact in parsed.syntax_facts.functions
            function_fact.terminal_name == where["scope.fn"] ||
                function_fact.name == where["scope.fn"] ||
                continue
            scanned_functions += 1
            function_start = function_fact.line
            function_end = julia_flow_lite_fact_end_line(function_fact)
            source = julia_flow_lite_call_occurrence(
                parsed.syntax_facts.calls,
                owner_path,
                function_start,
                function_end,
                "S",
                "source",
                "call",
                where["source.call"],
            )
            sink = julia_flow_lite_call_occurrence(
                parsed.syntax_facts.calls,
                owner_path,
                function_start,
                function_end,
                "K",
                "sink",
                "constructs",
                where["sink.constructs"],
            )
            result = Dict{String,Any}(
                "confidence" =>
                    (!isnothing(source) && !isnothing(sink) ? "bounded" : "partial"),
                "ownerPath" => owner_path,
                "functionName" => function_fact.terminal_name,
                "functionStart" => function_start,
                "functionEnd" => function_end,
                "source" => source,
                "sink" => sink,
                "scannedFiles" => length(files),
                "scannedFunctions" => scanned_functions,
                "omissions" => julia_flow_lite_omissions(source, sink, where),
            )
            if !isnothing(source) && !isnothing(sink)
                return result
            end
            isnothing(best_partial) && (best_partial = result)
        end
    end
    !isnothing(best_partial) && return best_partial
    return Dict{String,Any}(
        "confidence" => "unavailable",
        "ownerPath" => ".",
        "functionName" => where["scope.fn"],
        "functionStart" => 0,
        "functionEnd" => 0,
        "source" => nothing,
        "sink" => nothing,
        "scannedFiles" => length(files),
        "scannedFunctions" => scanned_functions,
        "omissions" => [
            Dict{String,Any}(
                "kind" => "no-match",
                "message" => "no Julia function matched flow-lite scope/source/sink constraints",
                "target" => JULIA_FLOW_LITE_CATALOG_ID,
            ),
        ],
    )
end

function julia_flow_lite_call_occurrence(
    calls::Vector{JuliaCallSyntax},
    owner_path::AbstractString,
    start_line::Int,
    end_line::Int,
    id::AbstractString,
    role::AbstractString,
    kind::AbstractString,
    value::AbstractString,
)
    for call in calls
        start_line <= call.line <= end_line || continue
        call.terminal_name == value || call.name == value || continue
        return Dict{String,Any}(
            "id" => String(id),
            "kind" => String(kind),
            "role" => String(role),
            "value" => String(value),
            "path" => String(owner_path),
            "line" => call.line,
            "range" => "$(owner_path):$(call.line):$(call.line)",
            "handle" => "$(role):$(kind)($(value))@$(owner_path):$(call.line)",
            "nativeFactRef" => "julia-call:$(owner_path):$(call.line):$(call.terminal_name)",
        )
    end
    return nothing
end

function julia_flow_lite_fact_end_line(fact)::Int
    if hasproperty(fact, :expression)
        expression = getproperty(fact, :expression)
        isempty(expression) && return getproperty(fact, :line)
        return getproperty(fact, :line) + length(split(expression, '\n')) - 1
    end
    return getproperty(fact, :line)
end

function julia_flow_lite_omissions(source, sink, where::Dict{String,String})
    omissions = Any[]
    if isnothing(source)
        push!(
            omissions,
            Dict{String,Any}(
                "kind" => "missing-source",
                "message" => "source.call was not found in matched Julia function scope",
                "target" => where["source.call"],
            ),
        )
    end
    if isnothing(sink)
        push!(
            omissions,
            Dict{String,Any}(
                "kind" => "missing-sink",
                "message" => "sink.constructs was not found in matched Julia function scope",
                "target" => where["sink.constructs"],
            ),
        )
    end
    return omissions
end

function render_julia_flow_lite_frontier(
    project_root::AbstractString,
    where::Dict{String,String},
    result::Dict{String,Any},
)
    scope_fn = where["scope.fn"]
    owner_path = result["ownerPath"]
    function_start = result["functionStart"]
    function_end = result["functionEnd"]
    source = result["source"]
    sink = result["sink"]
    nodes = [
        "F=flow:local-source-sink(fn:$(scope_fn))!flow",
        "O=owner:function($(scope_fn))@$(owner_path):$(function_start):$(function_end)!code",
    ]
    !isnothing(source) && push!(
        nodes,
        "$(source["id"])=source:call($(source["value"]))@$(source["path"]):$(source["line"])!code",
    )
    !isnothing(sink) && push!(
        nodes,
        "$(sink["id"])=sink:constructs($(sink["value"]))@$(sink["path"]):$(sink["line"])!code",
    )
    edges = ["G>{F:selects}", "F>{O:scopes}"]
    !isnothing(source) && push!(edges, "O>{$(source["id"]):source}")
    !isnothing(sink) && push!(edges, "O>{$(sink["id"]):sink}")
    !isnothing(source) &&
        !isnothing(sink) &&
        push!(edges, "$(source["id"])>{$(sink["id"]):flows_to}")
    rank = join(
        filter(
            !isempty,
            ["O", isnothing(source) ? "" : source["id"], isnothing(sink) ? "" : sink["id"]],
        ),
        ",",
    )
    frontier = join(
        filter(
            !isempty,
            [
                isnothing(source) ? "" : "$(source["id"]).code",
                isnothing(sink) ? "" : "$(sink["id"]).code",
                "O.code",
            ],
        ),
        ",",
    )
    join(
        [
            "[query-flow-lite] root=$(project_root) lang=julia catalog=flow-lite flow=$(JULIA_FLOW_LITE_FLOW_KIND) scope=fn($(scope_fn)) alg=native-flow-lite status=$(result["confidence"] == "bounded" ? "hit" : "partial")",
            "legend: ID=kind:role(value)!next; edge SRC>{DST:rel}; frontier ID.next",
            "aliases=G:query,F:flow,P:path",
            "",
            nodes...,
            "",
            edges...,
            "",
            "confidence=$(result["confidence"]) sourceAuthority=native-parser executionBackend=native-parser adapterMode=native-projection owner=$(owner_path) range=$(function_start):$(function_end) scannedFiles=$(result["scannedFiles"]) scannedFunctions=$(result["scannedFunctions"])",
            "rank=$(rank)",
            "frontier=$(frontier)",
            "omit=code,full-path-ast,raw-source",
            "avoid=raw-read,inline-code",
            isempty(result["omissions"]) ?
            "note=native parser bounded source/sink captures" :
            "note=$(join([omission["kind"] for omission in result["omissions"]], ","))",
        ],
        "\n",
    )
end

function julia_flow_lite_packet(
    project_root::AbstractString,
    where::Dict{String,String},
    result::Dict{String,Any},
)
    path = Any[]
    !isnothing(result["source"]) && push!(path, result["source"])
    !isnothing(result["sink"]) && push!(path, result["sink"])
    Dict{String,Any}(
        "schemaId" => "agent.semantic-protocols.semantic-flow-lite",
        "schemaVersion" => "1",
        "protocolId" => "agent.semantic-protocols.semantic-language",
        "protocolVersion" => "1",
        "languageId" => "julia",
        "providerId" => "asp-julia",
        "projectRoot" => abspath(String(project_root)),
        "packageName" => basename(abspath(String(project_root))),
        "flowId" => "flow-lite:julia:$(where["scope.fn"]):$(where["source.call"]):$(where["sink.constructs"])",
        "flowKind" => JULIA_FLOW_LITE_FLOW_KIND,
        "scope" => "function",
        "ownerPath" => result["ownerPath"],
        "sourceAuthority" => "native-parser",
        "executionBackend" => "native-parser",
        "adapterMode" => "native-projection",
        "sourceHandle" => "call:$(where["source.call"])",
        "sinkHandle" => "constructs:$(where["sink.constructs"])",
        "path" => path,
        "guards" => Any[],
        "effects" => Any[],
        "artifacts" => Any[],
        "confidence" => result["confidence"],
        "omissions" => result["omissions"],
        "fields" => Dict{String,Any}(
            "catalog" => JULIA_FLOW_LITE_CATALOG_ID,
            "where" => where,
            "functionRange" => "$(result["functionStart"]):$(result["functionEnd"])",
            "scannedFiles" => result["scannedFiles"],
            "scannedFunctions" => result["scannedFunctions"],
            "fileHashes" => Any[],
            "rawSourceStored" => false,
        ),
    )
end
