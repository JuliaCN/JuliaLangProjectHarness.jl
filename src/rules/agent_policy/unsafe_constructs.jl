const JULIA_RUNTIME_ESCAPE_CALLS = Set(["ccall", "eval"])
const JULIA_EXTERNAL_PROCESS_CALLS = Set(["pipeline", "readchomp", "run"])
const JULIA_ESCAPE_MACROS = Set(["eval", "inbounds"])
const JULIA_PROCESS_EXPRESSION_MARKERS = (
    "`",
    "cmd",
    "command",
    "process",
    "shell",
)
const UNSAFE_CONSTRUCT_REASON_DOC_TOKENS = (
    "abi",
    "bounds",
    "command",
    "external",
    "fixed",
    "invariant",
    "performance",
    "precondition",
    "process",
    "safe",
    "safety",
    "shell",
    "unsafe",
)
const UNSAFE_CONSTRUCT_EVIDENCE_DOC_TOKENS = (
    "benchmark",
    "covered",
    "evidence",
    "profile",
    "receipt",
    "smoke",
    "test",
    "verified",
    "verification",
)

function unsafe_construct_findings(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
    rules::Dict{String,JuliaHarnessRule},
)
    findings = JuliaHarnessFinding[]
    reported = Set{Tuple{String,String,String}}()
    for parsed in parsed_files
        parsed.report.is_valid || continue
        is_test_path(scope, parsed.report.path) && continue
        append!(findings, unsafe_construct_call_findings(parsed, rules, reported))
        append!(findings, unsafe_construct_macro_findings(parsed, rules, reported))
    end
    findings
end

function public_unsafe_evidence_test_findings(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
    public_names::Set{String},
    rules::Dict{String,JuliaHarnessRule},
)
    tested_names = tested_public_call_names(scope, parsed_files)
    findings = JuliaHarnessFinding[]
    reported = Set{String}()
    for parsed in parsed_files
        parsed.report.is_valid || continue
        is_test_path(scope, parsed.report.path) && continue
        for function_fact in parsed.syntax_facts.functions
            function_fact.kind == "function" || continue
            name = function_fact.terminal_name
            name in public_names || continue
            name in tested_names && continue
            name in reported && continue
            constructs = unsafe_constructs_for_function(parsed, function_fact)
            isempty(constructs) && continue
            unsafe_construct_has_contract(parsed, function_fact.line) || continue
            push!(reported, name)
            push!(
                findings,
                finding_from_rule_typed(
                    rules[AGENT_JL_R030],
                    "Exported/public method `$(name)` documents unsafe or performance evidence for $(join(constructs, ", ")) but package tests do not call it.",
                    SourceLocation(
                        parsed.report.path,
                        function_fact.line,
                        function_fact.column,
                    ),
                    source_line(parsed.source, function_fact.line),
                    "add a package test that calls this public safety/performance API",
                ),
            )
        end
    end
    findings
end

function unsafe_construct_call_findings(
    parsed::ParsedJuliaFile,
    rules::Dict{String,JuliaHarnessRule},
    reported::Set{Tuple{String,String,String}},
)
    findings = JuliaHarnessFinding[]
    for call in parsed.syntax_facts.calls
        construct = unsafe_call_construct(call)
        isnothing(construct) && continue
        unsafe_construct_has_contract(parsed, call.line) && continue
        key = unsafe_construct_report_key(parsed, call.line, construct)
        key in reported && continue
        push!(reported, key)
        push!(
            findings,
            finding_from_rule_typed(
                rules[AGENT_JL_R017],
                unsafe_construct_summary(construct),
                SourceLocation(parsed.report.path, call.line, call.column),
                source_line(parsed.source, call.line),
                "document the safety/performance reason and focused verification evidence for this construct",
            ),
        )
    end
    findings
end

function unsafe_construct_macro_findings(
    parsed::ParsedJuliaFile,
    rules::Dict{String,JuliaHarnessRule},
    reported::Set{Tuple{String,String,String}},
)
    findings = JuliaHarnessFinding[]
    for invocation in parsed.syntax_facts.macro_invocations
        invocation.terminal_name in JULIA_ESCAPE_MACROS || continue
        construct = "@$(invocation.terminal_name)"
        unsafe_construct_has_contract(parsed, invocation.line) && continue
        key = unsafe_construct_report_key(parsed, invocation.line, construct)
        key in reported && continue
        push!(reported, key)
        push!(
            findings,
            finding_from_rule_typed(
                rules[AGENT_JL_R017],
                unsafe_construct_summary(construct),
                SourceLocation(parsed.report.path, invocation.line, invocation.column),
                source_line(parsed.source, invocation.line),
                "document the safety/performance reason and focused verification evidence for this construct",
            ),
        )
    end
    findings
