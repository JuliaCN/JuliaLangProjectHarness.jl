const MIN_PUBLIC_GENERIC_TEST_INPUT_TYPES = 2

function public_generic_type_coverage_findings(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
    public_names::Set{String},
    rules::Dict{String,AspJuliaRule},
)
    findings = AspJuliaFinding[]
    input_types_by_name = test_literal_input_types_by_call_name(scope, parsed_files)
    reported = Set{String}()
    for parsed in parsed_files
        parsed.report.is_valid || continue
        is_test_path(scope, parsed.report.path) && continue
        for function_fact in parsed.syntax_facts.functions
            is_public_generic_method(function_fact, public_names) || continue
            name = function_fact.terminal_name
            name in reported && continue
            input_types = get(input_types_by_name, name, Set{String}())
            length(input_types) >= MIN_PUBLIC_GENERIC_TEST_INPUT_TYPES && continue
            push!(reported, name)
            push!(
                findings,
                finding_from_rule_typed(
                    rules[AGENT_JL_R018],
                    public_generic_type_coverage_summary(function_fact, input_types),
                    SourceLocation(
                        parsed.report.path,
                        function_fact.line,
                        function_fact.column,
                    ),
                    source_line(parsed.source, function_fact.line),
                    "add tests that call this generic public API with at least two relevant input types",
                ),
            )
        end
    end
    findings
end

function is_public_generic_method(
    function_fact::JuliaFunctionSyntax,
    public_names::Set{String},
)
    function_fact.terminal_name in public_names || return false
    !isempty(function_fact.where_parameters)
end

function test_literal_input_types_by_call_name(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
)
    input_types_by_name = Dict{String,Set{String}}()
    for parsed in parsed_files
        parsed.report.is_valid || continue
        is_test_path(scope, parsed.report.path) || continue
        for call in parsed.syntax_facts.calls
            input_type = literal_input_type_for_call(call)
            isnothing(input_type) && continue
            push!(get!(input_types_by_name, call.terminal_name, Set{String}()), input_type)
        end
    end
    input_types_by_name
end

function literal_input_type_for_call(call::JuliaCallSyntax)
    argument = first_call_argument_lexeme(call.expression)
    isnothing(argument) && return nothing
    literal_input_type_category(argument)
end

function first_call_argument_lexeme(
    expression::AbstractString,
)::Union{Nothing,String}
    text = String(expression)
    opening = findfirst(==('('), text)
    isnothing(opening) && return nothing
    start = nextind(text, opening)
    start > lastindex(text) && return nothing
    paren_depth = 0
    bracket_depth = 0
    brace_depth = 0
    string_delimiter::Union{Nothing,Char} = nothing
    escaped = false
    index = start
    while index <= lastindex(text)
        character = text[index]
        if !isnothing(string_delimiter)
            if escaped
                escaped = false
            elseif character == '\\'
                escaped = true
            elseif character == string_delimiter
                string_delimiter = nothing
            end
        elseif character == '"' || character == '\''
            string_delimiter = character
        elseif character == '('
            paren_depth += 1
        elseif character == ')'
            if paren_depth == 0 && bracket_depth == 0 && brace_depth == 0
                return stripped_argument_lexeme(text, start, prevind(text, index))
            end
            paren_depth -= 1
        elseif character == '['
            bracket_depth += 1
        elseif character == ']'
            bracket_depth -= 1
        elseif character == '{'
            brace_depth += 1
        elseif character == '}'
            brace_depth -= 1
        elseif (character == ',' || character == ';') &&
               paren_depth == 0 &&
               bracket_depth == 0 &&
               brace_depth == 0
            return stripped_argument_lexeme(text, start, prevind(text, index))
        end
        index = nextind(text, index)
    end
    nothing
end

function stripped_argument_lexeme(
    text::String,
    start::Int,
    stop::Int,
)::Union{Nothing,String}
    stop < start && return nothing
    argument = strip(String(SubString(text, start, stop)))
    isempty(argument) ? nothing : argument
end

