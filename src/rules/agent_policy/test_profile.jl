const JULIA_HARNESS_TEST_PROFILE_CALL_NAMES = Set([
    "assert_julia_project_harness_test_profile_clean",
])

function verification_test_profile_findings(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
    rules::Dict{String,JuliaHarnessRule},
)
    has_harness_dependency(scope) || return JuliaHarnessFinding[]
    has_test_profile_hook(scope, parsed_files) && return JuliaHarnessFinding[]
    owner_path = preferred_test_owner_path(scope)
    [
        finding_from_rule_typed(
            rules[AGENT_JL_R014],
            "Project `$(something(scope.package_name, "<unnamed>"))` depends on JuliaLangProjectHarness, but its test files do not call `assert_julia_project_harness_test_profile_clean`.",
            SourceLocation(owner_path, 1, 0),
            test_profile_owner_source_line(owner_path, parsed_files),
            "add a compact harness testset that calls `assert_julia_project_harness_test_profile_clean(pkgdir(<PackageModule>))`",
        ),
    ]
end

function has_test_profile_hook(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
)
    any(parsed_files) do parsed
        parsed.report.is_valid || return false
        is_test_path(scope, parsed.report.path) || return false
        any(
            call -> call.terminal_name in JULIA_HARNESS_TEST_PROFILE_CALL_NAMES,
            parsed.syntax_facts.calls,
        )
    end
end

function test_profile_owner_source_line(
    owner_path::AbstractString,
    parsed_files::Vector{ParsedJuliaFile},
)
    owner = findfirst(parsed -> parsed.report.path == owner_path, parsed_files)
    isnothing(owner) && return nothing
    source_line(parsed_files[owner].source, 1)
end
