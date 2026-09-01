const MOSHI_DOMAIN_BRANCH_THRESHOLD = 2

function moshi_policy_findings(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
    rules::Dict{String,AspJuliaRule},
)
    project_moshi_policy(scope) == "enable" || return AspJuliaFinding[]
    haskey(scope.direct_dependencies, "Moshi") && return AspJuliaFinding[]
    application::Union{Nothing,MoshiNearestApplication} =
        moshi_nearest_application(scope, parsed_files)
    repair_target = isnothing(application) ?
                    moshi_source_repair_target(scope) :
                    display_public_owner_path(scope, application.path)
    summary_suffix = isnothing(application) ? "" :
                     " Nearest parser-visible application: `$(application.function_name)` at $(repair_target):$(application.line) with branch literals $(join(application.branch_literals, ", "))."
    [
        finding_from_rule_typed(
            rules[AGENT_JL_R020],
            "Project.toml enables Moshi support through `[tool.AspJulia]`, but Moshi is not a direct package dependency available to `src/`.$(summary_suffix)",
            SourceLocation(scope.project_toml_path, 1, 0),
            "declare Moshi in `[deps]` and model the nearest stringly domain in `$(repair_target)`",
            moshi_policy_labels(scope, application, repair_target),
        ),
    ]
end

function moshi_domain_model_findings(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
    public_names::Set{String},
    rules::Dict{String,AspJuliaRule},
)
    modeling_facts = moshi_modeling_facts(parsed_files)
    findings = AspJuliaFinding[]
    for parsed in parsed_files
        parsed.report.is_valid || continue
        is_test_path(scope, parsed.report.path) && continue
        for function_fact in parsed.syntax_facts.functions
            function_fact.terminal_name in public_names || continue
            is_stringly_branch_dispatch(function_fact) || continue
            moshi_domain_model_satisfied(function_fact, modeling_facts) && continue
            push!(
                findings,
                finding_from_rule_typed(
                    rules[AGENT_JL_R020],
                    moshi_domain_model_summary(scope, function_fact),
                    SourceLocation(
                        parsed.report.path,
                        function_fact.line,
                        function_fact.column,
                    ),
                    source_line(parsed.source, function_fact.line),
                    moshi_domain_model_label(scope),
                    moshi_domain_model_labels(
                        scope,
                        function_fact,
                        modeling_facts,
                    ),
                ),
            )
        end
    end
    findings
end

function moshi_domain_bridge_findings(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
    public_names::Set{String},
    rules::Dict{String,AspJuliaRule},
)
    modeling_facts = moshi_modeling_facts(parsed_files)
    findings = AspJuliaFinding[]
    for parsed in parsed_files
        parsed.report.is_valid || continue
        is_test_path(scope, parsed.report.path) && continue
        for function_fact in parsed.syntax_facts.functions
            function_fact.terminal_name in public_names || continue
            is_stringly_branch_dispatch(function_fact) || continue
            moshi_domain_model_satisfied(function_fact, modeling_facts) || continue
            moshi_match_bridge_satisfied(function_fact, modeling_facts) && continue
            push!(
                findings,
                finding_from_rule_typed(
                    rules[AGENT_JL_R022],
                    moshi_domain_bridge_summary(function_fact),
                    SourceLocation(
                        parsed.report.path,
                        function_fact.line,
                        function_fact.column,
                    ),
                    source_line(parsed.source, function_fact.line),
                    "route this domain through Moshi @match cases or typed methods",
                    moshi_domain_bridge_labels(
                        scope,
                        function_fact,
                        modeling_facts,
                    ),
                ),
            )
        end
    end
    findings
end

function moshi_modeling_facts(parsed_files::Vector{ParsedJuliaFile})
    [
        fact for parsed in parsed_files for fact in parsed.syntax_facts.moshi if
        is_moshi_modeling_fact(fact)
    ]
end

function is_moshi_modeling_fact(fact::JuliaMoshiSyntax)
    fact.kind in ("data", "match")
end

