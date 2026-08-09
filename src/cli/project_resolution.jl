const JULIA_PROJECT_RESOLUTION_REQUEST_SCHEMA =
    "agent.semantic-protocols.provider-project-resolution-request"
const JULIA_PROJECT_RESOLUTION_RESPONSE_SCHEMA =
    "agent.semantic-protocols.provider-project-resolution-response"
const JULIA_PROJECT_RESOLUTION_SCHEMA = "agent.semantic-protocols.project-resolution"
const JULIA_PACKAGE_GRAPH_SCHEMA = "agent.semantic-protocols.language-package-graph"
const JULIA_PROJECT_RESOLUTION_PARSER = "julia.pkg-project-toml"

struct JuliaProjectResolutionError <: Exception
    message::String
    reason_kind::String
    next_action::String
end

struct JuliaProjectDocument
    name::Union{Nothing,String}
    entryfile::Union{Nothing,String}
    deps::Dict{String,String}
    weakdeps::Dict{String,String}
    extras::Dict{String,String}
    extensions::Dict{String,Vector{String}}
    targets::Dict{String,Vector{String}}
    compat::Dict{String,String}
    workspace_projects::Vector{String}
end

const JuliaCandidateGeneration = @NamedTuple begin
    algorithm::String
    digest::String
    authorities::Vector{String}
end
const JuliaProjectResolutionPolicyExclusion = @NamedTuple begin
    path::String
    authority::String
    reasonKind::String
end
const JuliaProjectResolutionCollectionScope = @NamedTuple begin
    kind::String
    ownerPaths::Vector{String}
end
const JuliaProjectResolutionRequest = @NamedTuple begin
    schemaId::String
    schemaVersion::String
    languageId::String
    providerId::String
    candidateBase::String
    candidateGeneration::JuliaCandidateGeneration
    collectionScope::JuliaProjectResolutionCollectionScope
    candidatePaths::Vector{String}
    policyExclusions::Vector{JuliaProjectResolutionPolicyExclusion}
end

const JuliaProjectFile = @NamedTuple begin
    path::String
    kind::String
    digest::String
end
const JuliaProjectTarget = @NamedTuple begin
    targetId::String
    kind::String
    name::String
    explicit::Bool
    sourceRoots::Vector{String}
    entrypoints::Vector{String}
    generatedRoots::Vector{String}
end
const JuliaProjectPackage = @NamedTuple begin
    packageId::String
    name::String
    manifestPath::String
    root::String
    workspaceMember::Bool
    targets::Vector{JuliaProjectTarget}
end
const JuliaProjectDependency = @NamedTuple begin
    fromPackageId::String
    packageName::String
    kind::String
    resolution::String
    toPackageId::String
    versionRequirement::String
end
const JuliaInternalDependencyEdge = @NamedTuple begin
    fromPackageId::String
    toPackageId::String
    kind::String
end
const JuliaExternalDependency = @NamedTuple begin
    dependencyId::String
    name::String
    kind::String
    requested::String
end
const JuliaProjectUnresolved = @NamedTuple begin
    state::String
    path::String
    reasonKind::String
end
const JuliaResolvedSourceScope = @NamedTuple begin
    scopeId::String
    packageId::String
    targetId::String
    roots::Vector{String}
    explicitPaths::Vector{String}
    extensions::Vector{String}
    includeAuthority::String
    exclusions::Vector{@NamedTuple{prefix::String,authority::String}}
    classifications::Vector{String}
end
const JuliaLanguagePackageGraph = @NamedTuple begin
    schemaId::String
    schemaVersion::String
    languageId::String
    providerId::String
    projectEntry::String
    parserId::String
    manifests::Vector{JuliaProjectFile}
    lockfiles::Vector{JuliaProjectFile}
    packages::Vector{JuliaProjectPackage}
    internalDependencyEdges::Vector{JuliaInternalDependencyEdge}
    externalDependencies::Vector{JuliaExternalDependency}
    unresolved::Vector{JuliaProjectUnresolved}
end
const JuliaProjectResolutionMetrics = @NamedTuple begin
    parsedManifestCount::Int
    parsedLockfileCount::Int
    affectedPackageCount::Int
    fullWorkspaceReads::Int
    fullManifestReparses::Int
    dbOpens::Int
    elapsedMicros::Int
end
const JuliaProjectConflict = @NamedTuple begin
    path::String
    includeAuthority::String
    excludeAuthority::String
    reasonKind::String
end
const JuliaProjectResolution = @NamedTuple begin
    schemaId::String
    schemaVersion::String
    state::String
    completeness::String
    languageId::String
    providerId::String
    parserId::String
    candidateGenerationDigest::String
    projectEntry::String
    packageGraph::JuliaLanguagePackageGraph
    sourceScopes::Vector{JuliaResolvedSourceScope}
    conflicts::Vector{JuliaProjectConflict}
    metrics::JuliaProjectResolutionMetrics
end
const JuliaProjectResolutionSuccess = @NamedTuple begin
    schemaId::String
    schemaVersion::String
    languageId::String
    providerId::String
    state::String
    scope::JuliaProjectResolution
