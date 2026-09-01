@testset "Moshi extension is inactive until Moshi loads" begin
    @test isempty(moshi_extension_capabilities())
    @test isnothing(Base.get_extension(AspJulia, :AspJuliaMoshiExt))
end

if isnothing(Base.find_package("Moshi"))
    @test_skip "Moshi extension activation requires the test extra environment"
else
    @eval using Moshi

    @testset "Moshi extension activates through package weakdep" begin
        @test !isnothing(Base.get_extension(AspJulia, :AspJuliaMoshiExt))
        capabilities = moshi_extension_capabilities()

        @test "syntax: native JuliaSyntax facts for Moshi @data/@match/@derive" in capabilities
        @test "domain-model: typed domain carriers for stringly branch dispatch in source deps or optional extensions" in capabilities
        @test "search: agent search and snapshots for Moshi modeling forms" in capabilities
    end

    @testset "Moshi extension capability names stay compact for agent surfaces" begin
        @test AspJulia.moshi_extension_capability_names() ==
              ["syntax", "domain-model", "search"]
    end
end
