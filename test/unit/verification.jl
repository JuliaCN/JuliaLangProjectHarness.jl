function write_verification_project(root::AbstractString)
    write(
        joinpath(root, "Project.toml"),
        """
        name = "VerifyExample"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"

        [deps]
        JuliaLangProjectHarness = "67259778-f152-405a-bc38-ee6219bce977"

        [weakdeps]
        JSON = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"

        [extensions]
        VerifyJSONExt = ["JSON"]

        [compat]
        JSON = "1"
        JuliaLangProjectHarness = "0.1"

        [extras]
        Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

        [targets]
        test = ["Test"]
        """,
    )
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "test"))
    mkpath(joinpath(root, "ext"))
    write(
        joinpath(root, "src", "VerifyExample.jl"),
        """
        module VerifyExample
        export run
        \"\"\"Run the verification fixture value.\"\"\"
        run(value) = value
        end
        """,
    )
    write(
        joinpath(root, "test", "runtests.jl"),
        """
        using JuliaLangProjectHarness
        using Test

        @test true
        assert_julia_project_harness_test_profile_clean(dirname(@__DIR__))
        """,
    )
    write(joinpath(root, "ext", "VerifyJSONExt.jl"), "module VerifyJSONExt\nend\n")
end

function write_responsibility_project(root::AbstractString)
    write(
        joinpath(root, "Project.toml"),
        """
        name = "ResponsibilityExample"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"

        [deps]
        HTTP = "cd3eb016-35fb-5094-929b-558a96fad6f3"
        JSON = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"

        [compat]
        HTTP = "1"
        JSON = "1"
        """,
    )
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "ResponsibilityExample.jl"),
        """
        module ResponsibilityExample
        using HTTP
        using JSON
        using SHA
        using LinearAlgebra
        export fetch_config

        \"\"\"Fetch and decode a remote config payload.\"\"\"
        function fetch_config(urls)
            digests = mapreduce(url -> bytes2hex(sha256(url)), vcat, urls)
            response = HTTP.get(first(urls))
            data = open("config.json") do io
                JSON.parse(read(io, String))
            end
            return norm(digests), response, data
        end
        end
        """,
    )
end

function write_algorithm_shape_project(root::AbstractString)
    write(
        joinpath(root, "Project.toml"),
        """
        name = "ShapeExample"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"
        """,
    )
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "ShapeExample.jl"),
        """
        module ShapeExample
        function scan_values(rows)
            total = 0
            for row in rows
                for value in row
                    if value > 0
                        total += value
                    end
                    if isodd(value)
                        total += 1
                    end
                end
            end
            total
        end
        end
        """,
    )
end

function write_documenter_project(root::AbstractString)
    write(
        joinpath(root, "Project.toml"),
        """
        name = "DocsExample"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"

        [compat]
        Documenter = "1"
        """,
    )
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "test"))
    mkpath(joinpath(root, "docs", "src"))
    write(
        joinpath(root, "src", "DocsExample.jl"),
        """
        module DocsExample
        export run
        \"\"\"Run the docs fixture value.\"\"\"
        run(value) = value
        end
        """,
    )
    write(joinpath(root, "test", "runtests.jl"), "using Test\n@test true\n")
    write(
        joinpath(root, "docs", "Project.toml"),
        """
        [deps]
        Documenter = "e30172f5-a6a5-5a46-863b-614d45cd2de4"
        DocsExample = "11111111-1111-1111-1111-111111111111"

        [compat]
        Documenter = "1"
        """,
    )
    write(
        joinpath(root, "docs", "make.jl"),
        """
        using Documenter
        using DocsExample

        makedocs(sitename = "DocsExample")
        """,
    )
    write(joinpath(root, "docs", "src", "index.md"), "# DocsExample\n")
end

function write_moshi_extension_verification_project(root::AbstractString)
    write(
        joinpath(root, "Project.toml"),
        """
        name = "MoshiVerifyExample"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"

        [weakdeps]
        Moshi = "2e0e35c7-a2e4-4343-998d-7ef72827ed2d"

        [extensions]
        VerifyMoshiExt = "Moshi"

        [compat]
        Moshi = "0.3"

        [extras]
        Moshi = "2e0e35c7-a2e4-4343-998d-7ef72827ed2d"
        Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

        [targets]
        test = ["Moshi", "Test"]
        """,
    )
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "test"))
    mkpath(joinpath(root, "ext"))
    write(
        joinpath(root, "src", "MoshiVerifyExample.jl"),
        """
        module MoshiVerifyExample
        end
        """,
    )
    write(joinpath(root, "test", "runtests.jl"), "using Test\n@test true\n")
    write(joinpath(root, "ext", "VerifyMoshiExt.jl"), "module VerifyMoshiExt\nend\n")
end

function write_benchmark_verification_project(root::AbstractString)
    write(
        joinpath(root, "Project.toml"),
        """
        name = "BenchmarkExample"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"
        """,
    )
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "test", "perf"))
    mkpath(joinpath(root, "benchmark"))
    write(
        joinpath(root, "src", "BenchmarkExample.jl"),
        """
        module BenchmarkExample
        function scan_values(rows)
            total = 0
            for row in rows
                for value in row
                    if value > 0
                        total += value
                    end
                    if isodd(value)
                        total += 1
                    end
                end
            end
            total
        end
        end
        """,
    )
    write(joinpath(root, "test", "runtests.jl"), "using Test\n@test true\n")
    write(
        joinpath(root, "benchmark", "Project.toml"),
        """
        [deps]
        BenchmarkTools = "6e4b80f9-dd2c-5a6d-8f14-7f3c1d9e8f4a"

        [compat]
        BenchmarkTools = "1"
        """,
    )
    write(joinpath(root, "benchmark", "runbenchmarks.jl"), "println(\"benchmark\")\n")
    write(joinpath(root, "test", "perf", "runtests.jl"), "println(\"strict perf\")\n")
end

function write_example_verification_project(root::AbstractString)
    write(
        joinpath(root, "Project.toml"),
        """
        name = "ExampleVerification"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"
        """,
    )
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "examples"))
    write(
        joinpath(root, "src", "ExampleVerification.jl"),
        """
        module ExampleVerification
        run(value) = value
        end
        """,
    )
    write(
        joinpath(root, "examples", "Project.toml"),
        """
        [deps]
        ExampleVerification = "11111111-1111-1111-1111-111111111111"

        [sources]
        ExampleVerification = {path = ".."}
        """,
    )
    write(joinpath(root, "examples", "runexamples.jl"), "using ExampleVerification\nrun(1)\n")
end


include("verification/task_index.jl")
include("verification/profile.jl")
include("verification/receipts.jl")
