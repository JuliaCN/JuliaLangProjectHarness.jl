"""Knowledge-axis search packets for the Julia provider."""

const JULIA_KNOWLEDGE_AXIS_DETAILS = Dict{String,Dict{String,String}}(
    "env" => Dict(
        "authority" => "project-environment",
        "summary" => "Julia environment facts from Project.toml and package scope.",
        "next" => "search lang module package",
    ),
    "runtime-source" => Dict(
        "authority" => "local-source",
        "summary" => "Julia provider has no runtime checkout resolver; use owner/query/deps evidence.",
        "next" => "search deps <package>",
    ),
    "lang" => Dict(
        "authority" => "language-rules",
        "summary" => "Julia syntax and dispatch semantics visible to provider syntax facts.",
        "next" => "query <owner-path> --term <symbol>",
    ),
    "std" => Dict(
        "authority" => "standard-library",
        "summary" => "Julia Base/stdlib API facts for agent code generation.",
        "next" => "search api <symbol>",
    ),
    "capability" => Dict(
        "authority" => "provider-registry",
        "summary" => "Julia provider method and capability registry facts.",
        "next" => "guide",
    ),
    "extension" => Dict(
        "authority" => "ecosystem-extension",
        "summary" => "Package or extension-specific Julia ecosystem evidence; dependency search is manifest-first and import-usage backed.",
        "next" => "search dependency <package[@version][::api]>",
    ),
    "pattern" => Dict(
        "authority" => "executable-pattern",
        "summary" => "Executable syntax and API patterns backed by owner/deps/query evidence.",
        "next" => "search owner <path> items --query <symbol>",
    ),
    "compare" => Dict(
        "authority" => "semantic-comparison",
        "summary" => "Compare Julia project, dependency, or syntax axes using provider-owned facts.",
        "next" => "run each side through matching provider axis",
    ),
)

function julia_knowledge_search_packet(
    axis::AbstractString,
    terms::Vector{String},
    project_root::AbstractString;
    render_mode::AbstractString="seeds",
)
    detail = get(JULIA_KNOWLEDGE_AXIS_DETAILS, String(axis), JULIA_KNOWLEDGE_AXIS_DETAILS["capability"])
    query = join(terms, " ")
    facts = julia_knowledge_facts(String(axis), terms, project_root)
    packet = julia_search_packet_base(axis, render_mode, project_root; query=query)
    packet["header"]["fields"]["evidenceGrade"] = isempty(facts) ? "unknown" : "fact"
    packet["header"]["fields"]["authority"] = detail["authority"]
    packet["header"]["fields"]["fact"] = length(facts)
    packet["packages"] = facts
    packet["nodes"] = [
        Dict{String,Any}(
            "id" => "knowledge:$(String(axis)):$(fact["id"])",
            "kind" => "package",
            "fields" => merge(Dict{String,Any}("axis" => String(axis)), fact["fields"]),
        ) for fact in facts
    ]
    packet["hits"] = [
        Dict{String,Any}(
            "kind" => "text",
            "ownerPath" => ".",
            "symbol" => String(fact["id"]),
            "location" => Dict("path" => "."),
            "score" => isempty(terms) ? 1.0 : 2.0,
            "reason" => "$(String(axis)):$(detail["authority"])",
            "snippet" => string(fact["fields"]),
            "fields" => merge(
                Dict{String,Any}(
                    "axis" => String(axis),
                    "authority" => detail["authority"],
                ),
                fact["fields"],
            ),
        ) for fact in facts[1:min(length(facts), 12)]
    ]
    push!(
        packet["notes"],
        Dict(
            "kind" => "fact-scope",
            "message" => isempty(facts) ?
                "$(String(axis)) search did not find a provider-owned fact for the query; refine the axis query or route through owner/deps/query evidence" :
                detail["summary"],
        ),
    )
    push!(packet["notes"], Dict("kind" => "fact-scope", "message" => detail["next"]))
    packet["nextActions"] = [
        Dict{String,Any}("kind" => "lexical", "target" => isempty(query) ? String(axis) : query),
        Dict{String,Any}("kind" => "owner", "target" => "."),
    ]
    packet
