function verification_search_entries(
    scope::JuliaProjectHarnessScope,
    config::AspJuliaConfig,
    parsed_files::Vector{ParsedJuliaFile},
)
    [
        verification_search_entry(scope, record) for record in
        verification_task_records_for_scope(scope, config, parsed_files)
    ]
end

function verification_search_entry(
    scope::JuliaProjectHarnessScope,
    record::JuliaVerificationTaskRecord,
)
    owner = verification_owner_fingerprint_part(scope, record.owner_path)
    detail = verification_search_detail(scope, record, owner)
    JuliaSearchIndexEntry(
        SourceLocation(record.owner_path, something(record.line, 1), 0),
        "verification",
        "$(record.kind) $(owner)",
        detail,
        join(["verification", record.kind, owner, detail, record.reason], " "),
        verification_search_tags(record),
    )
end

function verification_search_detail(
    scope::JuliaProjectHarnessScope,
    record::JuliaVerificationTaskRecord,
    owner::AbstractString,
)
    segments = [
        "kind=$(record.kind)",
        "phase=$(record.phase)",
        "owner=$(owner)",
    ]
    if !isempty(record.command)
        push!(segments, "command=$(verification_search_command(scope, record))")
    end
    evidence = verification_search_evidence(record)
    isempty(evidence) || push!(segments, "evidence=$(evidence)")
    required = compact_required_evidence(record)
    isempty(required) || push!(segments, "requires=$(required)")
    push!(segments, "reason=$(record.reason)")
    join(segments, " ")
end

function verification_search_command(
    scope::JuliaProjectHarnessScope,
    record::JuliaVerificationTaskRecord,
)
    join(shell_quote_arg.(verification_search_command_arg.(Ref(scope), record.command)), " ")
end

function verification_search_command_arg(
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
            return "--project=$(verification_owner_fingerprint_part(scope, normalized))"
        end
        return text
    end
    replace(text, scope.project_root => ".")
end

function verification_search_evidence(record::JuliaVerificationTaskRecord)
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

function verification_search_tags(record::JuliaVerificationTaskRecord)
    tags = ["verification", record.kind, record.phase]
    !isempty(record.command) && push!(tags, "runnable")
    !isempty(verification_task_required_evidence(record)) && push!(tags, "receipt")
    append!(tags, verification_search_evidence_tags(record))
    unique(tags)
end

function verification_search_evidence_tags(record::JuliaVerificationTaskRecord)
    tags = String[]
    haskey(record.evidence, "benchmark_project") && push!(tags, "benchmark")
    haskey(record.evidence, "example_project") && push!(tags, "example")
    haskey(record.evidence, "docs_project") && push!(tags, "docs")
    haskey(record.evidence, "extension") && push!(tags, "extension")
    get(record.evidence, "tool", "") == "Documenter" && push!(tags, "documenter")
    haskey(record.evidence, "capability_source") &&
        push!(tags, lowercase(record.evidence["capability_source"]))
    haskey(record.evidence, "activation") &&
        push!(tags, record.evidence["activation"])
    tags
end
