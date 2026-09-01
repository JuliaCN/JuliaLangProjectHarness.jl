"""Build agent-runnable verification tasks for a Julia project root."""
function build_julia_verification_task_index(
    project_root::AbstractString;
    config=default_julia_harness_config(),
)
    context = project_policy_context(project_root, config)
    verification_task_index_from_context(context, context.config)
end

"""Build the in-test verification profile that agents should keep green."""
function build_julia_project_verification_profile(
    project_root::AbstractString=pwd();
    config=default_julia_harness_config(),
)
    context = project_policy_context(project_root, config)
    report = harness_report_from_project_context(context, context.config)
    task_index = verification_task_index_from_context(context, context.config)
    profile_index = verification_profile_index_from_context(context, context.config)
    receipt_reviews = review_julia_project_verification_receipts(task_index)
    JuliaVerificationProfile(report, task_index, profile_index, receipt_reviews)
end

"""Assert the package's JuliaSyntax policy and verification profile from Pkg.test."""
function assert_julia_project_harness_test_profile_clean(
    project_root::AbstractString=pwd();
    config=default_julia_harness_config(),
    advice_io::Union{Nothing,IO}=stdout,
)
    profile = build_julia_project_verification_profile(project_root; config)
    effective_config = project_policy_context(project_root, config).config
    has_blocking = !is_clean(profile.report)
    has_advice = !has_agent_advice_allow_explanation(effective_config) &&
                 !isempty(advisory_findings(profile.report))
    has_receipt_failures = any(
        review -> !is_julia_verification_receipt_review_clean(review),
        profile.receipt_reviews,
    )
    if has_blocking || has_advice || has_receipt_failures
        error(render_julia_verification_profile(profile))
    end
    if !isnothing(advice_io)
        print(advice_io, render_julia_verification_pending_advice(profile))
    end
    profile
end

function verification_task_records_for_scope(
    scope::JuliaProjectHarnessScope,
    config::AspJuliaConfig,
    parsed_files::Vector{ParsedJuliaFile}=parsed_julia_files_for_scope(scope, config),
)
    records = JuliaVerificationTaskRecord[]
    push!(records, pkg_test_verification_task(scope))
    if has_harness_dependency(scope)
        push!(records, harness_self_policy_verification_task(scope))
        push!(records, syntax_search_verification_task(scope))
    end
    benchmark_records = benchmark_verification_tasks(scope)
    append!(records, benchmark_records)
    append!(records, example_verification_tasks(scope))
    excluded_inferred_task_kinds = Set{String}(record.kind for record in benchmark_records)
    append!(
        records,
        inferred_verification_task_records(
            scope,
            parsed_files;
            exclude_task_kinds=excluded_inferred_task_kinds,
        ),
    )
    append!(records, extension_verification_tasks(scope))
    append!(records, docs_verification_tasks(scope))
    filter(!isnothing, records)
end

function parsed_julia_files_for_scope(scope::JuliaProjectHarnessScope, config::AspJuliaConfig)
    [
        parse_julia_file(path) for path in discover_julia_files(
            scope_monitored_paths(scope),
            config,
        )
    ]
end

function pkg_test_verification_task(scope::JuliaProjectHarnessScope)
    owner_path = preferred_test_owner_path(scope)
    JuliaVerificationTaskRecord(
        verification_fingerprint(
            "pkg_test",
            verification_scope_fingerprint(scope),
            verification_owner_fingerprint_part(scope, owner_path),
        ),
        "pkg_test",
        "pending",
        "after_unit_tests_pass",
        scope.project_root,
        owner_path,
        nothing,
        ["julia", "--project=$(scope.project_root)", "-e", "using Pkg; Pkg.test()"],
        verification_evidence(
            "package" => something(scope.package_name, "<unnamed>"),
            "targets" => verification_targets_summary(scope),
            "tests" => string(length(scope.test_paths)),
        ),
        "Run the Julia package test gate from the Project.toml root.",
    )
end

function harness_self_policy_verification_task(scope::JuliaProjectHarnessScope)
    owner_path = preferred_test_owner_path(scope)
    JuliaVerificationTaskRecord(
        verification_fingerprint(
            "harness_policy",
            verification_scope_fingerprint(scope),
            verification_owner_fingerprint_part(scope, owner_path),
        ),
        "harness_policy",
        "pending",
        "after_unit_tests_pass",
        scope.project_root,
        owner_path,
        nothing,
        [
            "julia",
            "--project=$(scope.project_root)",
            "-e",
            "using AspJulia; assert_julia_project_harness_test_profile_clean(pwd())",
        ],
        verification_evidence(
            "package" => something(scope.package_name, "<unnamed>"),
            "dependency" => "AspJulia",
            "profile" => "test",
        ),
        "Run the in-test harness verification profile that agents should keep green.",
    )
end

