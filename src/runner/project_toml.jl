struct JuliaProjectTomlFacts
    project_root::String
    path::Union{Nothing,String}
    parse_error::Union{Nothing,String}
    package_name::Union{Nothing,String}
    package_uuid::Union{Nothing,String}
    entryfile::Union{Nothing,String}
    direct_dependencies::Dict{String,String}
    weak_dependencies::Dict{String,String}
    extra_dependencies::Dict{String,String}
    targets::Dict{String,Vector{String}}
    compat::Dict{String,String}
    sources::Dict{String,Dict{String,String}}
    extensions::Dict{String,Vector{String}}
    workspace_projects::Vector{String}
    source_dependency_projects::Vector{String}
end

function parse_project_toml_facts(project_path::AbstractString)
    start = project_search_start(project_path)
    project_toml = Base.current_project(start)
    if isnothing(project_toml)
        root = abspath(start)
        return empty_project_toml_facts(root, joinpath(root, "Project.toml"))
    end
    root = dirname(project_toml)
    parsed = try
        TOML.parsefile(project_toml)
    catch err
        parse_error = if err isa TOML.ParserError
            project_parse_error_message(err)
        else
            "failed to parse Project.toml"
        end
        return empty_project_toml_facts(
            root,
            project_toml;
            parse_error=parse_error,
        )
    end
    toml_project_facts(parsed, root, project_toml)
end

function toml_project_facts(
    parsed::Dict{String,Any},
    root::String,
    project_toml::String,
)::JuliaProjectTomlFacts
    package_name = toml_optional_string(parsed, "name")
    package_uuid = toml_optional_string(parsed, "uuid")
    entryfile = toml_optional_string(parsed, "entryfile")
    (package_name.valid && package_uuid.valid && entryfile.valid) ||
        return invalid_project_toml_facts(root, project_toml, "package identity")
    direct_dependencies = toml_string_table(parsed, "deps")
    weak_dependencies = toml_string_table(parsed, "weakdeps")
    extra_dependencies = toml_string_table(parsed, "extras")
    targets = toml_string_vector_table(parsed, "targets")
    compat = toml_string_table(parsed, "compat")
    sources = toml_source_table(parsed)
    extensions = toml_extension_table(parsed)
    workspace_projects = toml_workspace_projects(parsed)
    isnothing(direct_dependencies) &&
        return invalid_project_toml_facts(root, project_toml, "deps")
    isnothing(weak_dependencies) &&
        return invalid_project_toml_facts(root, project_toml, "weakdeps")
    isnothing(extra_dependencies) &&
        return invalid_project_toml_facts(root, project_toml, "extras")
    isnothing(targets) &&
        return invalid_project_toml_facts(root, project_toml, "targets")
    isnothing(compat) &&
        return invalid_project_toml_facts(root, project_toml, "compat")
    isnothing(sources) &&
        return invalid_project_toml_facts(root, project_toml, "sources")
    isnothing(extensions) &&
        return invalid_project_toml_facts(root, project_toml, "extensions")
    isnothing(workspace_projects) &&
        return invalid_project_toml_facts(root, project_toml, "workspace.projects")
    declared_target_dependencies = Set{String}()
    union!(declared_target_dependencies, keys(direct_dependencies))
    union!(declared_target_dependencies, keys(weak_dependencies))
    union!(declared_target_dependencies, keys(extra_dependencies))
    for dependencies in values(targets), dependency in dependencies
        dependency in declared_target_dependencies ||
            return empty_project_toml_facts(
                root,
                project_toml;
                parse_error="target dependency `$(dependency)` is not declared",
            )
    end
    source_dependency_projects::Vector{String} =
        string_source_dependency_projects(root, sources)
    JuliaProjectTomlFacts(
        root,
        project_toml,
        nothing,
        package_name.value,
        package_uuid.value,
        entryfile.value,
        direct_dependencies,
        weak_dependencies,
        extra_dependencies,
        targets,
        compat,
        sources,
        extensions,
        workspace_projects,
        source_dependency_projects,
    )
end

