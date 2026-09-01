function extension_entrypoint_findings(
    scope::JuliaProjectHarnessScope,
    rules::Dict{String,AspJuliaRule},
)
    findings = AspJuliaFinding[]
    for name in sort!(collect(keys(scope.extensions)))
        any(isfile, extension_entrypoint_candidates(scope.project_root, name)) && continue
        push!(
            findings,
            finding_from_rule_typed(
                rules[JULIA_PROJ_R011],
                "Project extension `$(name)` is declared but no extension entrypoint exists.",
                SourceLocation(scope.project_toml_path, 1, 0),
                "add the extension module file under ext/ using the Pkg extension name",
            ),
        )
    end
    findings
end

function extension_dependency_findings(
    scope::JuliaProjectHarnessScope,
    rules::Dict{String,AspJuliaRule},
)
    stdlib_roots = julia_stdlib_import_roots()
    declared = union(Set(keys(scope.direct_dependencies)), Set(keys(scope.weak_dependencies)), stdlib_roots)
    findings = AspJuliaFinding[]
    for (extension_name, dependencies) in sort!(collect(scope.extensions))
        for dependency in sort!(copy(dependencies))
            dependency in declared && continue
            push!(
                findings,
                finding_from_rule_typed(
                    rules[JULIA_PROJ_R012],
                    "Project extension `$(extension_name)` is triggered by `$(dependency)`, but `$(dependency)` is not declared in `[weakdeps]` or `[deps]`.",
                    SourceLocation(scope.project_toml_path, 1, 0),
                    "declare the extension trigger as a weak dependency or regular dependency",
                ),
            )
        end
    end
    findings
end

function extension_entrypoint_candidates(project_root::AbstractString, name::AbstractString)
    extension_root = joinpath(project_root, "ext")
    [
        joinpath(extension_root, "$(name).jl"),
        joinpath(extension_root, String(name), "$(name).jl"),
    ]
end

function extension_import_roots(scope::JuliaProjectHarnessScope, path::AbstractString)
    extension_name = extension_name_for_path(scope, path)
    isnothing(extension_name) && return Set{String}()
    Set(get(scope.extensions, extension_name, String[]))
end

function extension_name_for_path(scope::JuliaProjectHarnessScope, path::AbstractString)
    for name in keys(scope.extensions)
        if any(
            candidate -> normpath(path) == normpath(candidate),
            extension_entrypoint_candidates(scope.project_root, name),
        )
            return name
        end
        extension_dir = joinpath(scope.project_root, "ext", name)
        is_path_under(path, extension_dir) && return name
    end
    nothing
end