end

function unsafe_constructs_for_function(
    parsed::ParsedJuliaFile,
    function_fact::JuliaFunctionSyntax,
)
    constructs = String[]
    lines = function_line_range(function_fact)
    for call in parsed.syntax_facts.calls
        call.line in lines || continue
        construct = unsafe_call_construct(call)
        isnothing(construct) || push!(constructs, construct)
    end
    for invocation in parsed.syntax_facts.macro_invocations
        invocation.line in lines || continue
        invocation.terminal_name in JULIA_ESCAPE_MACROS || continue
        push!(constructs, "@$(invocation.terminal_name)")
    end
    sort!(unique(constructs))
end

function tested_public_call_names(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
)
    names = Set{String}()
    for parsed in parsed_files
        parsed.report.is_valid || continue
        is_test_path(scope, parsed.report.path) || continue
        for call in parsed.syntax_facts.calls
            push!(names, call.terminal_name)
        end
    end
    names
end

function unsafe_call_construct(call::JuliaCallSyntax)
    call.terminal_name in JULIA_RUNTIME_ESCAPE_CALLS && return call.terminal_name
    is_external_process_call(call) && return call.terminal_name
    nothing
end

function is_external_process_call(call::JuliaCallSyntax)
    call.terminal_name in JULIA_EXTERNAL_PROCESS_CALLS || return false
    lower_expression = lowercase(call.expression)
    any(marker -> occursin(marker, lower_expression), JULIA_PROCESS_EXPRESSION_MARKERS)
end

function unsafe_construct_report_key(
    parsed::ParsedJuliaFile,
    line::Int,
    construct::AbstractString,
)
    owner = unsafe_construct_owner_function(parsed, line)
    owner_key = isnothing(owner) ? "top-level:$(line)" : "$(owner.terminal_name):$(owner.line)"
    (parsed.report.path, owner_key, String(construct))
end

function unsafe_construct_has_contract(parsed::ParsedJuliaFile, line::Int)
    docs = unsafe_construct_owner_docs(parsed, line)
    any(has_unsafe_construct_contract_doc, docs)
end

function unsafe_construct_owner_docs(parsed::ParsedJuliaFile, line::Int)
    docs = String[]
    owner = unsafe_construct_owner_function(parsed, line)
    if !isnothing(owner)
        append!(
            docs,
            [
                docstring.text for docstring in parsed.syntax_facts.docstrings if
                docstring.target_kind == owner.kind &&
                terminal_public_name(docstring.target_name) == owner.terminal_name
            ],
        )
    end
    append!(
        docs,
        [
            docstring.text for docstring in parsed.syntax_facts.docstrings if
            docstring.target_kind == "module"
        ],
    )
    docs
end

function unsafe_construct_owner_function(parsed::ParsedJuliaFile, line::Int)
    owners = [
        function_fact for function_fact in parsed.syntax_facts.functions if
        function_fact.line <= line <= function_end_line(function_fact)
    ]
    isempty(owners) && return nothing
    first(sort(owners; by=function_fact -> (
        function_end_line(function_fact) - function_fact.line,
        -function_fact.line,
    )))
end

function function_end_line(function_fact::JuliaFunctionSyntax)
    function_fact.line + count(==('\n'), function_fact.expression)
end

function has_unsafe_construct_contract_doc(text::AbstractString)
    lower_text = lowercase(text)
    has_reason = any(
        token -> occursin(token, lower_text),
        UNSAFE_CONSTRUCT_REASON_DOC_TOKENS,
    )
    has_evidence = any(
        token -> occursin(token, lower_text),
        UNSAFE_CONSTRUCT_EVIDENCE_DOC_TOKENS,
    )
    has_reason && has_evidence
end

function unsafe_construct_summary(construct::AbstractString)
    if construct == "ccall"
        return "Non-test source uses `ccall` without a safety and verification evidence contract."
    elseif construct == "eval" || construct == "@eval"
        return "Non-test source uses runtime evaluation construct `$(construct)` without a safety and verification evidence contract."
    elseif construct == "@inbounds"
        return "Non-test source uses `@inbounds` without a bounds-safety and verification evidence contract."
    end
    "Non-test source may execute an external process through `$(construct)` without a safety and verification evidence contract."
end
