const JULIA_SYNTAX_PACK_ID = "julia.syntax"
const JULIA_PROJECT_POLICY_PACK_ID = "julia.project_policy"
const JULIA_MODULARITY_PACK_ID = "julia.modularity"
const JULIA_AGENT_POLICY_PACK_ID = "julia.agent_policy"
const JULIA_SYN_R001 = "JULIA-SYN-R001"
const JULIA_PROJ_R001 = "JULIA-AGENT-PROJECT-001"
const JULIA_PROJ_R002 = "JULIA-AGENT-PROJECT-002"
const JULIA_PROJ_R003 = "JULIA-AGENT-PROJECT-003"
const JULIA_PROJ_R004 = "JULIA-AGENT-PROJECT-004"
const JULIA_PROJ_R005 = "JULIA-AGENT-PROJECT-005"
const JULIA_PROJ_R006 = "JULIA-AGENT-PROJECT-006"
const JULIA_PROJ_R007 = "JULIA-AGENT-PROJECT-007"
const JULIA_PROJ_R008 = "JULIA-AGENT-PROJECT-008"
const JULIA_PROJ_R009 = "JULIA-AGENT-PROJECT-009"
const JULIA_PROJ_R010 = "JULIA-AGENT-PROJECT-010"
const JULIA_PROJ_R011 = "JULIA-AGENT-PROJECT-011"
const JULIA_PROJ_R012 = "JULIA-AGENT-PROJECT-012"
const JULIA_PROJ_R013 = "JULIA-AGENT-PROJECT-013"
const JULIA_PROJ_R014 = "JULIA-AGENT-PROJECT-014"
const JULIA_MOD_R001 = "JULIA-MOD-R001"
const JULIA_MOD_R002 = "JULIA-MOD-R002"
const JULIA_MOD_R003 = "JULIA-MOD-R003"
const JULIA_MOD_R004 = "JULIA-MOD-R004"
const JULIA_MOD_R005 = "JULIA-MOD-R005"
const JULIA_MOD_R006 = "JULIA-MOD-R006"
const JULIA_MOD_R007 = "JULIA-MOD-R007"
const AGENT_JL_R001 = "AGENT-JL-R001"
const AGENT_JL_R002 = "AGENT-JL-R002"
const AGENT_JL_R003 = "AGENT-JL-R003"
const AGENT_JL_R004 = "AGENT-JL-R004"
const AGENT_JL_R005 = "AGENT-JL-R005"
const AGENT_JL_R006 = "AGENT-JL-R006"
const AGENT_JL_R007 = "AGENT-JL-R007"
const AGENT_JL_R008 = "AGENT-JL-R008"
const AGENT_JL_R009 = "AGENT-JL-R009"
const AGENT_JL_R010 = "AGENT-JL-R010"
const AGENT_JL_R011 = "AGENT-JL-R011"
const AGENT_JL_R012 = "AGENT-JL-R012"
const AGENT_JL_R013 = "AGENT-JL-R013"
const AGENT_JL_R014 = "AGENT-JL-R014"
const AGENT_JL_R015 = "AGENT-JL-R015"
const AGENT_JL_R016 = "AGENT-JL-R016"
const AGENT_JL_R017 = "AGENT-JL-R017"
const AGENT_JL_R018 = "AGENT-JL-R018"
const AGENT_JL_R019 = "AGENT-JL-R019"
const AGENT_JL_R020 = "AGENT-JL-R020"
const AGENT_JL_R021 = "AGENT-JL-R021"
const AGENT_JL_R022 = "AGENT-JL-R022"
const AGENT_JL_R023 = "AGENT-JL-R023"
const AGENT_JL_R024 = "AGENT-JL-R024"
const AGENT_JL_R025 = "AGENT-JL-R025"
const AGENT_JL_R026 = "AGENT-JL-R026"
const AGENT_JL_R027 = "AGENT-JL-R027"
const AGENT_JL_R028 = "AGENT-JL-R028"
const AGENT_JL_R029 = "AGENT-JL-R029"
const AGENT_JL_R030 = "AGENT-JL-R030"
const AGENT_JL_R031 = "AGENT-JL-R031"

const GENERIC_SOURCE_OWNER_SEGMENTS = Set(["common", "helper", "helpers", "misc", "util", "utils"])
const MAX_ENTRY_FACADE_NONBLANK_LINES = 120
const MAX_SOURCE_FILE_NONBLANK_LINES = 400
const MAX_THIN_RUNTESTS_NONBLANK_LINES = 80

"""Return rule pack metadata for the Julia project harness."""
function julia_rule_pack_descriptors()
    [
        RulePackDescriptor(JULIA_SYNTAX_PACK_ID, "1", ["julia", "syntax"], :blocking),
        RulePackDescriptor(
            JULIA_PROJECT_POLICY_PACK_ID,
            "1",
            ["julia", "project-policy", "tests"],
            :blocking,
        ),
        RulePackDescriptor(JULIA_MODULARITY_PACK_ID, "1", ["julia", "modularity"], :blocking),
        RulePackDescriptor(JULIA_AGENT_POLICY_PACK_ID, "1", ["julia", "agent-policy"], :advisory),
    ]
