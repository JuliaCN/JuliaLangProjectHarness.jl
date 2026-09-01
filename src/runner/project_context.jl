function project_policy_context(project_root::AbstractString, config::AspJuliaConfig)
    effective_config = project_toml_harness_config(project_root, config)
    scope = julia_project_harness_scope(project_root, effective_config)
    workspace_member_scopes = julia_workspace_member_scopes(scope, effective_config)
    monitored_paths = project_policy_monitored_paths(scope, workspace_member_scopes)
    parsed_files = parse_julia_files_for_paths(monitored_paths, effective_config)
    (; scope, workspace_member_scopes, monitored_paths, parsed_files, config = effective_config)
end

function project_policy_monitored_paths(
    scope::JuliaProjectHarnessScope,
    workspace_member_scopes::Vector{JuliaProjectHarnessScope},
)
    vcat(
        scope_monitored_paths(scope),
        mapreduce(scope_monitored_paths, vcat, workspace_member_scopes; init=String[]),
    )
end

function parse_julia_files_for_paths(paths::Vector{String}, config::AspJuliaConfig)
    [parse_julia_file(path) for path in discover_julia_files(paths, config)]
end

function harness_report_from_parsed(
    paths::Vector{String},
    parsed_files::Vector{ParsedJuliaFile},
    config::AspJuliaConfig;
    scope=nothing,
    workspace_member_scopes=JuliaProjectHarnessScope[],
)
    findings = evaluate_default_rule_packs(
        scope,
        parsed_files,
        config;
        workspace_member_scopes,
    )
    AspJuliaReport(
        [parsed.report for parsed in parsed_files],
        findings,
        paths,
        copy(config.blocking_severities),
        scope,
        workspace_member_scopes,
    )
end

function harness_report_from_project_context(context, config::AspJuliaConfig)
    harness_report_from_parsed(
        context.monitored_paths,
        context.parsed_files,
        config;
        scope=context.scope,
        workspace_member_scopes=context.workspace_member_scopes,
    )
end