end

function julia_knowledge_facts(axis::String, terms::Vector{String}, project_root::AbstractString)
    if axis == "env"
        return julia_filter_knowledge_facts([
            julia_knowledge_fact("Project.toml", axis; path="Project.toml", source="project-config"),
        ], terms, project_root)
    elseif axis == "runtime-source"
        return Dict{String,Any}[]
    elseif axis == "lang"
        return julia_filter_knowledge_facts([
            julia_knowledge_fact("multiple-dispatch", axis; syntax="function/method", selector="query owner --term"),
            julia_knowledge_fact("module-import", axis; syntax="using/import/export", selector="search owner items"),
            julia_knowledge_fact("macro", axis; syntax="@macro", selector="query owner --term"),
        ], terms, project_root)
    elseif axis == "std"
        return julia_filter_knowledge_facts([
            julia_knowledge_fact("Base", axis; symbol="Base", pattern="core language APIs"),
            julia_knowledge_fact("Pkg", axis; symbol="Pkg", pattern="package management"),
            julia_knowledge_fact("Test", axis; symbol="Test.@test", pattern="unit tests"),
        ], terms, project_root)
    elseif axis == "capability"
        return julia_filter_knowledge_facts([
            julia_knowledge_fact("owner-items", axis; command="search owner <path> items"),
            julia_knowledge_fact("dependency", axis; command="search dependency <dependency[@version][::api]>"),
            julia_knowledge_fact("deps", axis; command="search deps <dependency[@version][::api]>"),
            julia_knowledge_fact("query", axis; command="query <owner-path> --term <symbol>"),
        ], terms, project_root)
    elseif axis == "extension"
        return julia_filter_knowledge_facts(julia_project_dependency_facts(project_root, axis), terms, project_root)
    elseif axis == "pattern"
        return julia_filter_knowledge_facts([
            julia_knowledge_fact("dispatch-pattern", axis; command="query owner --term function then owner-items", qualitySignal="method owner before code read"),
            julia_knowledge_fact("dependency-api-usage", axis; command="search deps <dependency>::<api>", qualitySignal="dependency and local usage evidence"),
        ], terms, project_root)
    elseif axis == "compare"
        return [
            julia_knowledge_fact(
                "compare-query",
                axis;
                left=get(terms, 1, "-"),
                right=get(terms, 2, "-"),
                route="run each side through the matching provider axis and compare facts",
            ),
        ]
    end
    Dict{String,Any}[]
end

function julia_project_dependency_facts(project_root::AbstractString, axis::AbstractString)
    project_file = joinpath(project_root, "Project.toml")
    isfile(project_file) || return Dict{String,Any}[]
    facts = Dict{String,Any}[]
    for line in eachline(project_file)
        if occursin("=", line) && !startswith(strip(line), "[")
            name = strip(first(split(line, "=")))
            isempty(name) ||
                push!(facts, julia_knowledge_fact(name, axis; dependency=name, source="Project.toml"))
        end
    end
    facts
end

function julia_knowledge_fact(id::AbstractString, axis::AbstractString; kwargs...)
    Dict{String,Any}(
        "id" => String(id),
        "fields" => merge(
            Dict{String,Any}("axis" => String(axis)),
            Dict{String,Any}(String(key) => String(value) for (key, value) in kwargs),
        ),
    )
end

function julia_filter_knowledge_facts(
    facts::Vector{Dict{String,Any}},
    terms::Vector{String},
    project_root::AbstractString,
)
    existing_facts = [
        fact for fact in facts
        if !haskey(fact["fields"], "path") ||
            isfile(joinpath(project_root, String(fact["fields"]["path"])))
    ]
    isempty(terms) && return existing_facts
    [
        fact for fact in existing_facts
        if any(term -> occursin(lowercase(term), lowercase(string(fact))), terms)
    ]
end