end

function labels(label::AbstractString)
    Dict("domain" => String(label))
end

"""Return Julia syntax parse rules backed by JuliaSyntax.jl."""
function julia_syntax_rules()
    [
        JuliaHarnessRule(
            JULIA_SYN_R001,
            JULIA_SYNTAX_PACK_ID,
            Error,
            "Julia source does not parse",
            "Julia source files must parse through `JuliaSyntax.jl` before project policy runs.",
            labels("syntax"),
        ),
    ]
end

"""Return Project.toml and package-layout policy rules."""
julia_project_policy_rules() = [
    JuliaHarnessRule(
        JULIA_PROJ_R001,
        JULIA_PROJECT_POLICY_PACK_ID,
        Warning,
        "Project.toml lacks a package name",
        "Package project runners must parse `Project.toml` and find a concrete package name before package policy runs.",
        labels("project-policy"),
    ),
    JuliaHarnessRule(
        JULIA_PROJ_R002,
        JULIA_PROJECT_POLICY_PACK_ID,
        Warning,
        "Package entry module is missing",
        "Julia packages should expose a parser-stable entry file at `src/<PackageName>.jl`, unless project config records a reason.",
        labels("project-policy"),
    ),
    JuliaHarnessRule(
        JULIA_PROJ_R003,
        JULIA_PROJECT_POLICY_PACK_ID,
        Warning,
        "Pkg.test entrypoint is missing",
        "Julia package test scopes should mount the `Pkg.test` entrypoint at `test/runtests.jl`.",
        labels("project-policy"),
    ),
    JuliaHarnessRule(
        JULIA_PROJ_R004,
        JULIA_PROJECT_POLICY_PACK_ID,
        Warning,
        "Pkg.test entrypoint is no longer a thin aggregate",
        "`test/runtests.jl` should stay a compact `Pkg.test` aggregate and move larger test bodies into included test files.",
        labels("project-policy"),
    ),
    JuliaHarnessRule(
        JULIA_PROJ_R005,
        JULIA_PROJECT_POLICY_PACK_ID,
        Warning,
        "Custom source or test scope lacks explanation",
        "Custom Julia source or test scope paths must carry a concrete project-local explanation.",
        labels("project-policy"),
    ),
    JuliaHarnessRule(
        JULIA_PROJ_R006,
        JULIA_PROJECT_POLICY_PACK_ID,
        Warning,
        "Conventional source or test scope was excluded",
        "Excluding conventional Julia `src` or `test` scopes must carry a concrete project-local explanation.",
        labels("project-policy"),
    ),
    JuliaHarnessRule(
        JULIA_PROJ_R007,
        JULIA_PROJECT_POLICY_PACK_ID,
        Warning,
        "Package entry file lacks package module declaration",
        "The package entry file should declare a top-level module matching the `Project.toml` package name.",
        labels("project-policy"),
    ),
    JuliaHarnessRule(
        JULIA_PROJ_R008,
        JULIA_PROJECT_POLICY_PACK_ID,
        Warning,
        "Imported package is missing from Project.toml",
        "External Julia package imports should be declared in `Project.toml` as deps, weakdeps, or test extras according to their source scope.",
        labels("project-policy"),
    ),
    JuliaHarnessRule(
        JULIA_PROJ_R009,
        JULIA_PROJECT_POLICY_PACK_ID,
        Warning,
        "Project dependency lacks compat or source override",
        "Registry Julia dependencies should carry `[compat]` bounds; source-tracked dependencies should be recorded in `[sources]`.",
        labels("project-policy"),
    ),
    JuliaHarnessRule(
        JULIA_PROJ_R010,
        JULIA_PROJECT_POLICY_PACK_ID,
        Warning,
        "Source-tracked dependency rev is not locked",
        "URL-based Julia `[sources]` entries should lock `rev` to a commit SHA instead of a moving branch name.",
        labels("project-policy"),
    ),
    JuliaHarnessRule(
        JULIA_PROJ_R011,
        JULIA_PROJECT_POLICY_PACK_ID,
        Warning,
        "Project extension entrypoint is missing",
        "Every Julia `[extensions]` entry should resolve to `ext/<ExtensionName>.jl` or `ext/<ExtensionName>/<ExtensionName>.jl`.",
        labels("project-policy"),
    ),
    JuliaHarnessRule(
        JULIA_PROJ_R012,
        JULIA_PROJECT_POLICY_PACK_ID,
        Warning,
        "Project extension dependency is undeclared",
        "Every Julia `[extensions]` trigger dependency should be declared in `[weakdeps]` or `[deps]` unless it is a stdlib.",
        labels("project-policy"),
    ),
    JuliaHarnessRule(
        JULIA_PROJ_R013,
        JULIA_PROJECT_POLICY_PACK_ID,
        Warning,
        "Project.toml is not readable by Pkg",
        "Julia project policy should run from a `Project.toml` that `Pkg.Types.read_project` can read.",
        labels("project-policy"),
    ),
    JuliaHarnessRule(
        JULIA_PROJ_R014,
        JULIA_PROJECT_POLICY_PACK_ID,
        Warning,
        "Harness config escape lacks explanation",
        "Harness config that disables rules, downgrades severity, shrinks blocking severities, or allows advisory findings must carry a concrete explanation.",
        labels("project-policy"),
    ),
]

