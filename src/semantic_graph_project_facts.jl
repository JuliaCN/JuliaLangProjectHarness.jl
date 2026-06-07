"""Project-level package/build/test facts for semantic graph packets."""

const JULIA_SEMANTIC_GRAPH_DEPENDENCY_LIMIT = 64
const JULIA_SEMANTIC_GRAPH_TEST_LIMIT = 64

function julia_semantic_graph_project_payload(project_root::AbstractString)
    project = julia_semantic_graph_project_fact(project_root)
    isnothing(project) && return (nodes=Dict{String,Any}[], edges=Dict{String,String}[])
    nodes = Dict{String,Any}[
        julia_semantic_graph_package_node(project),
        julia_semantic_graph_build_node(project),
    ]
    edges = Dict{String,String}[
        Dict(
            "source" => julia_semantic_graph_package_id(project["packageName"]),
            "target" => julia_semantic_graph_build_id(project["packageName"]),
            "relation" => "builds",
        ),
    ]
    for dependency in project["dependencies"]
        dependency_id = julia_semantic_graph_dependency_id(project["packageName"], dependency)
        push!(nodes, julia_semantic_graph_dependency_node(project, dependency, dependency_id))
        push!(
            edges,
            Dict(
                "source" => julia_semantic_graph_package_id(project["packageName"]),
                "target" => dependency_id,
                "relation" => "depends_on",
            ),
        )
    end
    for test_fact in project["tests"]
        test_id = julia_semantic_graph_test_id(project["packageName"], test_fact)
        push!(nodes, julia_semantic_graph_test_node(project, test_fact, test_id))
        push!(
            edges,
            Dict(
                "source" => julia_semantic_graph_build_id(project["packageName"]),
                "target" => test_id,
                "relation" => "tests",
            ),
        )
        push!(
            edges,
            Dict(
                "source" => test_id,
                "target" => julia_semantic_graph_package_id(project["packageName"]),
                "relation" => "belongs_to",
            ),
        )
    end
    (nodes=nodes, edges=edges)
end

function julia_semantic_graph_project_fact(project_root::AbstractString)
    root = abspath(String(project_root))
    manifest_path = joinpath(root, "Project.toml")
    isfile(manifest_path) || return nothing
    parsed = try
        TOML.parsefile(manifest_path)
    catch
        return nothing
    end
    package_name = get(parsed, "name", nothing)
    isa(package_name, AbstractString) && !isempty(strip(package_name)) || return nothing
    manifest_display = asp_project_path(manifest_path, root)
    Dict{String,Any}(
        "packageName" => strip(String(package_name)),
        "manifestPath" => manifest_display,
        "dependencies" => julia_semantic_graph_dependency_facts(parsed, manifest_display),
        "tests" => julia_semantic_graph_test_facts(root),
    )
end

function julia_semantic_graph_dependency_facts(
    parsed::AbstractDict,
    manifest_path::AbstractString,
)
    compat = get(parsed, "compat", Dict{String,Any}())
    facts = Dict{String,Any}[]
    append!(
        facts,
        julia_semantic_graph_dependency_table_facts(
            get(parsed, "deps", Dict{String,Any}()),
            "normal",
            manifest_path,
            compat,
        ),
    )
    append!(
        facts,
        julia_semantic_graph_dependency_table_facts(
            get(parsed, "extras", Dict{String,Any}()),
            "dev",
            manifest_path,
            compat,
        ),
    )
    append!(
        facts,
        julia_semantic_graph_dependency_table_facts(
            get(parsed, "weakdeps", Dict{String,Any}()),
            "optional",
            manifest_path,
            compat,
        ),
    )
    sort!(facts; by=fact -> "$(fact["dependencyKind"]):$(fact["dependencyName"])")
    facts[1:min(length(facts), JULIA_SEMANTIC_GRAPH_DEPENDENCY_LIMIT)]
end

function julia_semantic_graph_dependency_table_facts(
    table,
    dependency_kind::AbstractString,
    manifest_path::AbstractString,
    compat,
)
    isa(table, AbstractDict) || return Dict{String,Any}[]
    facts = Dict{String,Any}[]
    for dependency_name in sort(collect(keys(table)))
        isa(dependency_name, AbstractString) || continue
        fact = Dict{String,Any}(
            "dependencyName" => String(dependency_name),
            "dependencyPackageName" => String(dependency_name),
            "dependencyKind" => String(dependency_kind),
            "manifestPath" => String(manifest_path),
        )
        if isa(compat, AbstractDict) && haskey(compat, dependency_name)
            version_req = compat[dependency_name]
            isa(version_req, AbstractString) && (fact["versionReq"] = String(version_req))
        end
        push!(facts, fact)
    end
    facts
end

function julia_semantic_graph_test_facts(root::AbstractString)
    test_root = joinpath(String(root), "test")
    isdir(test_root) || return Dict{String,Any}[]
    config = default_julia_harness_config()
    facts = Dict{String,Any}[]
    for path in discover_julia_files([test_root], config)
        parsed = parse_julia_file(path)
        parsed.report.is_valid || continue
        display_path = asp_project_path(path, root)
        push!(
            facts,
            Dict{String,Any}(
                "path" => display_path,
                "name" => splitext(basename(display_path))[1],
                "functionCount" => length(parsed.syntax_facts.tests),
            ),
        )
        length(facts) >= JULIA_SEMANTIC_GRAPH_TEST_LIMIT && break
    end
    facts
end

