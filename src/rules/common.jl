function evaluate_syntax_rules(parsed_files::Vector{ParsedJuliaFile})
    rules = syntax_rule_by_id()
    syntax_rule = rules[JULIA_SYN_R001]
    findings = JuliaHarnessFinding[]
    for parsed in parsed_files
        parsed.report.is_valid && continue
        push!(
            findings,
            finding_from_rule_typed(
                syntax_rule,
                isnothing(parsed.report.parse_error) ? "JuliaSyntax rejected the file." :
                        parsed.report.parse_error,
                SourceLocation(parsed.report.path, 1, 0),
                source_line(parsed.source, 1),
                "repair Julia syntax until JuliaSyntax can parse this file",
            ),
        )
    end
    findings
end

function apply_config_to_findings(findings::Vector{JuliaHarnessFinding}, config::JuliaHarnessConfig)
    selected = JuliaHarnessFinding[]
    for finding in findings
        finding.rule_id in config.disabled_rules && continue
        severity = get(config.rule_severity_overrides, finding.rule_id, finding.severity)
        if severity == finding.severity
            push!(selected, finding)
        else
            push!(
                selected,
                JuliaHarnessFinding(
                    finding.rule_id,
                    finding.pack_id,
                    severity,
                    finding.title,
                    finding.summary,
                    finding.location,
                    finding.requirement,
                    finding.source_line,
                    finding.label,
                    copy(finding.labels),
                ),
            )
        end
    end
    append!(selected, config_escape_findings(config))
    selected
end

function config_escape_findings(config::JuliaHarnessConfig)
    rules = rules_by_id()
    rule = rules[JULIA_PROJ_R014]
    findings = JuliaHarnessFinding[]
    append!(findings, disabled_rule_escape_findings(config, rule))
    append!(findings, severity_override_escape_findings(config, rule, rules))
    append!(findings, blocking_severity_escape_findings(config, rule))
    append!(findings, advisory_allow_escape_findings(config, rule))
    findings
end

function disabled_rule_escape_findings(
    config::JuliaHarnessConfig,
    rule::JuliaHarnessRule,
)
    [
        config_escape_finding(
            rule,
            "Rule `$(rule_id)` is disabled without a concrete explanation.",
            "add a concrete `config.disabled_rule_explanations[\"$(rule_id)\"]` or remove the disabled rule",
        ) for rule_id in sort(collect(config.disabled_rules)) if !has_config_explanation(
            config.disabled_rule_explanations,
            rule_id,
        )
    ]
end

function severity_override_escape_findings(
    config::JuliaHarnessConfig,
    rule::JuliaHarnessRule,
    rules::Dict{String,JuliaHarnessRule},
)
    findings = JuliaHarnessFinding[]
    for (rule_id, severity) in sort(collect(config.rule_severity_overrides); by=first)
        canonical = get(rules, rule_id, nothing)
        !isnothing(canonical) && canonical.severity == severity && continue
        has_config_explanation(config.rule_severity_override_explanations, rule_id) && continue
        push!(
            findings,
            config_escape_finding(
                rule,
                "Rule `$(rule_id)` severity is overridden to `$(severity_label(severity))` without a concrete explanation.",
                "add a concrete `config.rule_severity_override_explanations[\"$(rule_id)\"]` or remove the severity override",
            ),
        )
    end
    findings
end

function blocking_severity_escape_findings(
    config::JuliaHarnessConfig,
    rule::JuliaHarnessRule,
)
    findings = JuliaHarnessFinding[]
    for severity in (Warning, Error)
        severity in config.blocking_severities && continue
        label = severity_label(severity)
        has_config_explanation(config.blocking_severity_explanations, label) && continue
        push!(
            findings,
            config_escape_finding(
                rule,
                "Blocking severity `$(label)` is removed without a concrete explanation.",
                "add a concrete `config.blocking_severity_explanations[\"$(label)\"]` or keep `$(label)` blocking",
            ),
        )
    end
    findings
end

function advisory_allow_escape_findings(
    config::JuliaHarnessConfig,
    rule::JuliaHarnessRule,
)
    isnothing(config.agent_advice_allow_explanation) && return JuliaHarnessFinding[]
    has_agent_advice_allow_explanation(config) && return JuliaHarnessFinding[]
    [
        config_escape_finding(
            rule,
            "`agent_advice_allow_explanation` is set without a concrete explanation.",
            "write a concrete `agent_advice_allow_explanation` or leave it unset",
        ),
    ]
end

function config_escape_finding(
    rule::JuliaHarnessRule,
    summary::AbstractString,
    label::AbstractString,
)
    JuliaHarnessFinding(
        rule.rule_id,
        rule.pack_id,
        rule.severity,
        rule.title,
        String(summary),
        SourceLocation(nothing, 1, 0),
        rule.requirement,
        nothing,
        String(label),
        merge(copy(rule.labels), Dict("escape_guard" => "true")),
    )
end

function has_config_explanation(
    explanations::Dict{String,String},
    key::AbstractString,
)
    has_concrete_explanation(get(explanations, String(key), ""))
end

function has_agent_advice_allow_explanation(config::JuliaHarnessConfig)
    has_concrete_explanation(config.agent_advice_allow_explanation)
end

const MIN_CONCRETE_EXPLANATION_CHARS = 24
const PLACEHOLDER_EXPLANATIONS = Set([
    ".",
    "...",
    "fix later",
    "fixme",
    "later",
    "n/a",
    "na",
    "none",
    "tbd",
    "todo",
])
const PLACEHOLDER_EXPLANATION_PREFIXES = (
    "fix later",
    "fixme",
    "later",
    "tbd",
    "todo",
)

function has_concrete_explanation(explanation::Union{Nothing,AbstractString})
    normalized = lowercase(strip(something(explanation, "")))
    length(normalized) >= MIN_CONCRETE_EXPLANATION_CHARS || return false
    !is_placeholder_explanation(normalized)
end

function is_placeholder_explanation(normalized::AbstractString)
    normalized in PLACEHOLDER_EXPLANATIONS && return true
    any(
        prefix -> startswith(normalized, prefix * " ") ||
                  startswith(normalized, prefix * ":") ||
                  startswith(normalized, prefix * "-"),
        PLACEHOLDER_EXPLANATION_PREFIXES,
    )
end
