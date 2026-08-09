function julia_validate_project_resolution_request(request::JuliaProjectResolutionRequest)
    request.schemaId == JULIA_PROJECT_RESOLUTION_REQUEST_SCHEMA ||
        throw(ArgumentError("project-resolution request schema must be v1"))
    request.schemaVersion == "1" ||
        throw(ArgumentError("project-resolution request schema must be v1"))
    request.languageId == "julia" ||
        throw(ArgumentError("project-resolution language identity must be julia"))
    request.providerId == "julia-lang-project-harness" ||
        throw(ArgumentError("project-resolution provider identity does not match"))
    request.candidateBase == "." ||
        throw(ArgumentError("project-resolution request requires candidateBase=."))
    isempty(request.candidateGeneration.digest) &&
        throw(ArgumentError("project-resolution requires candidateGeneration.digest"))
    if request.collectionScope.kind == "complete-generation"
        isempty(request.collectionScope.ownerPaths) || throw(
            ArgumentError("complete-generation collectionScope must not include ownerPaths"),
        )
    elseif request.collectionScope.kind == "explicit-owners"
        isempty(request.collectionScope.ownerPaths) && throw(
            ArgumentError("explicit-owners collectionScope requires ownerPaths"),
        )
        julia_project_resolution_candidate_paths(request.collectionScope.ownerPaths)
    else
        throw(ArgumentError("project-resolution collectionScope is invalid"))
    end
    return nothing
end

function julia_project_resolution_candidate_paths(candidates::Vector{String})
    paths = String[]
    for candidate in candidates
        path = replace(normpath(candidate), '\\' => '/')
        (isabspath(path) || path == ".." || startswith(path, "../")) &&
            throw(ArgumentError("repository candidate must be workspace-relative: $path"))
        push!(paths, path)
    end
    return sort!(unique!(paths))
end

function julia_candidate_absolute_path(workspace_root::String, candidate::String)
    return abspath(workspace_root, candidate)
end

function julia_selected_project_manifests(
    entry_manifest::String,
    project::JuliaProjectDocument,
    manifests::Vector{String},
)
    entry_root = dirname(entry_manifest)
    selected = Set{String}([entry_manifest])
    for project_path in project.workspace_projects
        manifest = replace(
            normpath(joinpath(entry_root, project_path, "Project.toml")),
            '\\' => '/',
        )
        manifest in manifests || throw(
            ArgumentError("workspace project is absent from Git candidates: $manifest"),
        )
        push!(selected, manifest)
    end
    return sort!(collect(selected))
end

function julia_project_resolution_package(
    manifest_path::String,
    project::JuliaProjectDocument,
    candidates::Vector{String},
)
    isnothing(project.name) && return nothing
    name = project.name::String
    root = julia_project_resolution_root(manifest_path)
    package_id = "julia-package-" * julia_stable_id(manifest_path * ":" * name)
    targets = JuliaProjectTarget[]

    library_relative =
        isnothing(project.entryfile) ? joinpath("src", name * ".jl") : project.entryfile::String
    library_path = julia_join_project_path(root, library_relative)
    if library_path in candidates
        push!(
            targets,
            julia_project_resolution_target(
                package_id,
                name,
                "library",
                [library_path],
                !isnothing(project.entryfile),
            ),
        )
    end
    for extension_name in sort!(collect(keys(project.extensions)))
        extension_path =
            julia_join_project_path(root, "ext", extension_name * ".jl")
        extension_path in candidates || continue
        push!(
            targets,
            julia_project_resolution_target(
                package_id,
                extension_name,
                "extension",
                [extension_path],
                true,
            ),
        )
    end
    test_path = julia_join_project_path(root, "test", "runtests.jl")
    if haskey(project.targets, "test") && test_path in candidates
        push!(
            targets,
            julia_project_resolution_target(package_id, "test", "test", [test_path], true),
        )
    end
    return JuliaProjectPackage((
        packageId=package_id,
        name=name,
        manifestPath=manifest_path,
        root=isempty(root) ? "." : root,
        workspaceMember=true,
        targets=targets,
    ))
end

function julia_project_resolution_target(
    package_id::String,
    name::String,
    kind::String,
    paths::Vector{String},
    explicit::Bool,
)
    return JuliaProjectTarget((
        targetId="julia-target-" * julia_stable_id(package_id * ":" * kind * ":" * name),
        kind=kind,
        name=name,
        explicit,
        sourceRoots=sort!(unique!(dirname.(paths))),
        entrypoints=paths,
        generatedRoots=String[],
    ))
end

function julia_project_resolution_dependencies(
    packages::Vector{JuliaProjectPackage},
    documents::Dict{String,JuliaProjectDocument},
    manifests::Vector{String},
)
    package_by_manifest =
        Dict{String,JuliaProjectPackage}(package.manifestPath => package for package in packages)
    package_by_name =
        Dict{String,JuliaProjectPackage}(package.name => package for package in packages)
    dependencies = JuliaProjectDependency[]
    for manifest in manifests
        haskey(package_by_manifest, manifest) || continue
        package = package_by_manifest[manifest]
        project = documents[manifest]
        for (kind, table) in (
            ("normal", project.deps),
            ("normal", project.weakdeps),
            ("dev", project.extras),
        )
            for name in sort!(collect(keys(table)))
                internal = haskey(package_by_name, name)
                compat = get(project.compat, name, "*")
                push!(
                    dependencies,
                    (
                        fromPackageId=package.packageId,
                        packageName=name,
                        kind=kind,
                        resolution=internal ? "internal" : "external",
                        toPackageId=internal ? package_by_name[name].packageId : "",
                        versionRequirement=compat,
                    ),
                )
            end
        end
    end
    return dependencies
