const JuliaNativeSearchActionWithOwner = @NamedTuple begin
    kind::String
    ownerPath::String
    scope::String
    target::String
    targetRole::String
end
const JuliaNativeSearchActionWithoutOwner = @NamedTuple begin
    kind::String
    scope::String
    target::String
    targetRole::String
end
const JuliaNativeSearchAction =
    Union{JuliaNativeSearchActionWithOwner,JuliaNativeSearchActionWithoutOwner}
const JuliaNativeSearchWindow = @NamedTuple begin
    kind::String
    target::String
end
const JuliaNativeSearchOwner = @NamedTuple begin
    fields::@NamedTuple{languageKind::String}
    nextActions::Vector{JuliaNativeSearchActionWithOwner}
    path::String
    public::Bool
    role::String
end
const JuliaNativeSearchInputDetection = @NamedTuple begin
    byteCount::Int
    lineCount::Int
    sample::String
    source::String
end
const JuliaNativeSearchSynthesis = @NamedTuple begin
    algorithm::String
    editFrontier::Vector{String}
    scope::String
    seeds::Vector{JuliaNativeSearchAction}
    selectedOwners::Int
    summary::String
    testFrontier::Vector{String}
    windowSet::Vector{JuliaNativeSearchWindow}
end
const JuliaNativeEmptySearchRow = @NamedTuple begin
end
const JuliaNativeIngestPacket = @NamedTuple begin
    binary::String
    edges::Vector{JuliaNativeEmptySearchRow}
    findings::Vector{JuliaNativeEmptySearchRow}
    header::@NamedTuple{fields::@NamedTuple{provider::String,view::String},kind::String}
    hits::Vector{JuliaNativeEmptySearchRow}
    inputDetection::JuliaNativeSearchInputDetection
    languageId::String
    method::String
    namespace::String
    nextActions::Vector{JuliaNativeSearchAction}
    nodes::Vector{JuliaNativeEmptySearchRow}
    notes::Vector{JuliaNativeEmptySearchRow}
    owners::Vector{JuliaNativeSearchOwner}
    packageName::String
    projectRoot::String
    protocolId::String
    protocolVersion::String
    providerId::String
    renderMode::String
    schemaId::String
    schemaVersion::String
    searchSynthesis::JuliaNativeSearchSynthesis
    view::String
end

function julia_native_ingest_candidate(line::String)::Union{Nothing,String}
    stripped = strip(line)
    isempty(stripped) && return nothing
    boundary = findfirst(byte -> byte == '\t' || byte == ' ', stripped)
    first_field = isnothing(boundary) ? stripped : stripped[begin:prevind(stripped, boundary)]
    colon = findfirst(==(':'), first_field)
    path = isnothing(colon) ? first_field : first_field[begin:prevind(first_field, colon)]
    isempty(path) && return nothing
    endswith(path, ".jl") || return nothing
    isabspath(path) &&
        throw(ArgumentError("native ingest requires workspace-relative candidate paths"))
    normalized = replace(normpath(path), '\\' => '/')
    (normalized == ".." || startswith(normalized, "../")) &&
        throw(ArgumentError("native ingest candidate escaped workspace"))
    return normalized
end

function julia_native_ingest_candidates(stdin_text::String)::Vector{String}
    candidates = String[]
    for line in eachsplit(stdin_text, '\n')
        candidate = julia_native_ingest_candidate(String(line))
        isnothing(candidate) || push!(candidates, candidate)
    end
    return sort!(unique!(candidates))
end

function julia_native_ingest_action(path::String)::JuliaNativeSearchAction
    if is_julia_test_path(path)
        return (
            kind="tests",
            scope="ingest",
            target=path,
            targetRole="test",
        )
    end
    return (
        kind="owner",
        ownerPath=path,
        scope="ingest",
        target=path,
        targetRole="path",
    )
end

