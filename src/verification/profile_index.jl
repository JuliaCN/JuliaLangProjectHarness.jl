"""Build parser-derived verification profile candidates for a Julia project."""
function build_julia_verification_profile_index(
    project_root::AbstractString;
    config=default_julia_harness_config(),
)
    verification_profile_index_from_context(project_policy_context(project_root, config), config)
end

function verification_profile_candidates_for_scope(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
)
    candidates = JuliaVerificationProfileCandidate[]
    if has_harness_dependency(scope)
        push!(candidates, test_profile_gate_candidate(scope, parsed_files))
    end
    responsibility_candidate = project_responsibility_profile_candidate(scope, parsed_files)
    !isnothing(responsibility_candidate) && push!(candidates, responsibility_candidate)
    append!(candidates, extension_profile_candidates(scope))
    candidates
end

function test_profile_gate_candidate(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
)
    has_hook = has_test_profile_hook(scope, parsed_files)
    JuliaVerificationProfileCandidate(
        scope.project_root,
        preferred_test_owner_path(scope),
        has_hook ? "configured" : "missing_profile",
        ["test_profile_gate"],
        ["harness_policy", "pkg_test"],
        verification_evidence(
            "hook" => string(has_hook),
            "dependency" => "AspJulia",
        ),
    )
end

function extension_profile_candidates(scope::JuliaProjectHarnessScope)
    [
        JuliaVerificationProfileCandidate(
            scope.project_root,
            extension_owner_path(scope, extension_name),
            extension_activation_state(scope, dependencies),
            ["extension_boundary"],
            ["extension_boundary", "pkg_test"],
            extension_boundary_evidence(
                scope,
                extension_name,
                dependencies,
                extension_activation_state(scope, dependencies),
            ),
        ) for (extension_name, dependencies) in sort(collect(scope.extensions); by=first)
    ]
end

"""Render verification profile candidates as compact text for agents."""
function render_julia_verification_profile_index(index::JuliaVerificationProfileIndex)
    isempty(index.candidates) && return "[ok] julia verification profiles no-candidates\n"
    lines = ["VerificationProfiles: count=$(length(index.candidates))"]
    for candidate in index.candidates
        push!(
            lines,
            "- state=$(candidate.state) owner=" *
            verification_profile_owner_path(index, candidate) *
            " responsibilities=$(join(candidate.responsibilities, ","))" *
            " tasks=$(join(candidate.task_kinds, ","))",
        )
        if !isempty(candidate.evidence)
            evidence = [
                "$(key)=$(value)" for (key, value) in sort(collect(candidate.evidence); by=first)
            ]
            push!(lines, "  evidence=$(join(evidence, ";"))")
        end
    end
    join(lines, "\n") * "\n"
end

"""Render the in-test verification profile as compact agent context."""
function render_julia_verification_profile(profile::JuliaVerificationProfile)
    parts = [
        chomp(render_julia_project_harness(profile.report)),
        chomp(render_julia_verification_task_index(profile.task_index)),
        chomp(render_julia_verification_profile_index(profile.profile_index)),
        isempty(profile.receipt_reviews) ? "" : chomp(
            render_julia_verification_receipt_reviews(
                profile.receipt_reviews;
                project_root=profile.task_index.project_root,
            ),
        ),
    ]
    join(filter(!isempty, parts), "\n") * "\n"
end

"""Render verification profile candidates as JSON."""
function render_julia_verification_profile_index_json(index::JuliaVerificationProfileIndex)
    JSON.json(verification_profile_index_dict(index))
end

"""Render the full in-test verification profile as JSON."""
function render_julia_verification_profile_json(profile::JuliaVerificationProfile)
    JSON.json(verification_profile_dict(profile))
end

function verification_profile_dict(profile::JuliaVerificationProfile)
    Dict(
        "report" => report_dict(profile.report),
        "task_index" => verification_task_index_dict(profile.task_index),
        "profile_index" => verification_profile_index_dict(profile.profile_index),
        "receipt_reviews" => map(verification_receipt_review_dict, profile.receipt_reviews),
    )
end

function verification_profile_index_dict(index::JuliaVerificationProfileIndex)
    Dict(
        "project_root" => slash_path(index.project_root),
        "candidates" => map(verification_profile_candidate_dict, index.candidates),
    )
end

function verification_profile_candidate_dict(candidate::JuliaVerificationProfileCandidate)
    Dict(
        "project_root" => slash_path(candidate.project_root),
        "owner_path" => slash_path(candidate.owner_path),
        "state" => candidate.state,
        "responsibilities" => candidate.responsibilities,
        "task_kinds" => candidate.task_kinds,
        "evidence" => candidate.evidence,
    )
end

function verification_profile_owner_path(
    index::JuliaVerificationProfileIndex,
    candidate::JuliaVerificationProfileCandidate,
)
    relative_path = relpath(candidate.owner_path, index.project_root)
    parts = splitpath(relative_path)
    if !isabspath(relative_path) && (isempty(parts) || first(parts) != "..")
        return slash_path(relative_path)
    end
    slash_path(candidate.owner_path)
end