function syntax_search_verification_task(scope::JuliaProjectHarnessScope)
    owner_path = preferred_source_owner_path(scope)
    JuliaVerificationTaskRecord(
        verification_fingerprint(
            "syntax_search",
            verification_scope_fingerprint(scope),
            verification_owner_fingerprint_part(scope, owner_path),
        ),
        "syntax_search",
        "pending",
        "after_unit_tests_pass",
        scope.project_root,
        owner_path,
        nothing,
        [
            "julia",
            "--project=$(scope.project_root)",
            "-e",
            "using AspJulia; julia_project_search_index(pwd())",
        ],
        verification_evidence(
            "sources" => string(length(scope.source_paths)),
            "extensions" => string(length(scope.extension_paths)),
        ),
        "Smoke the JuliaSyntax-derived search index for agent context selection.",
    )
end

function docs_verification_tasks(scope::JuliaProjectHarnessScope)
    docs_root = joinpath(scope.project_root, "docs")
    docs_project = joinpath(docs_root, "Project.toml")
    docs_make = joinpath(docs_root, "make.jl")
    isfile(docs_project) || return JuliaVerificationTaskRecord[]
    isfile(docs_make) || return JuliaVerificationTaskRecord[]
    docs_facts = parse_project_toml_facts(docs_project)
    haskey(docs_facts.direct_dependencies, "Documenter") ||
        haskey(docs_facts.extra_dependencies, "Documenter") ||
        return JuliaVerificationTaskRecord[]
    [
        JuliaVerificationTaskRecord(
            verification_fingerprint(
                "docs_build",
                verification_scope_fingerprint(scope),
                verification_owner_fingerprint_part(scope, docs_make),
            ),
            "docs_build",
            "pending",
            "after_unit_tests_pass",
            scope.project_root,
            docs_make,
            nothing,
            [
                "julia",
                "--project=$(docs_root)",
                "-e",
                "cd($(repr(docs_root))) do; include(\"make.jl\"); end",
            ],
            verification_evidence(
                "tool" => "Documenter",
                "docs_project" => verification_owner_fingerprint_part(scope, docs_project),
                "make" => verification_owner_fingerprint_part(scope, docs_make),
            ),
            "Build Documenter docs and run doctests from the docs project.",
        ),
    ]
end

const JULIA_AGENT_VERIFICATION_TASK_KINDS = Set([
    "chaos",
    "extension_boundary",
    "performance",
    "security",
    "stress",
])

function inferred_verification_task_records(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile};
    exclude_task_kinds::Set{String}=Set{String}(),
)
    candidate = project_responsibility_profile_candidate(scope, parsed_files)
    isnothing(candidate) && return JuliaVerificationTaskRecord[]
    [
        inferred_verification_task_record(scope, candidate, task_kind) for
        task_kind in candidate.task_kinds if
        task_kind in JULIA_AGENT_VERIFICATION_TASK_KINDS &&
        !(task_kind in exclude_task_kinds)
    ]
end

function inferred_verification_task_record(
    scope::JuliaProjectHarnessScope,
    candidate::JuliaVerificationProfileCandidate,
    task_kind::AbstractString,
)
    evidence = copy(candidate.evidence)
    evidence["responsibilities"] = join(candidate.responsibilities, ",")
    JuliaVerificationTaskRecord(
        verification_fingerprint(
            String(task_kind),
            verification_scope_fingerprint(scope),
            verification_owner_fingerprint_part(scope, candidate.owner_path),
            join(candidate.responsibilities, ","),
        ),
        String(task_kind),
        "pending",
        inferred_verification_task_phase(task_kind),
        scope.project_root,
        candidate.owner_path,
        nothing,
        String[],
        evidence,
        inferred_verification_task_reason(task_kind),
    )
end

function inferred_verification_task_phase(task_kind::AbstractString)
    task_kind in ("stress", "performance") && return "after_unit_tests_pass"
    task_kind in ("chaos", "security") && return "before_release"
    "after_unit_tests_pass"
end

function inferred_verification_task_reason(task_kind::AbstractString)
    task_kind == "stress" &&
        return "Agent should add or run stress-style validation for this public Julia API surface."
    task_kind == "performance" &&
        return "Agent should add or run Julia-native performance evidence for this latency-sensitive owner."
    task_kind == "chaos" &&
        return "Agent should add or run dependency, persistence, or availability failure-mode verification."
    task_kind == "security" &&
        return "Agent should add or run security-boundary verification for this owner."
    "Agent should add or run verification evidence for this inferred responsibility."
end

function has_harness_dependency(scope::JuliaProjectHarnessScope)
    scope.package_name == "AspJulia" ||
        haskey(scope.direct_dependencies, "AspJulia") ||
        haskey(scope.extra_dependencies, "AspJulia")
end

