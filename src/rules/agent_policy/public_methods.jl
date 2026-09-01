const MAX_PUBLIC_METHOD_CONTROL_FLOW_DEPTH = 4
const MAX_PUBLIC_METHOD_BODY_STATEMENTS = 8
const MIN_PUBLIC_METHOD_PIPELINE_STEPS = 3
const MAX_PUBLIC_METHOD_MACRO_INVOCATIONS = 3

function public_method_shape_findings(
    parsed_files::Vector{ParsedJuliaFile},
    public_names::Set{String},
    function_docs_by_name::Dict{String,Vector{String}},
    rules::Dict{String,AspJuliaRule},
)
    findings = AspJuliaFinding[]
    for parsed in parsed_files
        parsed.report.is_valid || continue
        for function_fact in parsed.syntax_facts.functions
            function_fact.terminal_name in public_names || continue
            append!(
                findings,
                public_method_shape_findings(
                    parsed,
                    function_fact,
                    function_docs_by_name,
                    rules,
                ),
            )
        end
    end
    findings
end

function public_method_shape_findings(
    parsed::ParsedJuliaFile,
    function_fact::JuliaFunctionSyntax,
    function_docs_by_name::Dict{String,Vector{String}},
    rules::Dict{String,AspJuliaRule},
)
    findings = AspJuliaFinding[]
    append!(findings, public_method_argument_shape_findings(parsed, function_fact, rules))
    append!(findings, public_method_algorithm_shape_findings(parsed, function_fact, rules))
    append!(
        findings,
        public_method_macro_contract_findings(
            parsed,
            function_fact,
            function_docs_by_name,
            rules,
        ),
    )
    findings
end

function public_method_argument_shape_findings(
    parsed::ParsedJuliaFile,
    function_fact::JuliaFunctionSyntax,
    rules::Dict{String,AspJuliaRule},
)
    findings = AspJuliaFinding[]
    if length(function_fact.positional_args) >= 5
        push!(
            findings,
            finding_from_rule_typed(
                rules[AGENT_JL_R002],
                "Exported/public method `$(function_fact.terminal_name)` has $(length(function_fact.positional_args)) positional arguments: $(join(function_fact.positional_args, ", ")).",
                SourceLocation(parsed.report.path, function_fact.line, function_fact.column),
                source_line(parsed.source, function_fact.line),
                "move optional modes into keywords or a named config surface",
            ),
        )
    end
    if length(function_fact.bool_positional_args) >= 2
        push!(
            findings,
            finding_from_rule_typed(
                rules[AGENT_JL_R003],
                "Exported/public method `$(function_fact.terminal_name)` has positional Bool flags: $(join(function_fact.bool_positional_args, ", ")).",
                SourceLocation(parsed.report.path, function_fact.line, function_fact.column),
                source_line(parsed.source, function_fact.line),
                "move Bool flags into keywords or a named options object",
            ),
        )
    end
    if !isempty(function_fact.stringly_domain_args)
        push!(
            findings,
            finding_from_rule_typed(
                rules[AGENT_JL_R004],
                "Exported/public method `$(function_fact.terminal_name)` exposes stringly domain arguments: $(join(function_fact.stringly_domain_args, ", ")).",
                SourceLocation(parsed.report.path, function_fact.line, function_fact.column),
                source_line(parsed.source, function_fact.line),
                "replace stringly domain arguments with a named enum, value type, or config carrier",
            ),
        )
    end
    findings
end

function public_method_algorithm_shape_findings(
    parsed::ParsedJuliaFile,
    function_fact::JuliaFunctionSyntax,
    rules::Dict{String,AspJuliaRule},
)
    findings = AspJuliaFinding[]
    function_fact.kind == "function" || return findings
    if function_fact.control_flow_depth >= MAX_PUBLIC_METHOD_CONTROL_FLOW_DEPTH
        push!(
            findings,
            finding_from_rule_typed(
                rules[AGENT_JL_R007],
                "Exported/public method `$(function_fact.terminal_name)` has control-flow depth $(function_fact.control_flow_depth): $(join(function_fact.control_flow_kinds, ", ")). $(julia_algorithm_shape_summary(function_fact))",
                SourceLocation(parsed.report.path, function_fact.line, function_fact.column),
                source_line(parsed.source, function_fact.line),
                "extract nested branches and loops into named pipeline steps",
            ),
        )
    end
    if function_fact.body_statement_count >= MAX_PUBLIC_METHOD_BODY_STATEMENTS &&
       length(function_fact.body_named_calls) < MIN_PUBLIC_METHOD_PIPELINE_STEPS
        push!(
            findings,
            finding_from_rule_typed(
                rules[AGENT_JL_R008],
                "Exported/public method `$(function_fact.terminal_name)` has $(function_fact.body_statement_count) top-level body statements but only $(length(function_fact.body_named_calls)) named body calls.",
                SourceLocation(parsed.report.path, function_fact.line, function_fact.column),
                source_line(parsed.source, function_fact.line),
                "split the broad public body into named pipeline helper functions",
            ),
        )
    end
    findings
end

function public_method_macro_contract_findings(
    parsed::ParsedJuliaFile,
    function_fact::JuliaFunctionSyntax,
    function_docs_by_name::Dict{String,Vector{String}},
    rules::Dict{String,AspJuliaRule},
)
    findings = AspJuliaFinding[]
    function_fact.kind == "function" || return findings
    haskey(function_docs_by_name, function_fact.terminal_name) || return findings
    function_fact.macro_invocation_count >= MAX_PUBLIC_METHOD_MACRO_INVOCATIONS ||
        return findings
    has_syntax_contract_doc(function_docs_by_name, function_fact.terminal_name) &&
        return findings
    push!(
        findings,
        finding_from_rule_typed(
            rules[AGENT_JL_R010],
            "Exported/public method `$(function_fact.terminal_name)` uses $(function_fact.macro_invocation_count) macro invocations without a syntax contract doc: $(join(function_fact.macro_invocation_names, ", ")).",
            SourceLocation(parsed.report.path, function_fact.line, function_fact.column),
            source_line(parsed.source, function_fact.line),
            "document the syntax or macro-expansion contract for this public method",
        ),
    )
    findings
end
