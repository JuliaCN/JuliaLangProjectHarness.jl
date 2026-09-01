@testset "self apply policy" begin
    root = pkgdir(AspJulia)

    profile = assert_julia_project_harness_test_profile_clean(root; advice_io=nothing)
    report = profile.report

    @test AspJulia.is_clean(report)
    @test isempty(AspJulia.advisory_findings(report))
    @test !isempty(profile.task_index.records)
    @test !isempty(profile.profile_index.candidates)
    @test render_julia_project_harness(report) == "[ok] julia\n"
end
