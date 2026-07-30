struct MoshiNearestApplication
    path::String
    line::Int
    function_name::String
    domain_args::Vector{String}
    branch_literals::Vector{String}
    branch_count::Int
end

function moshi_policy_labels(
    scope::JuliaProjectHarnessScope,
    application::Union{Nothing,MoshiNearestApplication},
    repair_target::AbstractString,
)
    labels = Dict(
        "capability_source" => "Moshi",
        "configured_policy" => "enable",
        "moshi_extension_state" => moshi_extension_repair_state(scope),
        "moshi_repair_shape" => moshi_source_repair_shape(scope; repair_target),
        "moshi_repair_target" => repair_target,
    )
    isnothing(application) && return labels

    labels["moshi_nearest_application_path"] = repair_target
    labels["moshi_nearest_application_line"] = string(application.line)
    labels["moshi_nearest_application_function"] = application.function_name
    labels["moshi_nearest_application_args"] = join(application.domain_args, ",")
    labels["moshi_nearest_application_literals"] = join(application.branch_literals, ",")
    labels
end

function moshi_nearest_application(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
)::Union{Nothing,MoshiNearestApplication}
    candidates = MoshiNearestApplication[]
    for parsed in parsed_files
        parsed.report.is_valid || continue
        is_test_path(scope, parsed.report.path) && continue
        for function_fact in parsed.syntax_facts.functions
            is_stringly_branch_dispatch(function_fact) || continue
            push!(
                candidates,
                MoshiNearestApplication(
                    parsed.report.path,
                    function_fact.line,
                    function_fact.terminal_name,
                    copy(function_fact.stringly_domain_args),
                    copy(function_fact.stringly_branch_literals),
                    function_fact.branch_count,
                ),
            )
        end
    end
    isempty(candidates) && return nothing
    first(sort(candidates; by = moshi_application_rank_key))
end

function moshi_application_rank_key(application::MoshiNearestApplication)
    (
        -length(application.branch_literals),
        -application.branch_count,
        application.path,
        application.line,
        application.function_name,
    )
end
