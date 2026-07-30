const PUBLIC_FAILURE_CALL_NAMES = Set([
    "error",
    "throw",
])

const PUBLIC_FAILURE_MACRO_NAMES = Set([
    "assert",
])

const PUBLIC_FAILURE_CONTRACT_DOC_TOKENS = (
    "argumenterror",
    "assert",
    "error",
    "exception",
    "fail",
    "failure",
    "invalid",
    "must",
    "precondition",
    "require",
    "requires",
    "throw",
    "throws",
)

function public_failure_contract_findings(
    parsed_files::Vector{ParsedJuliaFile},
    public_names::Set{String},
    function_docs_by_name::Dict{String,Vector{String}},
    rules::Dict{String,JuliaHarnessRule},
)
    findings = JuliaHarnessFinding[]
    for parsed in parsed_files
        parsed.report.is_valid || continue
        for function_fact in parsed.syntax_facts.functions
            function_fact.kind == "function" || continue
            function_fact.terminal_name in public_names || continue
            haskey(function_docs_by_name, function_fact.terminal_name) || continue
            failure_constructs = public_failure_constructs(parsed, function_fact)
            isempty(failure_constructs) && continue
            has_public_failure_contract_doc(
                function_docs_by_name,
                function_fact.terminal_name,
            ) && continue
            push!(
                findings,
                finding_from_rule_typed(
                    rules[AGENT_JL_R026],
                    "Exported/public method `$(function_fact.terminal_name)` has parser-visible failure paths without a failure contract: $(join(failure_constructs, ", ")).",
                    SourceLocation(
                        parsed.report.path,
                        function_fact.line,
                        function_fact.column,
                    ),
                    source_line(parsed.source, function_fact.line),
                    "document thrown errors, assertions, or invalid-input preconditions for this public method",
                ),
            )
        end
    end
    findings
end

function public_failure_test_findings(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
    public_names::Set{String},
    function_docs_by_name::Dict{String,Vector{String}},
    rules::Dict{String,JuliaHarnessRule},
)
    test_throws_calls = test_throws_call_names_by_public_name(scope, parsed_files)
    detected_summary = isempty(test_throws_calls) ? "none" : join(sort(collect(test_throws_calls)), ", ")
    findings = JuliaHarnessFinding[]
    for parsed in parsed_files
        parsed.report.is_valid || continue
        is_test_path(scope, parsed.report.path) && continue
        for function_fact in parsed.syntax_facts.functions
            function_fact.kind == "function" || continue
            name = function_fact.terminal_name
            name in public_names || continue
            has_public_failure_contract_doc(function_docs_by_name, name) || continue
            isempty(public_failure_constructs(parsed, function_fact)) && continue
            name in test_throws_calls && continue
            push!(
                findings,
                finding_from_rule_typed(
                    rules[AGENT_JL_R027],
                    "Exported/public method `$(name)` documents a failure contract but lacks a parser-visible `@test_throws` call in tests. Detected covered methods: $(detected_summary).",
                    SourceLocation(
                        parsed.report.path,
                        function_fact.line,
                        function_fact.column,
                    ),
                    source_line(parsed.source, function_fact.line),
                    "add a direct parser-visible `@test_throws ExceptionType $(name)(...)` regression in a monitored test file",
                ),
            )
        end
    end
    findings
end

function public_failure_constructs(
    parsed::ParsedJuliaFile,
    function_fact::JuliaFunctionSyntax,
)
    constructs = String[]
    for call in parsed.syntax_facts.calls
        call.line in function_line_range(function_fact) || continue
        call.terminal_name in PUBLIC_FAILURE_CALL_NAMES || continue
        push!(constructs, call.terminal_name)
    end
    for invocation in parsed.syntax_facts.macro_invocations
        invocation.line in function_line_range(function_fact) || continue
        invocation.terminal_name in PUBLIC_FAILURE_MACRO_NAMES || continue
        push!(constructs, "@$(invocation.terminal_name)")
    end
    sort!(unique(constructs))
end

function function_line_range(function_fact::JuliaFunctionSyntax)
    function_fact.line:function_end_line(function_fact)
end

function has_public_failure_contract_doc(
    docs_by_name::Dict{String,Vector{String}},
    name::AbstractString,
)
    any(get(docs_by_name, String(name), String[])) do text
        lower_text = lowercase(text)
        any(token -> occursin(token, lower_text), PUBLIC_FAILURE_CONTRACT_DOC_TOKENS)
    end