function empty_project_toml_facts(
    project_root::AbstractString,
    project_toml::Union{Nothing,String};
    parse_error::Union{Nothing,String}=nothing,
)
    JuliaProjectTomlFacts(
        String(project_root),
        project_toml,
        parse_error,
        nothing,
        nothing,
        nothing,
        Dict{String,String}(),
        Dict{String,String}(),
        Dict{String,String}(),
        Dict{String,Vector{String}}(),
        Dict{String,String}(),
        Dict{String,Dict{String,String}}(),
        Dict{String,Vector{String}}(),
        String[],
        String[],
    )
end

function compact_error_message(message::String)::String
    replace(message, r"\s+" => " ")
end

function project_parse_error_message(err::TOML.ParserError)::String
    message = isnothing(err.str) ? "failed to parse Project.toml" : err.str
    compact_error_message(message)
end

function invalid_project_toml_facts(
    root::String,
    project_toml::String,
    field::String,
)::JuliaProjectTomlFacts
    empty_project_toml_facts(
        root,
        project_toml;
        parse_error="invalid Project.toml field `$(field)`",
    )
end

function toml_optional_string(
    table::Dict{String,Any},
    key::String,
)::NamedTuple{(:valid,:value),Tuple{Bool,Union{Nothing,String}}}
    value = get(table, key, nothing)
    isnothing(value) && return (valid=true, value=nothing)
    value isa String || return (valid=false, value=nothing)
    (valid=true, value=value)
end

function toml_string_table(
    table::Dict{String,Any},
    key::String,
)::Union{Nothing,Dict{String,String}}
    value = get(table, key, nothing)
    isnothing(value) && return Dict{String,String}()
    value isa Dict{String,Any} || return nothing
    result = Dict{String,String}()
    for (name, item) in value
        item isa String || return nothing
        result[name] = item
    end
    result
end

function toml_string_vector_table(
    table::Dict{String,Any},
    key::String,
)::Union{Nothing,Dict{String,Vector{String}}}
    value = get(table, key, nothing)
    isnothing(value) && return Dict{String,Vector{String}}()
    value isa Dict{String,Any} || return nothing
    result = Dict{String,Vector{String}}()
    for (name, items) in value
        items isa Vector{String} || return nothing
        result[name] = copy(items)
    end
    result
end

function toml_source_table(
    table::Dict{String,Any},
)::Union{Nothing,Dict{String,Dict{String,String}}}
    value = get(table, "sources", nothing)
    isnothing(value) && return Dict{String,Dict{String,String}}()
    value isa Dict{String,Any} || return nothing
    sources = Dict{String,Dict{String,String}}()
    for (name, source_value) in value
        source_value isa Dict{String,Any} || return nothing
        source = Dict{String,String}()
        for (key, item) in source_value
            item isa String || return nothing
            source[key] = item
        end
        sources[name] = source
    end
    sources
end

function toml_extension_table(
    table::Dict{String,Any},
)::Union{Nothing,Dict{String,Vector{String}}}
    value = get(table, "extensions", nothing)
    isnothing(value) && return Dict{String,Vector{String}}()
    value isa Dict{String,Any} || return nothing
    extensions = Dict{String,Vector{String}}()
    for (name, extension_value) in value
        if extension_value isa String
            extensions[name] = [extension_value]
        elseif extension_value isa Vector{String}
            extensions[name] = copy(extension_value)
        else
            return nothing
        end
    end
    extensions
end

function toml_workspace_projects(
    table::Dict{String,Any},
)::Union{Nothing,Vector{String}}
    workspace = get(table, "workspace", nothing)
    isnothing(workspace) && return String[]
    workspace isa Dict{String,Any} || return nothing
    projects = get(workspace, "projects", nothing)
    isnothing(projects) && return String[]
    projects isa Vector{String} || return nothing
    copy(projects)
end

function string_source_dependency_projects(
    project_root::AbstractString,
    sources::Dict{String,Dict{String,String}},
)
    projects = String[]
    seen = Set{String}()
    for source in values(sources)
        path = get(source, "path", "")
        isempty(path) && continue
        member_root = isabspath(path) ? normpath(path) : normpath(joinpath(project_root, path))
        isfile(joinpath(member_root, "Project.toml")) || continue
        member_root in seen && continue
        push!(seen, member_root)
        push!(projects, path)
    end
    sort!(projects)
end
