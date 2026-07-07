@enum JuliaDiagnosticSeverity::UInt8 Info Warning Error

severity_label(::Val{Info}) = "info"
severity_label(::Val{Warning}) = "warning"
severity_label(::Val{Error}) = "error"
severity_label(severity::JuliaDiagnosticSeverity) = severity_label(Val(severity))

"""Source position for a parser fact or harness finding."""
struct SourceLocation
    path::Union{Nothing,String}
    line::Int
    column::Int
end

"""Metadata for a rule pack exposed by the Julia project harness."""
struct RulePackDescriptor
    id::String
    version::String
    domains::Vector{String}
    default_mode::Symbol
end

"""Rule contract used to create project harness findings."""
struct JuliaHarnessRule
    rule_id::String
    pack_id::String
    severity::JuliaDiagnosticSeverity
    title::String
    requirement::String
    labels::Dict{String,String}
end

"""Agent-facing visibility contract for one harness rule."""
struct JuliaRuleVisibility
    rule_id::String
    accepted_ast_shapes::Vector{String}
    rejected_ast_shapes::Vector{String}
    minimal_examples::Vector{String}
    repair_notes::Vector{String}
end

"""Concrete harness finding with source evidence and repair guidance."""
struct JuliaHarnessFinding
    rule_id::String
    pack_id::String
    severity::JuliaDiagnosticSeverity
    title::String
    summary::String
    location::SourceLocation
    requirement::String
    source_line::Union{Nothing,String}
    label::String
    labels::Dict{String,String}
end

"""Parse status for one Julia source file."""
struct JuliaFileReport
    path::String
    is_valid::Bool
    parse_error::Union{Nothing,String}
end

"""Searchable JuliaSyntax-derived entry for agent context retrieval."""
struct JuliaSearchIndexEntry
    location::SourceLocation
    kind::String
    name::String
    detail::String
    search_text::String
    tags::Vector{String}
end

"""Ranked result returned by Julia syntax search queries."""
struct JuliaSearchResult
    entry::JuliaSearchIndexEntry
    score::Int
end

"""Agent-runnable verification task derived from project structure."""
struct JuliaVerificationTaskRecord
    fingerprint::String
    kind::String
    state::String
    phase::String
    project_root::String
    owner_path::String
    line::Union{Nothing,Int}
    command::Vector{String}
    evidence::Dict{String,String}
    reason::String
end

"""Collection of verification tasks for a Julia project root."""
struct JuliaVerificationTaskIndex
    project_root::String
    records::Vector{JuliaVerificationTaskRecord}
end

"""Review result for one agent-submitted verification receipt."""
struct JuliaVerificationReceiptReview
    fingerprint::String
    kind::String
    status::Symbol
    project_root::String
    owner_path::String
    missing_evidence::Vector{String}
    weak_evidence::Vector{String}
    problems::Vector{String}
    required_receipt::String
end

"""Parser-suggested verification responsibility for one Julia owner."""
struct JuliaVerificationProfileCandidate
    project_root::String
    owner_path::String
    state::String
    responsibilities::Vector{String}
    task_kinds::Vector{String}
    evidence::Dict{String,String}
end

"""Collection of parser-derived verification profile candidates."""
struct JuliaVerificationProfileIndex
    project_root::String
    candidates::Vector{JuliaVerificationProfileCandidate}
end

"""Pkg project scope resolved from Project.toml and Julia source layout."""
struct JuliaProjectHarnessScope
    project_root::String
    project_toml_path::Union{Nothing,String}
    project_parse_error::Union{Nothing,String}
    package_name::Union{Nothing,String}
    package_uuid::Union{Nothing,String}
    project_entryfile::Union{Nothing,String}
    package_entry_path::Union{Nothing,String}
    direct_dependencies::Dict{String,String}
    weak_dependencies::Dict{String,String}
    extra_dependencies::Dict{String,String}
    targets::Dict{String,Vector{String}}
    compat::Dict{String,String}
    sources::Dict{String,Dict{String,String}}
    extensions::Dict{String,Vector{String}}
    workspace_projects::Vector{String}
    source_dependency_projects::Vector{String}
    source_paths::Vector{String}
    extension_paths::Vector{String}
    test_paths::Vector{String}
    package_paths::Vector{String}
    fallback_paths::Vector{String}