function has_moshi_optional_extension(scope::JuliaProjectHarnessScope)
    haskey(scope.weak_dependencies, "Moshi") || return false
    any(dependencies -> "Moshi" in dependencies, values(scope.extensions))
end

function moshi_test_target_active(scope::JuliaProjectHarnessScope)
    "Moshi" in get(scope.targets, "test", String[])
end

function project_moshi_policy(scope::JuliaProjectHarnessScope)
    isnothing(scope.project_toml_path) && return "auto"
    table = project_harness_tool_table(scope.project_toml_path)
    value = get(table, "moshi", "auto")
    value isa String || return "invalid"
    normalized = lowercase(String(strip(value)))
    normalized in ("auto", "enable") && return normalized
    "invalid"
end

function is_stringly_branch_dispatch(function_fact::JuliaFunctionSyntax)
    !isempty(function_fact.stringly_domain_args) &&
        function_fact.branch_count >= MOSHI_DOMAIN_BRANCH_THRESHOLD
end

function moshi_domain_model_satisfied(
    function_fact::JuliaFunctionSyntax,
    modeling_facts::Vector{JuliaMoshiSyntax},
)
    isempty(modeling_facts) && return false
    isempty(function_fact.stringly_branch_literals) && return true
    literal_tokens = normalized_domain_tokens(function_fact.stringly_branch_literals)
    isempty(literal_tokens) && return true
    modeled_tokens = moshi_modeling_tokens(modeling_facts)
    !isempty(modeled_tokens) && all(token -> token in modeled_tokens, literal_tokens)
end

function moshi_match_bridge_satisfied(
    function_fact::JuliaFunctionSyntax,
    modeling_facts::Vector{JuliaMoshiSyntax},
)
    isempty(modeling_facts) && return false
    literal_tokens = normalized_domain_tokens(function_fact.stringly_branch_literals)
    if isempty(literal_tokens)
        return any(fact -> fact.kind == "match" && !isempty(fact.case_names), modeling_facts)
    end
    any(
        target -> moshi_match_patterns_cover_target(target, literal_tokens, modeling_facts),
        moshi_covered_data_targets(function_fact, modeling_facts),
    )
end

function moshi_domain_model_summary(
    scope::JuliaProjectHarnessScope,
    function_fact::JuliaFunctionSyntax,
)
    literal_suffix = isempty(function_fact.stringly_branch_literals) ? "" :
                     " Branch literals: $(join(function_fact.stringly_branch_literals, ", "))."
    "Exported/public method `$(function_fact.terminal_name)` branches over stringly domain arguments: $(join(function_fact.stringly_domain_args, ", ")).$(literal_suffix) Prefer a typed domain carrier. $(moshi_domain_model_repair_path(scope))"
end

function moshi_domain_model_label(scope::JuliaProjectHarnessScope)
    state = moshi_extension_repair_state(scope)
    state == "direct_dep_enabled" &&
        return "add Moshi @data/@match domain modeling under `$(moshi_source_repair_target(scope))`"
    state == "extension_without_model" &&
        return "add Moshi @data/@match domain modeling in `$(moshi_extension_repair_target(scope))`"
    state == "weakdep_without_extension" &&
        return "add `$(moshi_extension_repair_target(scope))` and model this domain with Moshi @data/@match"
    state == "direct_dep_without_extension" &&
        return "move Moshi behind weakdeps/extensions or document why it is core API"
    "model the domain with a package-owned value type, or add a Moshi weakdep extension first"
end

