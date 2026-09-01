const MAX_AGENT_SNAPSHOT_VERIFICATION_TASKS = 10

function snapshot_verification_lines(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
    config::AspJuliaConfig,
)
    records = verification_task_records_for_scope(scope, config, parsed_files)
    isempty(records) && return String[]
    sort!(records; by=record -> (record.kind, display_project_path(scope, record.owner_path)))
    compact_snapshot_verification_lines([
        display_snapshot_verification_task(scope, record) for record in records
    ])
end

function display_snapshot_verification_task(
    scope::JuliaProjectHarnessScope,
    record::JuliaVerificationTaskRecord,
)
    segments = [
        "kind=$(record.kind)",
        "phase=$(record.phase)",
        "owner=$(display_project_path(scope, record.owner_path))",
    ]
    command = snapshot_verification_command(scope, record)
    isempty(command) || push!(segments, "command=$(command)")
    evidence = snapshot_verification_evidence(record)
    isempty(evidence) || push!(segments, "evidence=$(evidence)")
    required = compact_required_evidence(record)
    isempty(required) || push!(segments, "requires=$(required)")
    "- $(join(segments, " "))"
end

function snapshot_verification_command(
    scope::JuliaProjectHarnessScope,
    record::JuliaVerificationTaskRecord,
)
    isempty(record.command) && return ""
    join(shell_quote_arg.(snapshot_verification_command_arg.(Ref(scope), record.command)), " ")
end

function snapshot_verification_command_arg(
    scope::JuliaProjectHarnessScope,
    arg::AbstractString,
)
    text = String(arg)
    project_prefix = "--project="
    if startswith(text, project_prefix)
        project_path = text[(lastindex(project_prefix) + 1):end]
        normalized = normpath(project_path)
        normpath(scope.project_root) == normalized && return "--project=."
        if isabspath(project_path) && is_path_under(normalized, scope.project_root)
            return "--project=$(display_project_path(scope, normalized))"
        end
        return text
    end
    replace(text, scope.project_root => ".")
end

function snapshot_verification_evidence(record::JuliaVerificationTaskRecord)
    keys = [
        "benchmark_project",
        "example_project",
        "docs_project",
        "make",
        "tool",
        "entry",
        "activation",
        "responsibilities",
        "extension",
        "weakdeps",
        "capabilities",
        "capability_source",
        "algorithm_shapes",
        "performance_roots",
        "security_roots",
        "persistence_roots",
        "network_roots",
    ]
    evidence = ["$(key)=$(record.evidence[key])" for key in keys if haskey(record.evidence, key)]
    join(evidence, ";")
end

function compact_snapshot_verification_lines(lines::Vector{String})
    length(lines) <= MAX_AGENT_SNAPSHOT_VERIFICATION_TASKS && return lines
    kept = lines[1:MAX_AGENT_SNAPSHOT_VERIFICATION_TASKS]
    push!(kept, "... $(length(lines) - MAX_AGENT_SNAPSHOT_VERIFICATION_TASKS) more verification tasks")
    kept
end
