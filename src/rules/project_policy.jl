function evaluate_project_policy_rules(
    scope::Union{Nothing,JuliaProjectHarnessScope},
    parsed_files::Vector{ParsedJuliaFile},
    config::AspJuliaConfig,
)
    isnothing(scope) && return AspJuliaFinding[]
    rules = rules_by_id()
    findings = AspJuliaFinding[]
    if !isnothing(scope.project_parse_error)
        push!(
            findings,
            finding_from_rule_typed(
                rules[JULIA_PROJ_R013],
                "Pkg could not read `$(scope.project_toml_path)`: $(scope.project_parse_error)",
                SourceLocation(scope.project_toml_path, 1, 0),
                "repair Project.toml until Pkg.Types.read_project can load it",
            ),
        )
        return findings
    end
    if isnothing(scope.package_name)
        push!(
            findings,
            finding_from_rule_typed(
                rules[JULIA_PROJ_R001],
                "Project.toml was not found or did not define a `name` field.",
                SourceLocation(scope.project_toml_path, 1, 0),
                "add a package name to Project.toml before running package policy",
            ),
        )
    elseif isnothing(scope.package_entry_path)
        push!(
            findings,
            finding_from_rule_typed(
                rules[JULIA_PROJ_R002],
                "Package `$(scope.package_name)` does not expose entry file `$(expected_entry_file(scope))`.",
                SourceLocation(scope.project_toml_path, 1, 0),
                "add the package entry module or configure an explicit source-scope exception",
            ),
        )
    else
        entry = findfirst(parsed -> parsed.report.path == scope.package_entry_path, parsed_files)
        if !isnothing(entry)
            parsed = parsed_files[entry]
            module_names = [mod.name for mod in parsed.syntax_facts.modules]
            if !(scope.package_name in module_names)
                push!(
                    findings,
                    finding_from_rule_typed(
                        rules[JULIA_PROJ_R007],
                        "`$(scope.package_entry_path)` does not declare module `$(scope.package_name)`.",
                        SourceLocation(scope.package_entry_path, 1, 0),
                        source_line(parsed.source, 1),
                        "declare the package module in the entry file so Pkg and syntax facts agree",
                    ),
                )
            end
        end
    end
    append!(findings, scope_explanation_findings(scope, config, rules))
    append!(findings, test_entrypoint_findings(scope, rules))
    append!(findings, thin_runtests_findings(scope, parsed_files, rules))
    append!(findings, source_rev_lock_findings(scope, rules))
    append!(findings, dependency_contract_findings(scope, rules))
    append!(findings, extension_dependency_findings(scope, rules))
    append!(findings, extension_entrypoint_findings(scope, rules))
    append!(findings, undeclared_import_findings(scope, parsed_files, rules))
    findings
end

function expected_entry_file(scope::JuliaProjectHarnessScope)
    if !isnothing(scope.project_entryfile)
        return scope.project_entryfile
    end
    isnothing(scope.package_name) ? "src/<PackageName>.jl" : "src/$(scope.package_name).jl"
end

function scope_explanation_findings(
    scope::JuliaProjectHarnessScope,
    config::AspJuliaConfig,
    rules::Dict{String,AspJuliaRule},
)
    findings = AspJuliaFinding[]
    append!(
        findings,
        custom_scope_explanation_findings(
            scope,
            config.source_dir_names,
            config.source_path_explanations,
            Set(["src"]),
            "source",
            rules,
        ),
    )
    if config.include_tests
        append!(
            findings,
            custom_scope_explanation_findings(
                scope,
                config.test_dir_names,
                config.test_path_explanations,
                Set(["test"]),
                "test",
                rules,
            ),
        )
    end
    append!(
        findings,
        conventional_scope_exclusion_findings(
            scope,
            config.source_dir_names,
            config.source_path_exclusion_explanations,
            "src",
            "source",
            rules,
        ),
    )
    append!(
        findings,
        conventional_scope_exclusion_findings(
            scope,
            config.include_tests ? config.test_dir_names : String[],
            config.test_path_exclusion_explanations,
            "test",
            "test",
            rules,
        ),
    )
    findings
end

function custom_scope_explanation_findings(
    scope::JuliaProjectHarnessScope,
    path_names::Vector{String},
    explanations::Dict{String,String},
    conventional_names::Set{String},
    label::AbstractString,
    rules::Dict{String,AspJuliaRule},
)
    findings = AspJuliaFinding[]
    for path_name in path_names
        path_name in conventional_names && continue
        full_path = joinpath(scope.project_root, path_name)
        ispath(full_path) || continue
        has_path_explanation(explanations, scope.project_root, path_name) && continue
        push!(
            findings,
            finding_from_rule_typed(
                rules[JULIA_PROJ_R005],
                "Configured $(label) scope `$(path_name)` exists but has no concrete explanation.",
                SourceLocation(scope.project_toml_path, 1, 0),
                "add a concrete scope explanation or use the conventional Julia path",
            ),
        )
    end
    findings