function julia_native_ingest_packet(
    stdin_text::String,
    project_root::String,
    render_mode::String,
)::JuliaNativeIngestPacket
    root = abspath(project_root)
    candidates = julia_native_ingest_candidates(stdin_text)
    owners = String[path for path in candidates if !is_julia_test_path(path)]
    tests = String[path for path in candidates if is_julia_test_path(path)]
    actions = JuliaNativeSearchAction[julia_native_ingest_action(path) for path in candidates]
    project_path = joinpath(root, "Project.toml")
    package_name = if isfile(project_path)
        something(julia_project_document(project_path).name, basename(root))
    else
        basename(root)
    end
    owner_rows = JuliaNativeSearchOwner[
        (
            fields=(languageKind="julia-owner",),
            nextActions=JuliaNativeSearchActionWithOwner[(
                kind="query",
                ownerPath=path,
                scope="search",
                target=path,
                targetRole="path",
            )],
            path=path,
            public=true,
            role="owner",
        ) for path in owners
    ]
    windows = JuliaNativeSearchWindow[
        (
            kind=is_julia_test_path(path) ? "tests" : "owner",
            target=path,
        ) for path in candidates[begin:min(end, 8)]
    ]
    input_lines = String[line for line in eachsplit(stdin_text, '\n') if !isempty(line)]
    return (
        binary=JULIA_AGENT_BINARY,
        edges=JuliaNativeEmptySearchRow[],
        findings=JuliaNativeEmptySearchRow[],
        header=(
            fields=(provider=JULIA_INDEX_EXPORT_PROVIDER_ID, view="ingest"),
            kind="search-ingest",
        ),
        hits=JuliaNativeEmptySearchRow[],
        inputDetection=(
            byteCount=sizeof(stdin_text),
            lineCount=length(input_lines),
            sample=compact_cli_value(isempty(input_lines) ? "" : first(input_lines)),
            source="path-list",
        ),
        languageId=JULIA_INDEX_EXPORT_LANGUAGE_ID,
        method="search/ingest",
        namespace=JULIA_AGENT_PROVIDER_NAMESPACE,
        nextActions=actions,
        nodes=JuliaNativeEmptySearchRow[],
        notes=JuliaNativeEmptySearchRow[],
        owners=owner_rows,
        packageName=package_name,
        projectRoot=root,
        protocolId=JULIA_INDEX_EXPORT_PROTOCOL_ID,
        protocolVersion=JULIA_INDEX_EXPORT_PROTOCOL_VERSION,
        providerId=JULIA_INDEX_EXPORT_PROVIDER_ID,
        renderMode=render_mode,
        schemaId=JULIA_SEARCH_PACKET_SCHEMA_ID,
        schemaVersion=JULIA_SEARCH_PACKET_SCHEMA_VERSION,
        searchSynthesis=(
            algorithm="stdin-candidate-paths",
            editFrontier=owners,
            scope="ingest",
            seeds=actions,
            selectedOwners=length(owners),
            summary="Resolved stdin candidate paths",
            testFrontier=tests,
            windowSet=windows,
        ),
        view="ingest",
    )
end

function render_julia_native_ingest_packet_json(
    stdin_text::String,
    project_root::String,
    render_mode::String,
)::String
    return JSON.json(julia_native_ingest_packet(stdin_text, project_root, render_mode))
end

function render_julia_native_ingest_graph(
    stdin_text::String,
    project_root::String,
    render_mode::String,
)::String
    packet = julia_native_ingest_packet(stdin_text, project_root, render_mode)
    lines = String["[search-ingest] root=$(packet.projectRoot) view=ingest"]
    for action in packet.nextActions
        prefix = action.kind == "tests" ? "T" : "O"
        push!(lines, "$prefix=$(action.kind):path($(action.target))")
    end
    push!(
        lines,
        "frontier=" * join(
            [action.kind == "tests" ? "T.tests" : "O.owner" for action in packet.nextActions],
            ",",
        ),
    )
    return join(lines, "\n") * "\n"
end
