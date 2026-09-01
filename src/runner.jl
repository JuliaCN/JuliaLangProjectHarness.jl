using Pkg
using SHA
using TOML

"""Run the JuliaSyntax harness over explicit Julia source roots.

Errors if any requested source root does not exist.
"""
function run_julia_lang_harness(paths::Vector{<:AbstractString}; config=default_julia_harness_config())
    for path in paths
        ispath(path) || error("harness path does not exist: $(path)")
    end
    run_paths(abspath.(String.(paths)), config)
end

"""Run the project harness from a Project.toml root resolved through Pkg facts.

Errors if `project_root` does not name an existing package path.
"""
function run_julia_project_harness(project_root::AbstractString; config=default_julia_harness_config())
    ispath(project_root) || error("project path does not exist: $(project_root)")
    context = project_policy_context(project_root, config)
    harness_report_from_project_context(context, context.config)
end

"""Run explicit paths and throw when blocking Julia harness findings exist."""
function assert_julia_lang_harness_clean(paths::Vector{<:AbstractString}; config=default_julia_harness_config())
    report = run_julia_lang_harness(paths; config)
    assert_clean(report)
end

"""Run a Project.toml-rooted harness check and throw on blocking findings."""
function assert_julia_project_harness_clean(project_root::AbstractString; config=default_julia_harness_config())
    report = run_julia_project_harness(project_root; config)
    assert_clean(report)
end

"""Run project policy plus advisory self-apply checks for package test gates."""
function assert_julia_project_harness_pkg_test_clean(
    project_root::AbstractString;
    config=default_julia_harness_config(),
)
    report = run_julia_project_harness(project_root; config)
    effective_config = project_policy_context(project_root, config).config
    assert_clean(report)
    if !has_agent_advice_allow_explanation(effective_config)
        assert_no_advisory_findings(report)
    end
    report
end

function run_paths(
    paths::Vector{String},
    config::AspJuliaConfig;
    scope=nothing,
    workspace_member_scopes=JuliaProjectHarnessScope[],
)
    parsed_files = parse_julia_files_for_paths(paths, config)
    harness_report_from_parsed(paths, parsed_files, config; scope, workspace_member_scopes)
end

function julia_project_harness_scope(project_root::AbstractString, config::AspJuliaConfig)
    project_facts = parse_project_toml_facts(project_root)
    root = project_facts.project_root
    source_paths = pkg_source_paths(root, project_facts, config)
    extension_paths = pkg_extension_paths(root, project_facts)
    test_paths = config.include_tests ? pkg_test_paths(root, project_facts, config) : String[]
    package_paths = pkg_package_paths(root)
    JuliaProjectHarnessScope(
        root,
        project_facts.path,
        project_facts.parse_error,
        project_facts.package_name,
        project_facts.package_uuid,
        project_facts.entryfile,
        package_entry_path(root, project_facts.package_name, project_facts.entryfile),
        project_facts.direct_dependencies,
        project_facts.weak_dependencies,
        project_facts.extra_dependencies,
        project_facts.targets,
        project_facts.compat,
        project_facts.sources,
        project_facts.extensions,
        project_facts.workspace_projects,
        project_facts.source_dependency_projects,
        source_paths,
        extension_paths,
        test_paths,
        package_paths,
        String[],
    )
end

function julia_workspace_member_scopes(
    scope::JuliaProjectHarnessScope,
    config::AspJuliaConfig,
)
    scopes = JuliaProjectHarnessScope[]
    seen_roots = Set([scope.project_root])
    for project_path in pkg_member_project_paths(scope)
        member_root = isabspath(project_path) ? normpath(project_path) :
                      normpath(joinpath(scope.project_root, project_path))
        isdir(member_root) || continue
        member_scope = julia_project_harness_scope(member_root, config)
        member_scope.project_root in seen_roots && continue
        push!(seen_roots, member_scope.project_root)
        push!(scopes, member_scope)
    end
    scopes
end

function scope_monitored_paths(scope::JuliaProjectHarnessScope)
    selected = vcat(scope.source_paths, scope.extension_paths, scope.test_paths)
    isempty(selected) ? [scope.project_root] : selected
end

function pkg_member_project_paths(scope::JuliaProjectHarnessScope)
    sort!(collect(Set(vcat(scope.workspace_projects, scope.source_dependency_projects))))
end