end

function julia_project_string_table(
    document::Dict{String,Any},
    key::String,
)::Dict{String,String}
    value = get(document, key, nothing)
    value === nothing && return Dict{String,String}()
    value isa Dict{String,Any} ||
        throw(ArgumentError("$key must be a TOML table"))
    result = Dict{String,String}()
    for (name, item) in value
        item isa String ||
            throw(ArgumentError("$key.$name must be a string"))
        result[name] = item
    end
    return result
end

function julia_project_string_list_table(
    document::Dict{String,Any},
    key::String,
)::Dict{String,Vector{String}}
    value = get(document, key, nothing)
    value === nothing && return Dict{String,Vector{String}}()
    value isa Dict{String,Any} ||
        throw(ArgumentError("$key must be a TOML table"))
    result = Dict{String,Vector{String}}()
    for (name, item) in value
        if item isa String
            result[name] = [item]
        elseif item isa Vector{String}
            result[name] = copy(item)
        elseif item isa Vector{Any}
            entries = String[]
            for entry in item
                entry isa String ||
                    throw(ArgumentError("$key.$name entries must be strings"))
                push!(entries, entry)
            end
            result[name] = entries
        else
            throw(ArgumentError("$key.$name must be a string or string array"))
        end
    end
    return result
end

function julia_project_workspace_projects(
    document::Dict{String,Any},
)::Vector{String}
    workspace = get(document, "workspace", nothing)
    workspace === nothing && return String[]
    workspace isa Dict{String,Any} ||
        throw(ArgumentError("workspace must be a TOML table"))
    projects = get(workspace, "projects", nothing)
    projects === nothing && return String[]
    if projects isa Vector{String}
        return copy(projects)
    end
    projects isa Vector{Any} ||
        throw(ArgumentError("workspace.projects must be an array"))
    result = String[]
    for project in projects
        project isa String ||
            throw(ArgumentError("workspace.projects entries must be strings"))
        push!(result, project)
    end
    return result
end

function julia_project_document(path::String)::JuliaProjectDocument
    document = TOML.parsefile(path)
    name_value = get(document, "name", nothing)
    name_value === nothing || name_value isa String ||
        throw(ArgumentError("name must be a string"))
    entryfile_value = get(document, "entryfile", nothing)
    entryfile_value === nothing || entryfile_value isa String ||
        throw(ArgumentError("entryfile must be a string"))
    return JuliaProjectDocument(
        name_value,
        entryfile_value,
        julia_project_string_table(document, "deps"),
        julia_project_string_table(document, "weakdeps"),
        julia_project_string_table(document, "extras"),
        julia_project_string_list_table(document, "extensions"),
        julia_project_string_list_table(document, "targets"),
        julia_project_string_table(document, "compat"),
        julia_project_workspace_projects(document),
    )
end

function julia_project_resolution_scopes(packages::Vector{JuliaProjectPackage})
    scopes = JuliaResolvedSourceScope[]
    unresolved = JuliaProjectUnresolved[]
    for package in packages
        if isempty(package.targets)
            push!(
                unresolved,
                (
                    state="target-source-missing",
                    path=package.manifestPath,
                    reasonKind="package-source-scope-missing",
                ),
            )
        end
        for target in package.targets
            push!(
                scopes,
                (
                    scopeId="julia-source-scope-" * julia_stable_id(
                        package.packageId * ":" * target.targetId,
                    ),
                    packageId=package.packageId,
                    targetId=target.targetId,
                    roots=target.sourceRoots,
                    explicitPaths=target.explicit ? target.entrypoints : String[],
                    extensions=[".jl"],
                    includeAuthority=target.explicit ? "manifest-explicit" : "package-manager",
                    exclusions=@NamedTuple{prefix::String,authority::String}[],
                    classifications=target.kind == "test" ? ["test"] : ["production"],
                ),
            )
        end
    end
    return scopes, unresolved
end

julia_project_resolution_root(manifest::String) =
    dirname(manifest) == "." ? "" : replace(dirname(manifest), '\\' => '/')

function julia_project_file(workspace_root::String, path::String, kind::String)
    return JuliaProjectFile((
        path=path,
        kind=kind,
        digest="sha256:" * bytes2hex(
            SHA.sha256(read(julia_candidate_absolute_path(workspace_root, path))),
        ),
    ))
end

function julia_join_project_path(root::String, parts::String...)
    path = joinpath(root, parts...)
    return replace(normpath(path), '\\' => '/')
end

julia_stable_id(value::String) = bytes2hex(SHA.sha256(value))[1:16]

function julia_project_resolution_response(resolution::JuliaProjectResolution)
    return JuliaProjectResolutionSuccess((
        schemaId=JULIA_PROJECT_RESOLUTION_RESPONSE_SCHEMA,
        schemaVersion="1",
        languageId="julia",
        providerId="julia-lang-project-harness",
        state="resolved",
        scope=resolution,
    ))
end

function julia_project_resolution_failure(
    message::String;
    reason_kind::String,
    next_action::String,
)
    return JuliaProjectResolutionFailure((
        schemaId=JULIA_PROJECT_RESOLUTION_RESPONSE_SCHEMA,
        schemaVersion="1",
        languageId="julia",
        providerId="julia-lang-project-harness",
        state="failed",
        failure=(
            reasonKind=reason_kind,
            message=message,
            nextAction=next_action,
        ),
    ))
end
