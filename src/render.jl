using JSON

"""Render blocking findings and agent advice as compact text."""
render_julia_project_harness(report::AspJuliaReport) =
    render_julia_project_harness_with_options(report; severities=nothing, include_advice=true)

"""Render only advisory findings from a Julia project harness report."""
function render_julia_project_harness_advice(report::AspJuliaReport)
    render_finding_list(advisory_findings(report))
end

function render_julia_project_harness_with_options(
    report::AspJuliaReport;
    severities=nothing,
    include_advice::Bool=true,
)
    blocking = blocking_findings(report; severities)
    advice = include_advice ? deduplicate_advice(advisory_findings(report), blocking) :
             AspJuliaFinding[]
    findings = copy(blocking)
    sizehint!(findings, length(blocking) + length(advice))
    for finding in advice
        push!(findings, finding)
    end
    isempty(findings) && return "[ok] julia\n"
    rendered = isempty(blocking) ? "" : render_julia_failure_frontier(report, blocking)
    if !isempty(advice)
        rendered *= isempty(rendered) ? "" : "\n"
        rendered *= render_finding_list(advice)
    end
    rendered
end

function render_finding_list(findings::Vector{AspJuliaFinding})
    isempty(findings) && return ""
    join(map(render_finding, findings), "\n")
end

function render_julia_failure_frontier(
    report::AspJuliaReport,
    findings::Vector{AspJuliaFinding},
)
    root = failure_frontier_root(report)
    lines = String[
        "[fail] julia blockingFindings=$(length(findings)) parsed=$(parsed_count(report))/$(file_count(report))",
    ]
    for finding in first(findings, min(length(findings), 3))
        selector = failure_frontier_selector(finding)
        path = isnothing(finding.location.path) ? "<memory>" : slash_path(finding.location.path)
        push!(
            lines,
            "|failureFrontier rule=$(finding.rule_id) severity=$(severity_label(finding.severity)) path=$(path) line=$(finding.location.line) column=$(finding.location.column + 1)",
        )
        push!(lines, "|message $(failure_frontier_text(finding.title))")
        !isempty(finding.summary) &&
            push!(lines, "|summary $(failure_frontier_text(finding.summary))")
        !isempty(finding.label) &&
            push!(lines, "|repair $(failure_frontier_text(finding.label))")
        if !isnothing(selector)
            push!(lines, "|hotBlock selector=$(selector) reason=blocking-finding")
            push!(lines, "|next action=direct-source-read selector=$(selector) root=$(root)")
        end
    end
    if length(findings) > 3
        push!(lines, "|more blockingFindings=$(length(findings) - 3)")
    end
    join(lines, "\n") * "\n"
end

failure_frontier_text(value::AbstractString) = join(split(String(value)), " ")

function failure_frontier_root(report::AspJuliaReport)
    if !isnothing(report.project_resolution)
        return slash_path(report.project_resolution.project_root)
    end
    isempty(report.root_paths) ? "." : slash_path(first(report.root_paths))
end

function failure_frontier_selector(finding::AspJuliaFinding)
    isnothing(finding.location.path) && return nothing
    line = max(finding.location.line, 1)
    "$(slash_path(finding.location.path)):$(line):$(line)"
end

function render_finding(finding::AspJuliaFinding)
    path = isnothing(finding.location.path) ? "<memory>" : slash_path(finding.location.path)
    display_column = finding.location.column + 1
    rendered = "[$(finding.rule_id)] $(titlecase(severity_label(finding.severity))): $(finding.title)\n"
    rendered *= "@ $(path):$(finding.location.line):$(display_column)\n"
    rendered *= "fix: $(finding.label)\n"
    if !isnothing(finding.source_line)
        rendered *= "line: $(finding.location.line) | $(finding.source_line)\n"
    end
    rendered *= "Help: $(finding.summary)\n"
    rendered *= "Contract: $(finding.requirement)\n"
    visibility = julia_rule_visibility(finding.rule_id)
    if !isnothing(visibility)
        rendered *= compact_rule_visibility(visibility)
    end
    rendered
end

