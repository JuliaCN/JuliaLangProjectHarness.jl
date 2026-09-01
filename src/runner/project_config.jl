const PROJECT_HARNESS_TOOL_TABLE = "AspJulia"

function project_toml_harness_config(
    project_root::AbstractString,
    base_config::AspJuliaConfig,
)
    project_toml = Base.current_project(project_search_start(project_root))
    isnothing(project_toml) && return base_config
    table = project_harness_tool_table(project_toml)
    isempty(table) && return base_config
    merge_project_harness_tool_config(base_config, table)
end

function project_harness_tool_table(project_toml::AbstractString)
    parsed = TOML.parsefile(project_toml)
    tool = get(parsed, "tool", nothing)
    tool isa Dict{String,Any} || return Dict{String,Any}()
    table = get(tool, PROJECT_HARNESS_TOOL_TABLE, nothing)
    table isa Dict{String,Any} || return Dict{String,Any}()
    copy(table)
end

function merge_project_harness_tool_config(
    base_config::AspJuliaConfig,
    table::Dict{String,Any},
)
    AspJuliaConfig(
        Set(project_config_string_list(
            table,
            "ignored_dir_names",
            collect(base_config.ignored_dir_names),
        )),
        Set(parse_harness_severity.(project_config_string_list(
            table,
            "blocking_severities",
            severity_label.(collect(base_config.blocking_severities)),
        ))),
        Set(project_config_string_list(
            table,
            "disabled_rules",
            collect(base_config.disabled_rules),
        )),
        project_config_string_dict(
            table,
            "disabled_rule_explanations",
            base_config.disabled_rule_explanations,
        ),
        project_config_severity_dict(
            table,
            "rule_severity_overrides",
            base_config.rule_severity_overrides,
        ),
        project_config_string_dict(
            table,
            "rule_severity_override_explanations",
            base_config.rule_severity_override_explanations,
        ),
        project_config_string_dict(
            table,
            "blocking_severity_explanations",
            base_config.blocking_severity_explanations,
        ),
        project_config_bool(table, "include_tests", base_config.include_tests),
        project_config_string_list(table, "source_dir_names", base_config.source_dir_names),
        project_config_string_list(table, "test_dir_names", base_config.test_dir_names),
        project_config_string_dict(
            table,
            "source_path_explanations",
            base_config.source_path_explanations,
        ),
        project_config_string_dict(
            table,
            "test_path_explanations",
            base_config.test_path_explanations,
        ),
        project_config_string_dict(
            table,
            "source_path_exclusion_explanations",
            base_config.source_path_exclusion_explanations,
        ),
        project_config_string_dict(
            table,
            "test_path_exclusion_explanations",
            base_config.test_path_exclusion_explanations,
        ),
        project_advice_policy_explanation(table, base_config.agent_advice_allow_explanation),
    )
end

function project_config_string_list(
    table::Dict{String,Any},
    key::String,
    default::Vector{String},
)::Vector{String}
    value = get(table, key, nothing)
    value === nothing && return copy(default)
    value isa Vector{String} && return copy(value)
    value isa Vector{Any} || throw(ArgumentError("`$key` must be a string array"))
    result = String[]
    sizehint!(result, length(value))
    for item in value
        item isa String || throw(ArgumentError("`$key` entries must be strings"))
        push!(result, item)
    end
    return result
end

function project_config_string_dict(
    table::Dict{String,Any},
    key::String,
    default::Dict{String,String},
)::Dict{String,String}
    value = get(table, key, nothing)
    value === nothing && return copy(default)
    value isa Dict{String,String} && return copy(value)
    value isa Dict{String,Any} || throw(ArgumentError("`$key` must be a string table"))
    result = Dict{String,String}()
    for (name, item) in value
        item isa String || throw(ArgumentError("`$key.$name` must be a string"))
        result[name] = item
    end
    return result
end

function project_config_severity_dict(
    table::Dict{String,Any},
    key::String,
    default::Dict{String,JuliaDiagnosticSeverity},
)::Dict{String,JuliaDiagnosticSeverity}
    value = get(table, key, nothing)
    value === nothing && return copy(default)
    value isa Dict{String,Any} || throw(ArgumentError("`$key` must be a severity table"))
    result = Dict{String,JuliaDiagnosticSeverity}()
    for (rule_id, severity) in value
        severity isa String || throw(ArgumentError("`$key.$rule_id` must be a string"))
        result[rule_id] = parse_harness_severity(severity)
    end
    return result
end

function project_config_bool(
    table::Dict{String,Any},
    key::String,
    default::Bool,
)::Bool
    value = get(table, key, nothing)
    value === nothing && return default
    value isa Bool || throw(ArgumentError("`$key` must be true or false"))
    return value
end

function string_list(value)
    value isa AbstractVector || throw(ArgumentError("expected a string array, got $(typeof(value))"))
    String[string(item) for item in value]
end

function string_set(value)
    Set(string_list(value))
end

function string_dict(value)
    value isa AbstractDict || throw(ArgumentError("expected a string table, got $(typeof(value))"))
    Dict{String,String}(String(key) => string(item) for (key, item) in value)
end

function bool_value(value, name::AbstractString)
    value isa Bool || throw(ArgumentError("`$(name)` must be true or false"))
    value
end

function optional_string(value, name::AbstractString)
    isnothing(value) && return nothing
    value isa AbstractString || throw(ArgumentError("`$(name)` must be a string"))
    String(value)
end

function project_advice_policy_explanation(
    table::Dict{String,Any},
    default_explanation::Union{Nothing,String},
)
    policy_value = get(table, "advice", nothing)
    policy_value === nothing && return default_explanation
    policy_value isa String || throw(ArgumentError("`advice` must be a string"))
    policy = lowercase(strip(policy_value))
    policy == "gate" && return default_explanation
    if policy == "report"
        explanation_value = get(table, "advice_explanation", nothing)
        explanation_value === nothing && return ""
        explanation_value isa String ||
            throw(ArgumentError("`advice_explanation` must be a string"))
        explanation = explanation_value
        isnothing(explanation) && return ""
        return explanation
    end
    throw(ArgumentError("`advice` must be \"gate\" or \"report\""))
end

function severity_set(value)
    Set(parse_harness_severity.(string_list(value)))
end

function severity_dict(value)
    value isa AbstractDict ||
        throw(ArgumentError("expected a severity override table, got $(typeof(value))"))
    Dict{String,JuliaDiagnosticSeverity}(
        String(rule_id) => parse_harness_severity(string(severity)) for
        (rule_id, severity) in value
    )
end

function parse_harness_severity(value::AbstractString)
    normalized = lowercase(strip(value))
    normalized == "info" && return Info
    normalized == "warning" && return Warning
    normalized == "error" && return Error
    throw(ArgumentError("unknown AspJulia severity `$(value)`"))
end
