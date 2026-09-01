function public_mutating_method_contract_findings(
    parsed_files::Vector{ParsedJuliaFile},
    public_names::Set{String},
    function_docs_by_name::Dict{String,Vector{String}},
    rules::Dict{String,AspJuliaRule},
)
    findings = AspJuliaFinding[]
    reported = Set{String}()
    for parsed in parsed_files
        parsed.report.is_valid || continue
        append!(
            findings,
            public_mutating_method_contract_findings(
                parsed,
                public_names,
                function_docs_by_name,
                rules,
                reported,
            ),
        )
    end
    findings
end

function public_mutating_method_test_findings(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
    public_names::Set{String},
    function_docs_by_name::Dict{String,Vector{String}},
    rules::Dict{String,AspJuliaRule},
)
    tested_mutating_names = tested_mutating_call_names(scope, parsed_files)
    findings = AspJuliaFinding[]
    reported = Set{String}()
    for parsed in parsed_files
        parsed.report.is_valid || continue
        is_test_path(scope, parsed.report.path) && continue
        for function_fact in parsed.syntax_facts.functions
            name = function_fact.terminal_name
            name in public_names || continue
            endswith(name, "!") || continue
            has_mutation_contract_doc(function_docs_by_name, name) || continue
            name in tested_mutating_names && continue
            name in reported && continue
            push!(reported, name)
            push!(
                findings,
                finding_from_rule_typed(
                    rules[AGENT_JL_R028],
                    "Exported/public mutating method `$(name)` documents a mutation contract but tests do not call it.",
                    SourceLocation(
                        parsed.report.path,
                        function_fact.line,
                        function_fact.column,
                    ),
                    source_line(parsed.source, function_fact.line),
                    "add a package test that calls this public mutating API",
                ),
            )
        end
    end
    findings
end

function tested_mutating_call_names(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
)
    names = Set{String}()
    for parsed in parsed_files
        parsed.report.is_valid || continue
        is_test_path(scope, parsed.report.path) || continue
        for call in parsed.syntax_facts.calls
            endswith(call.terminal_name, "!") || continue
            push!(names, call.terminal_name)
        end
    end
    names
end

function public_mutating_method_contract_findings(
    parsed::ParsedJuliaFile,
    public_names::Set{String},
    function_docs_by_name::Dict{String,Vector{String}},
    rules::Dict{String,AspJuliaRule},
    reported::Set{String},
)
    findings = AspJuliaFinding[]
    for function_fact in parsed.syntax_facts.functions
        name = function_fact.terminal_name
        name in public_names || continue
        endswith(name, "!") || continue
        haskey(function_docs_by_name, name) || continue
        name in reported && continue
        has_mutation_contract_doc(function_docs_by_name, name) && continue
        push!(reported, name)
        push!(
            findings,
            finding_from_rule_typed(
                rules[AGENT_JL_R016],
                "Exported/public mutating method `$(name)` is documented without a mutation contract.",
                SourceLocation(parsed.report.path, function_fact.line, function_fact.column),
                source_line(parsed.source, function_fact.line),
                "document which arguments or state this public mutating method changes",
            ),
        )
    end
    findings
end