function preferred_test_owner_path(scope::JuliaProjectHarnessScope)
    runtests = joinpath(scope.project_root, "test", "runtests.jl")
    isfile(runtests) && return runtests
    !isempty(scope.test_paths) && return first(sort(scope.test_paths))
    something(scope.project_toml_path, scope.project_root)
end

function preferred_source_owner_path(scope::JuliaProjectHarnessScope)
    !isnothing(scope.package_entry_path) && return scope.package_entry_path
    !isempty(scope.source_paths) && return first(sort(scope.source_paths))
    something(scope.project_toml_path, scope.project_root)
end

function extension_owner_path(scope::JuliaProjectHarnessScope, extension_name::AbstractString)
    for root in scope.extension_paths
        candidate = joinpath(root, "$(extension_name).jl")
        isfile(candidate) && return candidate
    end
    joinpath(scope.project_root, "ext", "$(extension_name).jl")
end

function verification_targets_summary(scope::JuliaProjectHarnessScope)
    isempty(scope.targets) && return ""
    parts = ["$(name)=$(join(values, ","))" for (name, values) in sort(collect(scope.targets); by=first)]
    join(parts, ";")
end

function verification_evidence(pairs::Pair{String,String}...)
    Dict(key => value for (key, value) in pairs if !isempty(value))
end

function verification_fingerprint(parts::AbstractString...)
    join((compact_fingerprint_part(part) for part in parts), ":")
end

function verification_scope_fingerprint(scope::JuliaProjectHarnessScope)
    !isnothing(scope.package_uuid) && return scope.package_uuid
    !isnothing(scope.package_name) && return scope.package_name
    basename(scope.project_root)
end

function verification_owner_fingerprint_part(
    scope::JuliaProjectHarnessScope,
    owner_path::AbstractString,
)
    root = normpath(scope.project_root)
    owner = normpath(String(owner_path))
    owner == root && return "."
    prefix = root * string(Base.Filesystem.path_separator)
    startswith(owner, prefix) || return slash_path(owner)
    slash_path(String(SubString(owner, nextind(owner, lastindex(prefix)))))
end

function compact_fingerprint_part(part::AbstractString)
    replace(slash_path(part), r"[^A-Za-z0-9_.=-]+" => "_")
end

"""Render verification tasks as compact text for agent execution."""
function render_julia_verification_task_index(index::JuliaVerificationTaskIndex)
    isempty(index.records) && return "[ok] julia verification tasks no-records\n"
    lines = ["VerificationTasks: count=$(length(index.records))"]
    for record in index.records
        push!(
            lines,
            "- kind=$(record.kind) state=$(record.state) phase=$(record.phase) owner=" *
            verification_owner_path(index, record),
        )
        push!(lines, "  fingerprint=$(record.fingerprint)")
        if !isempty(record.command)
            command = join(shell_quote_arg.(record.command), " ")
            push!(lines, "  command=$(command)")
        end
        if !isempty(record.evidence)
            evidence = [
                "$(key)=$(value)" for (key, value) in sort(collect(record.evidence); by=first)
            ]
            compact_evidence = join(evidence, ";")
            push!(lines, "  evidence=$(compact_evidence)")
        end
        required_evidence = compact_required_evidence(record)
        !isempty(required_evidence) && push!(lines, "  requires=$(required_evidence)")
        push!(lines, "  reason=$(record.reason)")
    end
    join(lines, "\n") * "\n"
end

function shell_quote_arg(arg::AbstractString)
    text = String(arg)
    occursin(r"[\s;'\"$`\\]", text) || return text
    "'$(replace(text, "'" => "'\\''"))'"
end

"""Render verification tasks as JSON while preserving raw argv vectors."""
function render_julia_verification_task_index_json(index::JuliaVerificationTaskIndex)
    JSON.json(verification_task_index_dict(index))
end

function verification_task_index_dict(index::JuliaVerificationTaskIndex)
    Dict(
        "project_root" => slash_path(index.project_root),
        "records" => map(verification_task_record_dict, index.records),
    )
end

function verification_task_record_dict(record::JuliaVerificationTaskRecord)
    Dict(
        "fingerprint" => record.fingerprint,
        "kind" => record.kind,
        "state" => record.state,
        "phase" => record.phase,
        "project_root" => slash_path(record.project_root),
        "owner_path" => slash_path(record.owner_path),
        "line" => record.line,
        "command" => record.command,
        "evidence" => record.evidence,
        "required_evidence" => verification_task_required_evidence(record),
        "required_receipt" => verification_task_required_receipt(record),
        "reason" => record.reason,
    )
end

function verification_owner_path(
    index::JuliaVerificationTaskIndex,
    record::JuliaVerificationTaskRecord,
)
    relative_path = relpath(record.owner_path, index.project_root)
    parts = splitpath(relative_path)
    if !isabspath(relative_path) && (isempty(parts) || first(parts) != "..")
        return slash_path(relative_path)
    end
    slash_path(record.owner_path)
end