end

function test_throws_call_names_by_public_name(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
)
    names = Set{String}()
    for parsed in parsed_files
        parsed.report.is_valid || continue
        is_test_path(scope, parsed.report.path) || continue
        for test_fact in parsed.syntax_facts.tests
            test_fact.kind == "test_throws" || continue
            union!(names, test_throws_call_names(test_fact))
        end
        for observation in parsed.syntax_facts.source_observations
            observation.kind == "test_throws" || continue
            observation.shape == "accepted-direct-public-call" || continue
            union!(names, observation.names)
        end
    end
    names
end

function test_throws_call_names(test_fact::JuliaTestSyntax)
    lexical_call_names(test_fact.expression)
end

const LEXICAL_CALL_KEYWORDS = Set([
    "begin",
    "catch",
    "do",
    "else",
    "elseif",
    "end",
    "finally",
    "for",
    "function",
    "if",
    "let",
    "quote",
    "try",
    "while",
])

const LEXICAL_CALL_OPERATORS = Set([
    "!=",
    "%",
    "&",
    "*",
    "+",
    "-",
    "/",
    "<",
    "<<",
    "<=",
    "==",
    "=>",
    ">",
    ">=",
    ">>",
    ">>>",
    "\\",
    "^",
    "|",
    "|>",
    "÷",
    "⊻",
])

function lexical_call_names(
    expression::AbstractString,
)::Set{String}
    text = unquoted_lexical_projection(expression)
    names = Set{String}()
    for matched in eachmatch(
        r"([A-Za-z_][A-Za-z0-9_!?]*(?:\.[A-Za-z_][A-Za-z0-9_!?]*)*)\s*\(",
        text,
    )
        name = terminal_public_name(matched.captures[1])
        name in LEXICAL_CALL_KEYWORDS || push!(names, name)
    end
    collect_lexical_call_operator_names!(names, text)
    names
end

function unquoted_lexical_projection(expression::AbstractString)::String
    characters = collect(String(expression))
    delimiter::Union{Nothing,Char} = nothing
    escaped = false
    for index in eachindex(characters)
        character = characters[index]
        if !isnothing(delimiter)
            characters[index] = ' '
            if escaped
                escaped = false
            elseif character == '\\'
                escaped = true
            elseif character == delimiter
                delimiter = nothing
            end
        elseif character == '"' || character == '\'' || character == '`'
            delimiter = character
            characters[index] = ' '
        end
    end
    String(characters)
end

function collect_lexical_call_operator_names!(
    names::Set{String},
    expression::String,
)::Set{String}
    characters = collect(expression)
    index = firstindex(characters)
    while index <= lastindex(characters)
        character = characters[index]
        if is_lexical_call_operator_character(character)
            start = index
            while index <= lastindex(characters) &&
                  is_lexical_call_operator_character(characters[index])
                index += 1
            end
            operator = String(characters[start:(index - 1)])
            if operator in LEXICAL_CALL_OPERATORS &&
               is_binary_lexical_call_operator(characters, start, index - 1)
                push!(names, operator)
            end
            continue
        end
        index += 1
    end
    names
end

function is_lexical_call_operator_character(character::Char)::Bool
    character in (
        '!',
        '%',
        '&',
        '*',
        '+',
        '-',
        '/',
        '<',
        '=',
        '>',
        '\\',
        '^',
        '|',
        '÷',
        '⊻',
    )
end

function is_binary_lexical_call_operator(
    characters::Vector{Char},
    start::Int,
    stop::Int,
)::Bool
    previous = previous_nonspace_character(characters, start - 1)
    following = next_nonspace_character(characters, stop + 1)
    isnothing(previous) && return false
    isnothing(following) && return false
    previous in ('(', '[', '{', ',', ';', '=') && return false
    following in (')', ']', '}', ',', ';') && return false
    true
end

function previous_nonspace_character(
    characters::Vector{Char},
    index::Int,
)::Union{Nothing,Char}
    while index >= firstindex(characters)
        isspace(characters[index]) || return characters[index]
        index -= 1
    end
    nothing
end

function next_nonspace_character(
    characters::Vector{Char},
    index::Int,
)::Union{Nothing,Char}
    while index <= lastindex(characters)
        isspace(characters[index]) || return characters[index]
        index += 1
    end
    nothing
end