function pkg_source_paths(
    project_root::AbstractString,
    project_facts,
    config::AspJuliaConfig,
)
    roots = String[]
    pkg_root = package_entry_source_root(
        project_root,
        project_facts.package_name,
        project_facts.entryfile,
    )
    add_existing_path!(roots, pkg_root)
    for path_name in config.source_dir_names
        full_path = joinpath(project_root, path_name)
        ispath(full_path) || continue
        if path_name == "src" && !isnothing(pkg_root) && !same_path(full_path, pkg_root)
            has_configured_path_explanation(
                config.source_path_explanations,
                project_root,
                path_name,
            ) || continue
        end
        add_existing_path!(roots, full_path)
    end
    roots
end

function pkg_extension_paths(project_root::AbstractString, project_facts)
    isempty(project_facts.extensions) && return String[]
    extension_root = joinpath(abspath(String(project_root)), "ext")
    isdir(extension_root) ? [extension_root] : String[]
end

function pkg_test_paths(
    project_root::AbstractString,
    project_facts,
    config::AspJuliaConfig,
)
    existing_configured_paths(project_root, config.test_dir_names)
end

function add_existing_path!(paths::Vector{String}, path::Union{Nothing,String})
    isnothing(path) && return paths
    ispath(path) || return paths
    normalized = normpath(path)
    any(existing -> same_path(existing, normalized), paths) || push!(paths, normalized)
    paths
end

function package_entry_source_root(
    project_root::AbstractString,
    package_name::Union{Nothing,String},
    entryfile::Union{Nothing,String},
)
    entry_path = expected_pkg_entry_path(project_root, package_name, entryfile)
    isnothing(entry_path) && return nothing
    source_root = dirname(entry_path)
    isdir(source_root) ? source_root : nothing
end

function expected_pkg_entry_path(
    project_root::AbstractString,
    package_name::Union{Nothing,String},
    entryfile::Union{Nothing,String},
)
    if !isnothing(entryfile)
        return isabspath(entryfile) ? normpath(entryfile) :
               normpath(joinpath(project_root, entryfile))
    end
    isnothing(package_name) && return nothing
    normpath(joinpath(project_root, "src", "$(package_name).jl"))
end

function same_path(left::AbstractString, right::AbstractString)
    normpath(left) == normpath(right)
end

function has_configured_path_explanation(
    explanations::Dict{String,String},
    project_root::AbstractString,
    path_name::AbstractString,
)
    full_path = normpath(joinpath(project_root, path_name))
    any(
        key -> haskey(explanations, key) && !isempty(strip(get(explanations, key, ""))),
        [String(path_name), slash_path(path_name), full_path, slash_path(full_path)],
    )
end

function existing_configured_paths(project_root::AbstractString, path_names::Vector{String})
    root = abspath(String(project_root))
    [joinpath(root, path_name) for path_name in path_names if ispath(joinpath(root, path_name))]
end

include("runner/project_toml.jl")

function project_search_start(project_path::AbstractString)
    path = abspath(String(project_path))
    isfile(path) ? dirname(path) : path
end

function package_entry_path(
    project_root::AbstractString,
    package_name::Union{Nothing,String},
    entryfile::Union{Nothing,String},
)
    if !isnothing(entryfile)
        path = isabspath(entryfile) ? normpath(entryfile) : normpath(joinpath(project_root, entryfile))
        return isfile(path) ? path : nothing
    end
    isnothing(package_name) && return nothing
    path = joinpath(project_root, "src", "$(package_name).jl")
    isfile(path) ? path : nothing
end

function discover_julia_files(paths::Vector{String}, config::AspJuliaConfig)
    files = Set{String}()
    for path in paths
        discover_julia_path!(files, path, config.ignored_dir_names)
    end
    sort!(collect(files))
end

function discover_julia_path!(files::Set{String}, path::AbstractString, ignored_dir_names::Set{String})
    should_ignore_path(path, ignored_dir_names) && return
    islink(path) && return
    if isfile(path)
        endswith(lowercase(path), ".jl") && push!(files, String(path))
        return
    end
    isdir(path) || return
    for entry in readdir(path; join=true)
        discover_julia_path!(files, entry, ignored_dir_names)
    end
end

function should_ignore_path(path::AbstractString, ignored_dir_names::Set{String})
    name = basename(path)
    name in ignored_dir_names
end
