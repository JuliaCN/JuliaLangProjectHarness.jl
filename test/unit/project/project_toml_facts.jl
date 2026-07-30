@testset "direct TOML project facts preserve package semantics" begin
    root = mktempdir()
    local_dependency_root = joinpath(root, "LocalDependency")
    mkpath(local_dependency_root)
    write(
        joinpath(local_dependency_root, "Project.toml"),
        """
        name = "LocalDependency"
        uuid = "22222222-2222-2222-2222-222222222222"
        version = "0.1.0"
        """,
    )
    write(
        joinpath(root, "Project.toml"),
        """
        name = "Example"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"
        entryfile = "lib/ExampleEntry.jl"

        [deps]
        JSON = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"

        [weakdeps]
        Moshi = "2e0e35c7-a2e4-4343-998d-7ef72827ed2d"

        [extras]
        Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

        [targets]
        test = ["Test", "Moshi"]

        [compat]
        JSON = "1"
        Moshi = "0.3"

        [sources]
        LocalDependency = {path = "LocalDependency"}

        [extensions]
        ExampleMoshiExt = "Moshi"
        ExampleManyExt = ["Moshi", "JSON"]

        [workspace]
        projects = ["packages/First", "packages/Second"]
        """,
    )

    facts = JuliaLangProjectHarness.parse_project_toml_facts(root)

    @test isnothing(facts.parse_error)
    @test facts.package_name == "Example"
    @test facts.package_uuid == "11111111-1111-1111-1111-111111111111"
    @test facts.entryfile == "lib/ExampleEntry.jl"
    @test facts.direct_dependencies ==
          Dict("JSON" => "682c06a0-de6a-54ab-a142-c8b1cf79cde6")
    @test facts.weak_dependencies ==
          Dict("Moshi" => "2e0e35c7-a2e4-4343-998d-7ef72827ed2d")
    @test facts.extra_dependencies ==
          Dict("Test" => "8dfed614-e22c-5e08-85e1-65c5234f0b40")
    @test facts.targets == Dict("test" => ["Test", "Moshi"])
    @test facts.compat == Dict("JSON" => "1", "Moshi" => "0.3")
    @test facts.sources == Dict(
        "LocalDependency" => Dict("path" => "LocalDependency"),
    )
    @test facts.extensions == Dict(
        "ExampleMoshiExt" => ["Moshi"],
        "ExampleManyExt" => ["Moshi", "JSON"],
    )
    @test facts.workspace_projects == ["packages/First", "packages/Second"]
    @test facts.source_dependency_projects == ["LocalDependency"]
end

@testset "direct TOML project facts reject invalid workspace project shapes" begin
    root = mktempdir()
    write(
        joinpath(root, "Project.toml"),
        """
        name = "Example"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"

        [workspace]
        projects = "packages/First"
        """,
    )

    facts = JuliaLangProjectHarness.parse_project_toml_facts(root)

    @test facts.parse_error == "invalid Project.toml field `workspace.projects`"
    @test isempty(facts.workspace_projects)
end