end

function conventional_scope_exclusion_findings(
    scope::JuliaProjectHarnessScope,
    configured_names::Vector{String},
    explanations::Dict{String,String},
    conventional_name::AbstractString,
    label::AbstractString,
    rules::Dict{String,AspJuliaRule},
)
    full_path = joinpath(scope.project_root, conventional_name)
    ispath(full_path) || return AspJuliaFinding[]
    label == "source" && !pkg_owns_conventional_source_scope(scope, full_path) &&
        return AspJuliaFinding[]
    conventional_scope_is_monitored(scope, full_path, label) && return AspJuliaFinding[]
    conventional_name in configured_names && return AspJuliaFinding[]
    has_path_explanation(explanations, scope.project_root, conventional_name) &&
        return AspJuliaFinding[]
    [
        finding_from_rule_typed(
            rules[JULIA_PROJ_R006],
            "Conventional Julia $(label) scope `$(conventional_name)` exists but is not monitored.",
            SourceLocation(scope.project_toml_path, 1, 0),
            "add a concrete exclusion explanation or restore the conventional scope",
        ),
    ]
end

function conventional_scope_is_monitored(
    scope::JuliaProjectHarnessScope,
    full_path::AbstractString,
    label::AbstractString,
)
    monitored_paths = label == "test" ? scope.test_paths : scope.source_paths
    any(path -> same_project_policy_path(path, full_path), monitored_paths)
end

function same_project_policy_path(left::AbstractString, right::AbstractString)
    normpath(left) == normpath(right)
end

function pkg_owns_conventional_source_scope(
    scope::JuliaProjectHarnessScope,
    conventional_path::AbstractString,
)
    if !isnothing(scope.project_entryfile)
        entry_path = isabspath(scope.project_entryfile) ? normpath(scope.project_entryfile) :
                     normpath(joinpath(scope.project_root, scope.project_entryfile))
        return project_policy_path_under(entry_path, conventional_path)
    end
    true
end

function project_policy_path_under(path::AbstractString, root::AbstractString)
    is_path_under(path, root)
end

function has_path_explanation(
    explanations::Dict{String,String},
    project_root::AbstractString,
    path_name::AbstractString,
)
    full_path = normpath(joinpath(project_root, path_name))
    any(
        key -> has_concrete_explanation(get(explanations, key, "")),
        [String(path_name), slash_path(path_name), full_path, slash_path(full_path)],
    )
end

function test_entrypoint_findings(
    scope::JuliaProjectHarnessScope,
    rules::Dict{String,AspJuliaRule},
)
    findings = AspJuliaFinding[]
    for test_path in scope.test_paths
        isdir(test_path) || continue
        entrypoint = joinpath(test_path, "runtests.jl")
        isfile(entrypoint) && continue
        push!(
            findings,
            finding_from_rule_typed(
                rules[JULIA_PROJ_R003],
                "Test scope `$(test_path)` exists, but `$(entrypoint)` is missing.",
                SourceLocation(entrypoint, 1, 0),
                "add test/runtests.jl so Pkg.test has a stable package test entrypoint",
            ),
        )
    end
    findings
end

function thin_runtests_findings(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
    rules::Dict{String,AspJuliaRule},
)
    findings = AspJuliaFinding[]
    for parsed in parsed_files
        parsed.report.is_valid || continue
        is_runtests_file(scope, parsed.report.path) || continue
        parsed.metrics.nonblank_line_count > MAX_THIN_RUNTESTS_NONBLANK_LINES || continue
        has_literal_includes(parsed) && continue
        push!(
            findings,
            finding_from_rule_typed(
                rules[JULIA_PROJ_R004],
                "`$(parsed.report.path)` has $(parsed.metrics.nonblank_line_count) nonblank lines and no literal included test files.",
                SourceLocation(parsed.report.path, 1, 0),
                source_line(parsed.source, 1),
                "move larger test bodies into included test files and keep runtests.jl as the aggregate",
            ),
        )
    end
    findings
end

function is_runtests_file(scope::JuliaProjectHarnessScope, path::AbstractString)
    any(test_path -> normpath(path) == normpath(joinpath(test_path, "runtests.jl")), scope.test_paths)
end

