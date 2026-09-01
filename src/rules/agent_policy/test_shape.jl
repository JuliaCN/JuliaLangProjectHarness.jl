const MAX_TESTSET_CONTROL_FLOW_DEPTH = 3
const MAX_TESTSET_LOOP_NESTING_DEPTH = 2
const MIN_TESTSET_BRANCH_COUNT = 1

function test_control_flow_shape_findings(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
    rules::Dict{String,AspJuliaRule},
)
    findings = AspJuliaFinding[]
    for parsed in parsed_files
        parsed.report.is_valid || continue
        is_test_path(scope, parsed.report.path) || continue
        for test_fact in parsed.syntax_facts.tests
            test_fact.kind == "testset" || continue
            is_nested_test_scenario(test_fact) || continue
            push!(
                findings,
                finding_from_rule_typed(
                    rules[AGENT_JL_R029],
                    "Package testset $(display_testset_name(test_fact)) nests scenario scaffolding: $(test_shape_summary(test_fact)).",
                    SourceLocation(parsed.report.path, test_fact.line, test_fact.column),
                    source_line(parsed.source, test_fact.line),
                    "split nested test scaffolding into named scenario testsets or helper assertions",
                ),
            )
        end
    end
    findings
end

function is_nested_test_scenario(test_fact::JuliaTestSyntax)
    test_fact.control_flow_depth >= MAX_TESTSET_CONTROL_FLOW_DEPTH &&
        test_fact.loop_nesting_depth >= MAX_TESTSET_LOOP_NESTING_DEPTH &&
        test_fact.branch_count >= MIN_TESTSET_BRANCH_COUNT
end

function test_shape_summary(test_fact::JuliaTestSyntax)
    "control-flow depth=$(test_fact.control_flow_depth), branches=$(test_fact.branch_count), loops=$(test_fact.loop_count), loop_depth=$(test_fact.loop_nesting_depth)"
end

function display_testset_name(test_fact::JuliaTestSyntax)
    label::Union{Nothing,String} = test_fact.label
    isnothing(label) && return test_fact.name
    escaped_label::String = replace(label, "\"" => "\\\"")
    single_line_label::String = replace(escaped_label, '\n' => ' ')
    "\"$(single_line_label)\""
end