end
const JuliaProjectResolutionFailureDetail = @NamedTuple begin
    reasonKind::String
    message::String
    nextAction::String
end
const JuliaProjectResolutionFailure = @NamedTuple begin
    schemaId::String
    schemaVersion::String
    languageId::String
    providerId::String
    state::String
    failure::JuliaProjectResolutionFailureDetail
end
function run_julia_project_resolution_cli(input::IO, out::IO)
    response = try
        request = julia_project_resolution_request_json(read(input, String))
        julia_project_resolution_response(julia_project_resolution(request))
    catch error
        if error isa JuliaProjectResolutionError
            typed_error = error::JuliaProjectResolutionError
            julia_project_resolution_failure(
                typed_error.message;
                reason_kind=typed_error.reason_kind,
                next_action=typed_error.next_action,
            )
        else
            julia_project_resolution_failure(
                "project-resolution request or Julia project entry is invalid";
                reason_kind="project-entry-invalid",
                next_action="send-valid-project-resolution-request",
            )
        end
    end
    JSON.json(out, response)
    print(out, '\n')
    return 0
end

function julia_project_resolution(request::JuliaProjectResolutionRequest)
    julia_validate_project_resolution_request(request)
    workspace_root = abspath(pwd())
    candidate_paths = julia_project_resolution_candidate_paths(request.candidatePaths)
    manifests = filter(path -> basename(path) == "Project.toml", candidate_paths)
    "Project.toml" in manifests || throw(
        JuliaProjectResolutionError(
            "provider project entry is required: tracked Project.toml",
            "provider-project-entry-required",
            "add-tracked-julia-project-entry",
        ),
    )

    entry_manifest = "Project.toml"
    entry_project = julia_project_document(
        julia_candidate_absolute_path(workspace_root, entry_manifest),
    )
    selected_manifests =
        julia_selected_project_manifests(entry_manifest, entry_project, manifests)
    documents = Dict{String,JuliaProjectDocument}(
        path => path == entry_manifest ?
                entry_project :
                julia_project_document(
            julia_candidate_absolute_path(workspace_root, path),
        ) for path in selected_manifests
    )
    packages = JuliaProjectPackage[]
    for path in selected_manifests
        package =
            julia_project_resolution_package(path, documents[path], candidate_paths)
        isnothing(package) || push!(packages, package)
    end
    isempty(packages) && throw(
        JuliaProjectResolutionError(
            "candidate Project.toml files declare no Julia packages",
            "project-entry-invalid",
            "declare-julia-package-name",
        ),
    )

    dependencies =
        julia_project_resolution_dependencies(packages, documents, selected_manifests)
    scopes, unresolved = julia_project_resolution_scopes(packages)
    package_graph = JuliaLanguagePackageGraph((
        schemaId=JULIA_PACKAGE_GRAPH_SCHEMA,
        schemaVersion="1",
        languageId="julia",
        providerId="julia-lang-project-harness",
        projectEntry=entry_manifest,
        parserId=JULIA_PROJECT_RESOLUTION_PARSER,
        manifests=JuliaProjectFile[
            julia_project_file(workspace_root, path, "julia-project") for
            path in selected_manifests
        ],
        lockfiles=JuliaProjectFile[
            julia_project_file(workspace_root, path, "julia-manifest") for
            path in candidate_paths if
            basename(path) == "Manifest.toml" &&
            any(
                manifest -> dirname(path) == dirname(manifest),
                selected_manifests,
            )
        ],
        packages=packages,
        internalDependencyEdges=JuliaInternalDependencyEdge[
            (
                fromPackageId=dependency.fromPackageId,
                toPackageId=dependency.toPackageId,
                kind=dependency.kind,
            ) for dependency in dependencies if dependency.resolution == "internal"
        ],
        externalDependencies=JuliaExternalDependency[
            (
                dependencyId="julia-dependency-" * julia_stable_id(
                    dependency.fromPackageId * ":" * dependency.packageName,
                ),
                name=dependency.packageName,
                kind=dependency.kind,
                requested=dependency.versionRequirement,
            ) for dependency in dependencies if dependency.resolution == "external"
        ],
        unresolved=unresolved,
    ))
    return JuliaProjectResolution((
        schemaId=JULIA_PROJECT_RESOLUTION_SCHEMA,
        schemaVersion="1",
        state="resolved",
        completeness=isempty(unresolved) ? "exact" : "partial",
        languageId="julia",
        providerId="julia-lang-project-harness",
        parserId=JULIA_PROJECT_RESOLUTION_PARSER,
        candidateGenerationDigest=request.candidateGeneration.digest,
        projectEntry=entry_manifest,
        packageGraph=package_graph,
        sourceScopes=scopes,
        conflicts=JuliaProjectConflict[],
        metrics=(
            parsedManifestCount=length(documents),
            parsedLockfileCount=
                count(path -> basename(path) == "Manifest.toml", candidate_paths),
            affectedPackageCount=length(packages),
            fullWorkspaceReads=0,
            fullManifestReparses=0,
            dbOpens=0,
            elapsedMicros=0,
        ),
    ))
end

include("project_resolution/model.jl")