function compact_rule_visibility(visibility::JuliaRuleVisibility)
    lines = String[]
    !isempty(visibility.accepted_ast_shapes) &&
        push!(lines, "Accepted AST: $(join(visibility.accepted_ast_shapes, " | "))")
    !isempty(visibility.rejected_ast_shapes) &&
        push!(lines, "Rejected AST: $(join(visibility.rejected_ast_shapes, " | "))")
    !isempty(visibility.minimal_examples) &&
        push!(lines, "Example: $(replace(first(visibility.minimal_examples), '\n' => " "))")
    !isempty(visibility.repair_notes) &&
        push!(lines, "Repair note: $(join(visibility.repair_notes, " | "))")
    isempty(lines) ? "" : join(lines, "\n") * "\n"
end

function deduplicate_advice(advice::Vector{AspJuliaFinding}, blocking::Vector{AspJuliaFinding})
    blocking_keys = Tuple{String,Union{Nothing,String},Int,Int}[]
    sizehint!(blocking_keys, length(blocking))
    for finding in blocking
        push!(blocking_keys, finding_key(finding))
    end
    retained = AspJuliaFinding[]
    sizehint!(retained, length(advice))
    for finding in advice
        key = finding_key(finding)
        duplicate = false
        for blocking_key in blocking_keys
            if key == blocking_key
                duplicate = true
                break
            end
        end
        if !duplicate
            push!(retained, finding)
        end
    end
    retained
end

function finding_key(finding::AspJuliaFinding)
    (finding.rule_id, finding.location.path, finding.location.line, finding.location.column)
end

slash_path(path::AbstractString) = replace(String(path), '\\' => '/')

"""Render a Julia project harness report as JSON for tools."""
function render_julia_project_harness_json(report::AspJuliaReport)
    JSON.json(report_dict(report))
end

function report_dict(report::AspJuliaReport)
    Dict(
        "files" => map(file_report_dict, report.files),
        "findings" => map(finding_dict, report.findings),
        "root_paths" => slash_path.(report.root_paths),
        "blocking_severities" => sort(severity_label.(collect(report.blocking_severities))),
        "project_resolution" => isnothing(report.project_resolution) ? nothing :
                           project_resolution_dict(report.project_resolution),
        "workspace_member_scopes" => map(project_resolution_dict, report.workspace_member_scopes),
    )
end

function file_report_dict(file::JuliaFileReport)
    Dict(
        "path" => slash_path(file.path),
        "is_valid" => file.is_valid,
        "parse_error" => file.parse_error,
    )
end

function finding_dict(finding::AspJuliaFinding)
    Dict(
        "rule_id" => finding.rule_id,
        "pack_id" => finding.pack_id,
        "severity" => severity_label(finding.severity),
        "title" => finding.title,
        "summary" => finding.summary,
        "location" => location_dict(finding.location),
        "requirement" => finding.requirement,
        "source_line" => finding.source_line,
        "label" => finding.label,
        "labels" => finding.labels,
    )
end

function location_dict(location::SourceLocation)
    Dict(
        "path" => isnothing(location.path) ? nothing : slash_path(location.path),
        "line" => location.line,
        "column" => location.column,
    )
end

function project_resolution_dict(scope::JuliaProjectHarnessScope)
    Dict(
        "project_root" => slash_path(scope.project_root),
        "project_toml_path" => isnothing(scope.project_toml_path) ? nothing :
                               slash_path(scope.project_toml_path),
        "project_parse_error" => scope.project_parse_error,
        "package_name" => scope.package_name,
        "package_uuid" => scope.package_uuid,
        "project_entryfile" => scope.project_entryfile,
        "package_entry_path" => isnothing(scope.package_entry_path) ? nothing :
                                slash_path(scope.package_entry_path),
        "direct_dependencies" => scope.direct_dependencies,
        "weak_dependencies" => scope.weak_dependencies,
        "extra_dependencies" => scope.extra_dependencies,
        "targets" => scope.targets,
        "compat" => scope.compat,
        "sources" => scope.sources,
        "extensions" => scope.extensions,
        "workspace_projects" => scope.workspace_projects,
        "source_dependency_projects" => scope.source_dependency_projects,
        "source_paths" => slash_path.(scope.source_paths),
        "extension_paths" => slash_path.(scope.extension_paths),
        "test_paths" => slash_path.(scope.test_paths),
        "package_paths" => slash_path.(scope.package_paths),
        "fallback_paths" => slash_path.(scope.fallback_paths),
    )
end
