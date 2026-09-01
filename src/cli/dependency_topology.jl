const JULIA_DEPENDENCY_TOPOLOGY_VALUE_OPTIONS = Set([
    "--workspace",
    "--asp-provider-id",
    "--asp-parser-identity-digest",
    "--asp-query-pack-digest",
    "--source-snapshot-envelope",
])

struct JuliaDependencyTopologyDependencyFields
    dependencyName::String
    manifestPath::String
end

struct JuliaDependencyTopologyVersionFields
    version::String
end

struct JuliaDependencyTopologyDependencyNode
    kind::String
    fields::JuliaDependencyTopologyDependencyFields
    id::String
    value::String
    path::String
end

struct JuliaDependencyTopologyVersionNode
    kind::String
    fields::JuliaDependencyTopologyVersionFields
    id::String
    value::String
end

const JuliaDependencyTopologyNode =
    Union{JuliaDependencyTopologyDependencyNode,JuliaDependencyTopologyVersionNode}

struct JuliaDependencyTopologyEdge
    source::String
    relation::String
    target::String
end

struct JuliaDependencyTopologyGraph
    nodes::Vector{JuliaDependencyTopologyNode}
    edges::Vector{JuliaDependencyTopologyEdge}
end

struct JuliaDependencyTopologyPacket
    fingerprint::String
    packetKind::String
    graph::JuliaDependencyTopologyGraph
end

function julia_dependency_topology_cli_args(args::Vector{String})
    workspace = "."
    json = false
    index = 1
    while index <= length(args)
        option = args[index]
        if option == "--json"
            json = true
            index += 1
        elseif option in JULIA_DEPENDENCY_TOPOLOGY_VALUE_OPTIONS
            index == length(args) && error("missing value for dependency-topology option: $(option)")
            option == "--workspace" && (workspace = args[index + 1])
            index += 2
        else
            error("unknown dependency-topology option: $(option)")
        end
    end
    json || error("search dependency-topology requires --json")
    abspath(workspace)
end

function julia_manifest_dependency_versions(manifest_path::String)::Dict{String,String}
    isfile(manifest_path) || return Dict{String,String}()
    document = TOML.parsefile(manifest_path)
    dependencies_value = get(document, "deps", nothing)
    dependencies_value === nothing && return Dict{String,String}()
    dependencies_value isa Dict{String,Any} ||
        throw(ArgumentError("Manifest.toml deps must be a TOML table"))
    versions = Dict{String,String}()
    for (dependency_name, entries_value) in dependencies_value
        entries_value isa Vector{Any} ||
            throw(ArgumentError("Manifest.toml deps.$dependency_name must be an array"))
        isempty(entries_value) && continue
        entry_value = first(entries_value)
        entry_value isa Dict{String,Any} ||
            throw(ArgumentError("Manifest.toml deps.$dependency_name entry must be a table"))
        version_value = get(entry_value, "version", nothing)
        version_value === nothing && continue
        version_value isa String ||
            throw(ArgumentError("Manifest.toml deps.$dependency_name.version must be a string"))
        versions[dependency_name] = version_value
    end
    return versions
end

function julia_dependency_topology_packet(project_root::AbstractString)
    root = abspath(String(project_root))
    project_path = joinpath(root, "Project.toml")
    isfile(project_path) || error("dependency-topology requires Project.toml: $(project_path)")

    project = julia_project_document(project_path)
    declared = project.deps

    manifest_path = joinpath(root, "Manifest.toml")
    manifest_versions = julia_manifest_dependency_versions(manifest_path)
    nodes = JuliaDependencyTopologyNode[]
    edges = JuliaDependencyTopologyEdge[]
    fingerprint_rows = String[]

    dependency_names = String[]
    sizehint!(dependency_names, length(declared))
    for dependency_name in keys(declared)
        push!(dependency_names, String(dependency_name))
    end
    sort!(dependency_names)

    for dependency_name in dependency_names
        dependency_id = "dependency:$(dependency_name)"
        push!(nodes, JuliaDependencyTopologyDependencyNode(
            "dependency",
            JuliaDependencyTopologyDependencyFields(dependency_name, "Manifest.toml"),
            dependency_id,
            dependency_name,
            "Project.toml",
        ))

        version = get(manifest_versions, dependency_name, nothing)
        push!(fingerprint_rows, "$(dependency_name)\t$(something(version, ""))")
        isnothing(version) && continue

        version_id = "dependency-version:$(dependency_name)@$(version)"
        push!(nodes, JuliaDependencyTopologyVersionNode(
            "dependency-version",
            JuliaDependencyTopologyVersionFields(version),
            version_id,
            version,
        ))
        push!(edges, JuliaDependencyTopologyEdge(
            dependency_id,
            "version_locked",
            version_id,
        ))
    end

    fingerprint_material = join(fingerprint_rows, "\n")
    JuliaDependencyTopologyPacket(
        "sha256:$(bytes2hex(SHA.sha256(fingerprint_material)))",
        "dependency-topology",
        JuliaDependencyTopologyGraph(nodes, edges),
    )
end

run_julia_dependency_topology_cli(args::Vector{String}; out::IO=stdout) =
    run_julia_dependency_topology_cli(args, out)

function write_julia_dependency_topology_json(
    out::IO,
    packet::JuliaDependencyTopologyPacket,
)
    print(out, "{\"fingerprint\":")
    JSON.json(out, packet.fingerprint)
    print(out, ",\"packetKind\":")
    JSON.json(out, packet.packetKind)
    print(out, ",\"graph\":{\"nodes\":[")
    for (index, node) in enumerate(packet.graph.nodes)
        index == 1 || print(out, ',')
        if node isa JuliaDependencyTopologyDependencyNode
            JSON.json(out, node)
        else
            JSON.json(out, node::JuliaDependencyTopologyVersionNode)
        end
    end
    print(out, "],\"edges\":")
    JSON.json(out, packet.graph.edges)
    print(out, "}}")
end

function run_julia_dependency_topology_cli(args::Vector{String}, out::IO)
    project_root = julia_dependency_topology_cli_args(args)
    write_julia_dependency_topology_json(
        out,
        julia_dependency_topology_packet(project_root),
    )
    print(out, '\n')
    0
end