function has_literal_includes(parsed::ParsedJuliaFile)
    any(include -> include.is_literal, parsed.syntax_facts.includes)
end

function source_rev_lock_findings(
    scope::JuliaProjectHarnessScope,
    rules::Dict{String,AspJuliaRule},
)
    findings = AspJuliaFinding[]
    for (name, source) in sort!(collect(scope.sources); by = first)
        source_rev_is_locked(source) && continue
        rev = get(source, "rev", "")
        rev_summary = isempty(rev) ? "does not record a commit `rev`" :
                      "uses moving `rev = \"$(rev)\"`"
        push!(
            findings,
            finding_from_rule_typed(
                rules[JULIA_PROJ_R010],
                "Project source `$(name)` $(rev_summary).",
                SourceLocation(scope.project_toml_path, 1, 0),
                "lock the source dependency to a commit SHA from the intended branch",
            ),
        )
    end
    findings
end

function source_rev_is_locked(source::Dict{String,String})
    haskey(source, "path") && return true
    haskey(source, "url") || return true
    rev = get(source, "rev", "")
    is_commit_rev(rev)
end

function is_commit_rev(rev::AbstractString)
    length(rev) == 40 && all(
        character -> character in '0':'9' || character in 'a':'f' || character in 'A':'F',
        rev,
    )
end

function dependency_contract_findings(
    scope::JuliaProjectHarnessScope,
    rules::Dict{String,AspJuliaRule},
)
    stdlib_roots = julia_stdlib_import_roots()
    findings = AspJuliaFinding[]
    for (section, dependencies) in [
        ("deps", scope.direct_dependencies),
        ("weakdeps", scope.weak_dependencies),
    ]
        for name in sort!(collect(keys(dependencies)))
            name in stdlib_roots && continue
            haskey(scope.compat, name) && continue
            haskey(scope.sources, name) && continue
            push!(
                findings,
                finding_from_rule_typed(
                    rules[JULIA_PROJ_R009],
                    "Project dependency `$(name)` is declared in `[$(section)]` but has no `[compat]` entry or `[sources]` override.",
                    SourceLocation(scope.project_toml_path, 1, 0),
                    "add a compat bound or record the source-tracked dependency in Project.toml",
                ),
            )
        end
    end
    findings
end

function undeclared_import_findings(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
    rules::Dict{String,AspJuliaRule},
)
    findings = AspJuliaFinding[]
    stdlib_roots = julia_stdlib_import_roots()
    for parsed in parsed_files
        parsed.report.is_valid || continue
        allowed = allowed_import_roots(scope, parsed.report.path, stdlib_roots)
        for imported in parsed.syntax_facts.imports
            is_relative_import(imported) && continue
            dependency_root = imported_dependency_root(imported)
            dependency_root in allowed && continue
            push!(
                findings,
                finding_from_rule_typed(
                    rules[JULIA_PROJ_R008],
                    "`$(imported.expression)` imports `$(imported.root)`, but package root `$(dependency_root)` is not declared for this project scope.",
                    SourceLocation(parsed.report.path, imported.line, imported.column),
                    source_line(parsed.source, imported.line),
                    "add the package to Project.toml or make the import relative if it is project-local",
                ),
            )
        end
    end
    findings
end

function allowed_import_roots(
    scope::JuliaProjectHarnessScope,
    path::AbstractString,
    stdlib_roots::Set{String},
)
    allowed = union(
        Set(["Base", "Core", "Main"]),
        stdlib_roots,
        Set(keys(scope.direct_dependencies)),
    )
    !isnothing(scope.package_name) && push!(allowed, scope.package_name)
    union!(allowed, extension_import_roots(scope, path))
    if is_test_path(scope, path)
        union!(allowed, test_target_import_roots(scope))
    end
    allowed
end

function is_relative_import(imported::JuliaImportSyntax)
    expression = strip(imported.expression)
    startswith(expression, "using .") || startswith(expression, "import .")
end

function imported_dependency_root(imported::JuliaImportSyntax)
    first(split(imported.root, "."))
end

function is_test_path(scope::JuliaProjectHarnessScope, path::AbstractString)
    any(test_path -> is_path_under(path, test_path), scope.test_paths)
end

function julia_stdlib_import_roots()
    roots = Set{String}()
    for stdlib_dir::String in readdir(Sys.STDLIB; join = true)
        project_path::String = joinpath(stdlib_dir, "Project.toml")
        isfile(project_path) || continue
        project::Dict{String,Any} = TOML.parsefile(project_path)
        raw_name::Any = get(project, "name", nothing)
        raw_name isa String || continue
        name::String = raw_name
        push!(roots, name)
    end
    roots
end