function literal_input_type_category(argument::AbstractString)
    text = String(strip(String(argument)))
    isempty(text) && return nothing
    (text == "true" || text == "false") && return "Bool"
    occursin(r"^[+-]?\d[\d_]*$", text) && return "Int"
    occursin(
        r"^[+-]?(?:(?:\d[\d_]*)?\.\d[\d_]*|\d[\d_]*\.)(?:[eEfF][+-]?\d[\d_]*)?$|^[+-]?\d[\d_]*[eEfF][+-]?\d[\d_]*$",
        text,
    ) && return "Float64"
    startswith(text, '"') && endswith(text, '"') && return "String"
    startswith(text, '\'') && endswith(text, '\'') && return "Char"
    startswith(text, ':') && return "Symbol"
    startswith(text, '[') && endswith(text, ']') && return "Vector"
    if startswith(text, '(') && endswith(text, ')')
        closing = matching_delimiter_index(text, firstindex(text), '(', ')')
        if closing == lastindex(text)
            inner_start = nextind(text, firstindex(text))
            inner_stop = prevind(text, lastindex(text))
            inner_stop < inner_start && return "Tuple"
            inner = String(SubString(text, inner_start, inner_stop))
            has_top_level_comma(inner) && return "Tuple"
            return literal_input_type_category(inner)
        end
    end
    opening = findfirst(==('('), text)
    if !isnothing(opening) && endswith(text, ')')
        prefix_stop = prevind(text, opening)
        prefix_stop >= firstindex(text) || return nothing
        name = strip(String(SubString(text, firstindex(text), prefix_stop)))
        terminal = last(split(name, '.'))
        terminal in TYPE_COVERAGE_LITERAL_CONSTRUCTORS && return terminal
    end
    nothing
end

function matching_delimiter_index(
    text::String,
    opening::Int,
    open_character::Char,
    close_character::Char,
)::Union{Nothing,Int}
    depth = 0
    string_delimiter::Union{Nothing,Char} = nothing
    escaped = false
    index = opening
    while index <= lastindex(text)
        character = text[index]
        if !isnothing(string_delimiter)
            if escaped
                escaped = false
            elseif character == '\\'
                escaped = true
            elseif character == string_delimiter
                string_delimiter = nothing
            end
        elseif character == '"' || character == '\''
            string_delimiter = character
        elseif character == open_character
            depth += 1
        elseif character == close_character
            depth -= 1
            depth == 0 && return index
        end
        index = nextind(text, index)
    end
    nothing
end

function has_top_level_comma(text::String)::Bool
    paren_depth = 0
    bracket_depth = 0
    brace_depth = 0
    string_delimiter::Union{Nothing,Char} = nothing
    escaped = false
    for character in text
        if !isnothing(string_delimiter)
            if escaped
                escaped = false
            elseif character == '\\'
                escaped = true
            elseif character == string_delimiter
                string_delimiter = nothing
            end
        elseif character == '"' || character == '\''
            string_delimiter = character
        elseif character == '('
            paren_depth += 1
        elseif character == ')'
            paren_depth -= 1
        elseif character == '['
            bracket_depth += 1
        elseif character == ']'
            bracket_depth -= 1
        elseif character == '{'
            brace_depth += 1
        elseif character == '}'
            brace_depth -= 1
        elseif character == ',' &&
               paren_depth == 0 &&
               bracket_depth == 0 &&
               brace_depth == 0
            return true
        end
    end
    false
end

const TYPE_COVERAGE_LITERAL_CONSTRUCTORS = Set([
    "BigFloat",
    "BigInt",
    "Dict",
    "Float16",
    "Float32",
    "Float64",
    "Int128",
    "Int16",
    "Int32",
    "Int64",
    "Int8",
    "Set",
    "UInt128",
    "UInt16",
    "UInt32",
    "UInt64",
    "UInt8",
])

function public_generic_type_coverage_summary(
    function_fact::JuliaFunctionSyntax,
    input_types::Set{String},
)
    where_clause = join(function_fact.where_parameters, ", ")
    observed = isempty(input_types) ? "no parser-visible literal input types" :
               "only parser-visible input types: $(join(sort!(collect(input_types)), ", "))"
    "Exported/public generic method `$(function_fact.terminal_name)` declares `where {$(where_clause)}` but tests exercise $(observed)."
end