function moshi_domain_model_repair_path(scope::JuliaProjectHarnessScope)
    state = moshi_extension_repair_state(scope)
    if state == "extension_without_model"
        return "Moshi is already configured as an optional extension; add parser-visible `@data` variants that cover the branch literals, plus a `@match` branch surface in `$(moshi_extension_repair_target(scope))` instead of treating the config as the model."
    elseif state == "weakdep_without_extension"
        return "Moshi is already a weak dependency; add an `[extensions]` entry such as `$(moshi_extension_repair_name(scope))`, keep Moshi in `[extras]` and the `test` target, and place the ADT/pattern-match surface in `$(moshi_extension_repair_target(scope))`."
    elseif state == "direct_dep_enabled"
        return "Moshi is a direct dependency because Project.toml enables Moshi; add parser-visible `@data` variants and `@match` branches under `$(moshi_source_repair_target(scope))`."
    end
    "If Moshi is chosen as a source policy, set `[tool.AspJulia] moshi = \"enable\"`, declare Moshi in `[deps]` and `[compat]`, and add parser-visible `@data`/`@match` under `$(moshi_source_repair_target(scope))`. If this is only an optional experiment, keep Moshi behind `[weakdeps]`, `[extensions]`, `[extras]`, and the `test` target. Otherwise use a package-owned enum, Symbol, or value type."
end

function moshi_domain_bridge_summary(function_fact::JuliaFunctionSyntax)
    literal_suffix = isempty(function_fact.stringly_branch_literals) ? "" :
                     " Covered literals: $(join(function_fact.stringly_branch_literals, ", "))."
    "Exported/public method `$(function_fact.terminal_name)` has a Moshi `@data` domain model but no parser-visible `@match` cases covering its stringly branch domain.$(literal_suffix) Convert the stringly boundary once, then branch on the Moshi domain model instead of repeating string comparisons."
end

function moshi_domain_model_labels(
    scope::JuliaProjectHarnessScope,
    function_fact::JuliaFunctionSyntax,
    modeling_facts::Vector{JuliaMoshiSyntax},
)
    labels = Dict(
        "capability_source" => "Moshi",
        "capabilities" => join(moshi_extension_capability_names(), ","),
        "moshi_extension_state" => moshi_extension_repair_state(scope),
        "moshi_extension_target" => moshi_model_repair_target(scope),
        "moshi_repair_shape" => moshi_extension_repair_shape(scope),
    )
    if !isempty(function_fact.stringly_branch_literals)
        labels["stringly_branch_literals"] = join(function_fact.stringly_branch_literals, ",")
        labels["moshi_model_coverage"] = moshi_model_coverage_label(
            function_fact,
            modeling_facts,
        )
    end
    labels
end

function moshi_model_coverage_label(
    function_fact::JuliaFunctionSyntax,
    modeling_facts::Vector{JuliaMoshiSyntax},
)
    isempty(modeling_facts) && return "missing_model"
    literal_tokens = normalized_domain_tokens(function_fact.stringly_branch_literals)
    modeled_tokens = moshi_modeling_tokens(modeling_facts)
    missing = [token for token in literal_tokens if !(token in modeled_tokens)]
    isempty(missing) ? "covered" : "missing=$(join(missing, ","))"
end

function moshi_modeling_tokens(modeling_facts::Vector{JuliaMoshiSyntax})
    tokens = Set{String}()
    for fact in modeling_facts
        for variant_name in fact.variant_names
            token = normalized_domain_token(variant_name)
            isempty(token) && continue
            push!(tokens, token)
        end
    end
    tokens
end

function moshi_match_case_tokens(modeling_facts::Vector{JuliaMoshiSyntax})
    tokens = Set{String}()
    for fact in modeling_facts
        fact.kind == "match" || continue
        for case_name in fact.case_names
            token = normalized_domain_token(case_name)
            isempty(token) && continue
            push!(tokens, token)
        end
    end
    tokens
end

function moshi_covered_data_targets(
    function_fact::JuliaFunctionSyntax,
    modeling_facts::Vector{JuliaMoshiSyntax},
)
    literal_tokens = normalized_domain_tokens(function_fact.stringly_branch_literals)
    isempty(literal_tokens) && return String[]
    targets = String[]
    seen = Set{String}()
    for fact in modeling_facts
        fact.kind == "data" || continue
        isnothing(fact.target_name) && continue
        variant_tokens = normalized_domain_tokens(fact.variant_names)
        all(token -> token in variant_tokens, literal_tokens) || continue
        fact.target_name in seen && continue
        push!(seen, fact.target_name)
        push!(targets, fact.target_name)
    end
    targets