"""Return source graph and file ownership policy rules."""
julia_modularity_rules() = [
    JuliaHarnessRule(
        JULIA_MOD_R001,
        JULIA_MODULARITY_PACK_ID,
        Warning,
        "Package entry file is too large for a facade",
        "Julia package entry files should stay compact facades that include named owner files and expose the public module surface.",
        labels("modularity"),
    ),
    JuliaHarnessRule(
        JULIA_MOD_R002,
        JULIA_MODULARITY_PACK_ID,
        Warning,
        "Julia owner file exceeds the owner budget",
        "Julia owner files under project-owned source, extension, and test scopes should stay within a bounded responsibility budget so agents can repair one owner at a time.",
        labels("modularity"),
    ),
    JuliaHarnessRule(
        JULIA_MOD_R003,
        JULIA_MODULARITY_PACK_ID,
        Warning,
        "Dynamic include hides source graph",
        "Keep Julia package source graphs parser-stable with literal `include(...)` targets, or record a project-local exception.",
        labels("modularity"),
    ),
    JuliaHarnessRule(
        JULIA_MOD_R004,
        JULIA_MODULARITY_PACK_ID,
        Warning,
        "Literal include target is missing",
        "Every literal Julia `include(...)` target must resolve to an existing source file.",
        labels("modularity"),
    ),
    JuliaHarnessRule(
        JULIA_MOD_R005,
        JULIA_MODULARITY_PACK_ID,
        Warning,
        "Literal include graph contains a cycle",
        "Julia package source graphs should stay acyclic so agents can follow one repair ownership path.",
        labels("modularity"),
    ),
    JuliaHarnessRule(
        JULIA_MOD_R006,
        JULIA_MODULARITY_PACK_ID,
        Warning,
        "Source file is orphaned from package entry",
        "Julia source files under `src/` should be reachable from the package entry include graph, unless project config records a reason.",
        labels("modularity"),
    ),
    JuliaHarnessRule(
        JULIA_MOD_R007,
        JULIA_MODULARITY_PACK_ID,
        Warning,
        "Source path uses a generic owner bucket",
        "Julia source path segments should name domain ownership instead of generic buckets such as `utils`, `common`, `helpers`, or `misc`.",
        labels("modularity"),
    ),
]

function syntax_rule_by_id()
    Dict(rule.rule_id => rule for rule in julia_syntax_rules())
end

function rules_by_id()
    Dict(
        rule.rule_id => rule for rule in vcat(
            julia_syntax_rules(),
            julia_project_policy_rules(),
            julia_modularity_rules(),
            julia_agent_policy_rules(),
        )
    )
end

function finding_from_rule(
    rule::JuliaHarnessRule;
    summary::AbstractString,
    location::SourceLocation,
    source_line::Union{Nothing,AbstractString}=nothing,
    label::AbstractString,
    extra_labels::Dict{String,String}=Dict{String,String}(),
)
    finding_from_rule_typed(rule, summary, location, source_line, label, extra_labels)
end

function finding_from_rule_typed(
    rule::JuliaHarnessRule,
    summary::AbstractString,
    location::SourceLocation,
    source_line::Union{Nothing,AbstractString},
    label::AbstractString,
    extra_labels::Dict{String,String},
)
    JuliaHarnessFinding(
        rule.rule_id,
        rule.pack_id,
        rule.severity,
        rule.title,
        summary,
        location,
        rule.requirement,
        source_line,
        label,
        merge(copy(rule.labels), extra_labels),
    )
end

function finding_from_rule_typed(
    rule::JuliaHarnessRule,
    summary::AbstractString,
    location::SourceLocation,
    source_line::Union{Nothing,AbstractString},
    label::AbstractString,
)
    finding_from_rule_typed(
        rule,
        summary,
        location,
        source_line,
        label,
        Dict{String,String}(),
    )
end

function finding_from_rule_typed(
    rule::JuliaHarnessRule,
    summary::AbstractString,
    location::SourceLocation,
    label::AbstractString,
)
    finding_from_rule_typed(rule, summary, location, nothing, label, Dict{String,String}())
end

function finding_from_rule_typed(
    rule::JuliaHarnessRule,
    summary::AbstractString,
    location::SourceLocation,
    label::AbstractString,
    extra_labels::Dict{String,String},
)
    finding_from_rule_typed(rule, summary, location, nothing, label, extra_labels)
end