end

"""Configuration for syntax parsing, project policy, and advice rules."""
struct JuliaHarnessConfig
    ignored_dir_names::Set{String}
    blocking_severities::Set{JuliaDiagnosticSeverity}
    disabled_rules::Set{String}
    disabled_rule_explanations::Dict{String,String}
    rule_severity_overrides::Dict{String,JuliaDiagnosticSeverity}
    rule_severity_override_explanations::Dict{String,String}
    blocking_severity_explanations::Dict{String,String}
    include_tests::Bool
    source_dir_names::Vector{String}
    test_dir_names::Vector{String}
    source_path_explanations::Dict{String,String}
    test_path_explanations::Dict{String,String}
    source_path_exclusion_explanations::Dict{String,String}
    test_path_exclusion_explanations::Dict{String,String}
    agent_advice_allow_explanation::Union{Nothing,String}
end

"""Full harness run result with parsed files, findings, and project scope."""
struct JuliaHarnessReport
    files::Vector{JuliaFileReport}
    findings::Vector{JuliaHarnessFinding}
    root_paths::Vector{String}
    blocking_severities::Set{JuliaDiagnosticSeverity}
    project_scope::Union{Nothing,JuliaProjectHarnessScope}
    workspace_member_scopes::Vector{JuliaProjectHarnessScope}
end

"""In-test verification profile for agent-facing package checks."""
struct JuliaVerificationProfile
    report::JuliaHarnessReport
    task_index::JuliaVerificationTaskIndex
    profile_index::JuliaVerificationProfileIndex
    receipt_reviews::Vector{JuliaVerificationReceiptReview}
end

const DEFAULT_IGNORED_DIR_NAMES = Set([
    ".cache",
    ".devenv",
    ".direnv",
    ".git",
    ".idea",
    ".jj",
    ".run",
    ".vscode",
    "artifacts",
    "deps",
    "node_modules",
    "scratchspaces",
])

"""Return the default Julia project harness configuration."""
function default_julia_harness_config()
    JuliaHarnessConfig(
        union(copy(DEFAULT_IGNORED_DIR_NAMES), Set([".gerbil"])),
        Set([Warning, Error]),
        Set{String}(),
        Dict{String,String}(),
        Dict{String,JuliaDiagnosticSeverity}(),
        Dict{String,String}(),
        Dict{String,String}(),
        true,
        ["src"],
        ["test"],
        Dict{String,String}(),
        Dict{String,String}(),
        Dict{String,String}(),
        Dict{String,String}(),
        nothing,
    )
end

file_count(report::JuliaHarnessReport) = length(report.files)
parsed_count(report::JuliaHarnessReport) = count(file -> file.is_valid, report.files)

function blocking_findings(report::JuliaHarnessReport; severities=nothing)
    selected = isnothing(severities) ? report.blocking_severities : severities
    [
        finding for finding in report.findings if finding.severity in selected ||
        is_escape_guard_finding(finding)
    ]
end

advisory_findings(report::JuliaHarnessReport) =
    [finding for finding in report.findings if finding.severity == Info]

is_clean(report::JuliaHarnessReport) = isempty(blocking_findings(report))

function is_escape_guard_finding(finding::JuliaHarnessFinding)
    get(finding.labels, "escape_guard", "") == "true"
end

function assert_clean(report::JuliaHarnessReport)
    if !is_clean(report)
        error(render_julia_project_harness(report))
    end
    report
end

function assert_no_advisory_findings(report::JuliaHarnessReport)
    if !isempty(advisory_findings(report))
        error(render_julia_project_harness(report))
    end
    report
end