function julia_semantic_graph_package_node(project::Dict{String,Any})
    manifest_path = project["manifestPath"]
    Dict{String,Any}(
        "id" => julia_semantic_graph_package_id(project["packageName"]),
        "kind" => "package",
        "role" => "julia-project",
        "value" => project["packageName"],
        "action" => "package",
        "path" => manifest_path,
        "ownerPath" => manifest_path,
        "startLine" => 1,
        "endLine" => 1,
        "locator" => "$(manifest_path):1:1",
        "matchText" => project["packageName"],
        "fields" => Dict{String,Any}(
            "languageId" => JULIA_INDEX_EXPORT_LANGUAGE_ID,
            "providerId" => JULIA_INDEX_EXPORT_PROVIDER_ID,
            "semanticFactKind" => "package",
            "provenance" => "parser",
            "confidence" => "exact",
            "freshness" => "fresh",
            "packageName" => project["packageName"],
            "manifestPath" => manifest_path,
        ),
    )
end

function julia_semantic_graph_build_node(project::Dict{String,Any})
    manifest_path = project["manifestPath"]
    command = julia_semantic_graph_test_command()
    Dict{String,Any}(
        "id" => julia_semantic_graph_build_id(project["packageName"]),
        "kind" => "build",
        "role" => "pkg-test",
        "value" => command,
        "action" => "build",
        "path" => manifest_path,
        "ownerPath" => manifest_path,
        "startLine" => 1,
        "endLine" => 1,
        "locator" => "$(manifest_path):1:1",
        "matchText" => command,
        "fields" => Dict{String,Any}(
            "languageId" => JULIA_INDEX_EXPORT_LANGUAGE_ID,
            "providerId" => JULIA_INDEX_EXPORT_PROVIDER_ID,
            "semanticFactKind" => "build",
            "provenance" => "build",
            "confidence" => "exact",
            "freshness" => "fresh",
            "packageName" => project["packageName"],
            "manifestPath" => manifest_path,
            "tool" => "Pkg",
            "command" => command,
        ),
    )
end

function julia_semantic_graph_dependency_node(
    project::Dict{String,Any},
    dependency::Dict{String,Any},
    dependency_id::AbstractString,
)
    fields = Dict{String,Any}(
        "languageId" => JULIA_INDEX_EXPORT_LANGUAGE_ID,
        "providerId" => JULIA_INDEX_EXPORT_PROVIDER_ID,
        "semanticFactKind" => "dependency",
        "provenance" => "parser",
        "confidence" => "exact",
        "freshness" => "fresh",
        "packageName" => project["packageName"],
        "manifestPath" => dependency["manifestPath"],
        "dependencyName" => dependency["dependencyName"],
        "dependencyPackageName" => dependency["dependencyPackageName"],
        "dependencyKind" => dependency["dependencyKind"],
    )
    haskey(dependency, "versionReq") && (fields["versionReq"] = dependency["versionReq"])
    Dict{String,Any}(
        "id" => String(dependency_id),
        "kind" => "dependency",
        "role" => dependency["dependencyKind"],
        "value" => dependency["dependencyPackageName"],
        "action" => "deps",
        "path" => dependency["manifestPath"],
        "ownerPath" => dependency["manifestPath"],
        "startLine" => 1,
        "endLine" => 1,
        "locator" => "$(dependency["manifestPath"]):1:1",
        "matchText" => dependency["dependencyPackageName"],
        "fields" => fields,
    )
end

function julia_semantic_graph_test_node(
    project::Dict{String,Any},
    test_fact::Dict{String,Any},
    test_id::AbstractString,
)
    Dict{String,Any}(
        "id" => String(test_id),
        "kind" => "test",
        "role" => "pkg-test-target",
        "value" => test_fact["name"],
        "action" => "tests",
        "path" => test_fact["path"],
        "ownerPath" => test_fact["path"],
        "startLine" => 1,
        "endLine" => 1,
        "locator" => "$(test_fact["path"]):1:1",
        "matchText" => test_fact["name"],
        "fields" => Dict{String,Any}(
            "languageId" => JULIA_INDEX_EXPORT_LANGUAGE_ID,
            "providerId" => JULIA_INDEX_EXPORT_PROVIDER_ID,
            "semanticFactKind" => "test",
            "provenance" => "test",
            "confidence" => "exact",
            "freshness" => "fresh",
            "packageName" => project["packageName"],
            "testName" => test_fact["name"],
            "testPath" => test_fact["path"],
            "functionCount" => test_fact["functionCount"],
            "command" => julia_semantic_graph_test_command(),
        ),
    )
end

function julia_semantic_graph_package_id(package_name::AbstractString)
    julia_semantic_graph_stable_id("package", package_name)
end

function julia_semantic_graph_build_id(package_name::AbstractString)
    julia_semantic_graph_stable_id("build", "$(julia_semantic_graph_test_command()):$(package_name)")
end

function julia_semantic_graph_dependency_id(
    package_name::AbstractString,
    dependency::Dict{String,Any},
)
    julia_semantic_graph_stable_id(
        "dependency",
        "$(package_name):$(dependency["dependencyKind"]):$(dependency["dependencyPackageName"])",
    )
end

function julia_semantic_graph_test_id(
    package_name::AbstractString,
    test_fact::Dict{String,Any},
)
    julia_semantic_graph_stable_id("test", "$(package_name):$(test_fact["path"])")
end

function julia_semantic_graph_test_command()
    "julia --project=. -e 'using Pkg; Pkg.test()'"
end