end

function moshi_match_patterns_cover_target(
    target_name::AbstractString,
    literal_tokens::Vector{String},
    modeling_facts::Vector{JuliaMoshiSyntax},
)
    pattern_tokens = moshi_match_pattern_tokens_for_target(target_name, modeling_facts)
    !isempty(pattern_tokens) && all(token -> token in pattern_tokens, literal_tokens)
end

function moshi_match_pattern_tokens_for_target(
    target_name::AbstractString,
    modeling_facts::Vector{JuliaMoshiSyntax},
)
    target_token = normalized_terminal_domain_token(target_name)
    tokens = Set{String}()
    for fact in modeling_facts
        fact.kind == "match" || continue
        for pattern in fact.case_patterns
            pattern_target = moshi_match_pattern_target_token(pattern)
            pattern_case = moshi_match_pattern_case_token(pattern)
            isnothing(pattern_target) && continue
            isnothing(pattern_case) && continue
            pattern_target == target_token || continue
            push!(tokens, pattern_case)
        end
    end
    tokens
end

function moshi_match_pattern_target_token(pattern::AbstractString)
    parts = split(String(pattern), '.')
    length(parts) >= 2 || return nothing
    normalized_domain_token(parts[end - 1])
end

function moshi_match_pattern_case_token(pattern::AbstractString)
    parts = split(String(pattern), '.')
    isempty(parts) && return nothing
    normalized_domain_token(last(parts))
end

function normalized_terminal_domain_token(value::AbstractString)
    parts = split(String(value), '.')
    normalized_domain_token(last(parts))
end

function moshi_domain_bridge_labels(
    scope::JuliaProjectHarnessScope,
    function_fact::JuliaFunctionSyntax,
    modeling_facts::Vector{JuliaMoshiSyntax},
)
    labels = Dict(
        "capability_source" => "Moshi",
        "capabilities" => join(moshi_extension_capability_names(), ","),
        "moshi_extension_state" => moshi_extension_repair_state(scope),
        "moshi_extension_target" => moshi_model_repair_target(scope),
        "moshi_repair_shape" => moshi_extension_repair_shape(scope),
        "moshi_model_coverage" => moshi_model_coverage_label(
            function_fact,
            modeling_facts,
        ),
        "moshi_match_coverage" => moshi_match_coverage_label(
            function_fact,
            modeling_facts,
        ),
        "moshi_model_targets" => join(
            moshi_covered_data_targets(function_fact, modeling_facts),
            ",",
        ),
    )
    if !isempty(function_fact.stringly_branch_literals)
        labels["stringly_branch_literals"] = join(function_fact.stringly_branch_literals, ",")
    end
    labels
end

function moshi_match_coverage_label(
    function_fact::JuliaFunctionSyntax,
    modeling_facts::Vector{JuliaMoshiSyntax},
)
    literal_tokens = normalized_domain_tokens(function_fact.stringly_branch_literals)
    targets = moshi_covered_data_targets(function_fact, modeling_facts)
    isempty(targets) && return "missing_model_target"
    for target in targets
        pattern_tokens = moshi_match_pattern_tokens_for_target(target, modeling_facts)
        missing = [token for token in literal_tokens if !(token in pattern_tokens)]
        isempty(missing) && return "covered"
    end
    "missing=$(join(literal_tokens, ","))"
end

function normalized_domain_tokens(values::Vector{String})
    tokens = String[]
    seen = Set{String}()
    for value in values
        token = normalized_domain_token(value)
        isempty(token) && continue
        token in seen && continue
        push!(seen, token)
        push!(tokens, token)
    end
    tokens
end

function normalized_domain_token(value::AbstractString)
    buffer = IOBuffer()
    for character in value
        if isletter(character) || isdigit(character)
            print(buffer, lowercase(character))
        end
    end
    String(take!(buffer))
end
