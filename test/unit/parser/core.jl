@testset "parser" begin
    temp = mktempdir()
    source = joinpath(temp, "valid.jl")
    write(source, "module Valid\nexport run\nrun() = 1\nend\n")

    parsed = parse_julia_file(source)

    @test parsed.report.is_valid
    @test isnothing(parsed.report.parse_error)
    @test parsed.metrics.nonblank_line_count == 4
    @test parsed.syntax_facts.has_syntax_tree
end

@testset "parser namespace and api facts" begin
    temp = mktempdir()
    source = joinpath(temp, "entry.jl")
    write(
        source,
        """
        baremodule Example
        export run, Config
        public internal_api
        using JSON
        using JSON: read, write
        import Base: show
        import Dates
        end
        """,
    )

    parsed = parse_julia_file(source)

    @test length(parsed.syntax_facts.modules) == 1
    @test only(parsed.syntax_facts.modules).name == "Example"
    @test only(parsed.syntax_facts.modules).is_bare
    @test [(item.kind, item.names) for item in parsed.syntax_facts.exports] == [
        ("export", ["run", "Config"]),
        ("public", ["internal_api"]),
    ]
    @test [(item.kind, item.root, item.names) for item in parsed.syntax_facts.imports] == [
        ("using", "JSON", String[]),
        ("using", "JSON", ["read", "write"]),
        ("import", "Base", ["show"]),
        ("import", "Dates", String[]),
    ]
end

@testset "parser function facts" begin
    temp = mktempdir()
    source = joinpath(temp, "methods.jl")
    write(
        source,
        """
        function run(x, y::Int, force::Bool, dry_run=false; verbose=false, mode::AbstractString="fast")
            x + y
        end
        short(a, b=1, c::String="x", enabled::Core.Bool=true) = a
        Base.show(io::IO, value::Thing) = print(io, value)
        macro demo(x)
            x
        end
        """,
    )

    parsed = parse_julia_file(source)

    @test [(item.kind, item.name, item.terminal_name) for item in parsed.syntax_facts.functions] == [
        ("function", "run", "run"),
        ("function", "short", "short"),
        ("function", "Base.show", "show"),
        ("macro", "demo", "demo"),
    ]
    @test parsed.syntax_facts.functions[1].positional_args == ["x", "y", "force", "dry_run"]
    @test parsed.syntax_facts.functions[1].bool_positional_args == ["force", "dry_run"]
    @test parsed.syntax_facts.functions[1].stringly_domain_args == ["mode"]
    @test isempty(parsed.syntax_facts.functions[1].stringly_branch_literals)
    @test parsed.syntax_facts.functions[1].keyword_args == ["verbose", "mode"]
    @test [
        (
            arg.owner_name,
            arg.name,
            arg.type_annotation,
            arg.is_keyword,
            arg.has_default,
            arg.is_bool,
            arg.is_stringly_domain,
        ) for arg in parsed.syntax_facts.functions[1].argument_facts
    ] == [
        ("run", "x", nothing, false, false, false, false),
        ("run", "y", "Int", false, false, false, false),
        ("run", "force", "Bool", false, false, true, false),
        ("run", "dry_run", nothing, false, true, true, false),
        ("run", "verbose", nothing, true, true, true, false),
        ("run", "mode", "AbstractString", true, true, false, true),
    ]
    @test parsed.syntax_facts.functions[2].positional_args == ["a", "b", "c", "enabled"]
    @test parsed.syntax_facts.functions[2].bool_positional_args == ["enabled"]
    @test isempty(parsed.syntax_facts.functions[2].stringly_domain_args)
    @test isempty(parsed.syntax_facts.functions[2].stringly_branch_literals)
    @test parsed.syntax_facts.functions[3].positional_args == ["io", "value"]
    @test parsed.syntax_facts.functions[4].positional_args == ["x"]
end

@testset "parser function dispatch facts" begin
    temp = mktempdir()
    source = joinpath(temp, "dispatch.jl")
    write(
        source,
        """
        function run(x::T, y::Vector{T}; mode::Symbol=:fast)::T where {T<:Real}
            x
        end
        short(x::Int)::String = string(x)
        Base.show(io::IO, value::Thing{T}) where {T} = print(io, value)
        """,
    )

    parsed = parse_julia_file(source)

    @test [(item.name, item.return_type, item.where_parameters) for item in parsed.syntax_facts.functions] == [
        ("run", "T", ["T<:Real"]),
        ("short", "String", String[]),
        ("Base.show", nothing, ["T"]),
    ]
    @test parsed.syntax_facts.functions[1].typed_positional_args == ["x::T", "y::Vector{T}"]
    @test parsed.syntax_facts.functions[2].typed_positional_args == ["x::Int"]
    @test parsed.syntax_facts.functions[3].typed_positional_args == ["io::IO", "value::Thing{T}"]
    @test [(call.name, call.terminal_name) for call in parsed.syntax_facts.calls] == [
        ("string", "string"),
        ("print", "print"),
    ]
end

@testset "parser binding facts" begin
    temp = mktempdir()
    source = joinpath(temp, "bindings.jl")
    write(
        source,
        """
        CACHE = Dict{String,Int}()
        const DEFAULT_LIMIT = 8
        const TYPED_LIMIT::Int = 13
        global CACHE = Dict()
        function local_work()
            local seen = Set{String}()
            scratch = Int[]
        end
        """,
    )

    parsed = parse_julia_file(source)

    @test [
        (
            item.kind,
            item.name,
            item.terminal_name,
            item.type_annotation,
            item.initializer_kind,
            item.initializer_name,
            item.is_constant,
        ) for item in parsed.syntax_facts.bindings
    ] == [
        ("binding", "CACHE", "CACHE", nothing, "call", "Dict", false),
        ("const", "DEFAULT_LIMIT", "DEFAULT_LIMIT", nothing, "Integer", nothing, true),
        ("const", "TYPED_LIMIT", "TYPED_LIMIT", "Int", "Integer", nothing, true),
        ("global", "CACHE", "CACHE", nothing, "call", "Dict", false),
    ]
end
