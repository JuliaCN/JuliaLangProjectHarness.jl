@testset "parser docstring facts" begin
    temp = mktempdir()
    source = joinpath(temp, "docs.jl")
    write(
        source,
        """
        \"\"\"Package module docs.\"\"\"
        module Docs
        \"\"\"Run a value.

        Keeps the first paragraph searchable.
        \"\"\"
        run(value) = value
        \"\"\"A named payload.\"\"\"
        struct Payload
            value::Int
        end
        \"\"\"Public constant.\"\"\"
        const DEFAULT_PAYLOAD = Payload(1)
        \"\"\"Shared lookup.\"\"\"
        LOOKUP = Dict{String,Payload}()
        \"\"\"Shared cache.\"\"\"
        global CACHE = Dict()
        end
        """,
    )

    parsed = parse_julia_file(source)

    @test [
        (item.target_kind, item.target_name, item.text) for item in
        parsed.syntax_facts.docstrings
    ] == [
        ("module", "Docs", "Package module docs."),
        (
            "function",
            "run",
            "Run a value.\n\nKeeps the first paragraph searchable.\n",
        ),
        ("struct", "Payload", "A named payload."),
        ("const", "DEFAULT_PAYLOAD", "Public constant."),
        ("binding", "LOOKUP", "Shared lookup."),
        ("global", "CACHE", "Shared cache."),
    ]
end

@testset "parser identifier facts" begin
    temp = mktempdir()
    source = joinpath(temp, "identifiers.jl")
    write(
        source,
        """
        module Identifiers
        struct Payload
            value::Int
        end
        run(value::Payload) = JSON.parse(string(value))
        end
        """,
    )

    parsed = parse_julia_file(source)
    identifiers = parsed.syntax_facts.identifiers

    @test any(
        item -> item.name == "Identifiers" &&
                item.parent_kind == "module" &&
                item.line == 1,
        identifiers,
    )
    @test any(
        item -> item.name == "Payload" && item.parent_kind == "struct",
        identifiers,
    )
    @test any(
        item -> item.name == "JSON" &&
                item.parent_kind == "." &&
                item.parent_expression == "JSON.parse",
        identifiers,
    )
    @test any(
        item -> item.name == "value" && item.parent_kind == "call",
        identifiers,
    )
end

@testset "parser type facts" begin
    temp = mktempdir()
    source = joinpath(temp, "types.jl")
    write(
        source,
        """
        abstract type AbstractThing end
        struct Thing{T} <: AbstractThing
            value::T
            name
            mode::Symbol = :ready
        end
        Base.@kwdef mutable struct Box
            item::Thing
            enabled::Bool = true
        end
        primitive type Word32 <: Unsigned 32 end
        """,
    )

    parsed = parse_julia_file(source)

    @test [(item.kind, item.name, item.parameters, item.supertype) for item in parsed.syntax_facts.types] == [
        ("abstract", "AbstractThing", String[], nothing),
        ("struct", "Thing", ["T"], "AbstractThing"),
        ("struct", "Box", String[], nothing),
        ("primitive", "Word32", String[], "Unsigned"),
    ]
    @test parsed.syntax_facts.types[2].fields == ["value", "name", "mode"]
    @test parsed.syntax_facts.types[2].typed_fields == ["value::T", "mode::Symbol"]
    @test parsed.syntax_facts.types[2].defaulted_fields == ["mode"]
    @test [
        (field.owner_name, field.name, field.type_annotation, field.has_default) for field in
        parsed.syntax_facts.types[2].field_facts
    ] == [
        ("Thing", "value", "T", false),
        ("Thing", "name", nothing, false),
        ("Thing", "mode", "Symbol", true),
    ]
    @test !parsed.syntax_facts.types[2].is_mutable
    @test parsed.syntax_facts.types[3].fields == ["item", "enabled"]
    @test parsed.syntax_facts.types[3].typed_fields == ["item::Thing", "enabled::Bool"]
    @test parsed.syntax_facts.types[3].defaulted_fields == ["enabled"]
    @test [
        (field.owner_name, field.name, field.type_annotation, field.has_default) for field in
        parsed.syntax_facts.types[3].field_facts
    ] == [
        ("Box", "item", "Thing", false),
        ("Box", "enabled", "Bool", true),
    ]
    @test parsed.syntax_facts.types[3].is_mutable
end
