const MOSHI_EXTENSION_CAPABILITY_LINES = [
    "syntax: native JuliaSyntax facts for Moshi @data/@match/@derive",
    "domain-model: typed domain carriers for stringly branch dispatch in source deps or optional extensions",
    "search: agent search and snapshots for Moshi modeling forms",
]

"""Return compact capability lines from the optional Moshi package extension."""
function moshi_extension_capabilities()
    extension_module = Base.get_extension(@__MODULE__, :AspJuliaMoshiExt)
    isnothing(extension_module) && return String[]
    extension_module.moshi_extension_capability_lines()
end

function moshi_extension_snapshot_lines(scope::JuliaProjectHarnessScope)
    [
        "- extension=$(extension_name) weakdeps=$(join(dependencies, ",")) " *
        "activation=$(extension_activation_state(scope, dependencies)) " *
        "capabilities=$(join(moshi_extension_capability_names(), ","))"
        for (extension_name, dependencies) in moshi_optional_extension_entries(scope)
    ]
end

function moshi_extension_search_entries(scope::JuliaProjectHarnessScope)
    [
        JuliaSearchIndexEntry(
            SourceLocation(scope.project_toml_path, 1, 0),
            "moshi_extension",
            "MoshiExtensionCapabilities:$(extension_name)",
            moshi_extension_search_detail(scope, dependencies),
            moshi_extension_search_text(extension_name, dependencies),
            [
                "moshi",
                "extension",
                "weakdep",
                "optional",
                "agent-capability",
                extension_activation_state(scope, dependencies),
            ],
        )
        for (extension_name, dependencies) in moshi_optional_extension_entries(scope)
    ]
end

function moshi_optional_extension_entries(scope::JuliaProjectHarnessScope)
    haskey(scope.weak_dependencies, "Moshi") || return Pair{String,Vector{String}}[]
    [
        Pair(extension_name, dependencies)
        for (extension_name, dependencies) in sort(collect(scope.extensions); by=first)
        if "Moshi" in dependencies
    ]
end

function moshi_extension_capability_evidence(
    scope::JuliaProjectHarnessScope,
    extension_name::AbstractString,
    dependencies::Vector{String},
)
    haskey(scope.weak_dependencies, "Moshi") || return Dict{String,String}()
    "Moshi" in dependencies || return Dict{String,String}()
    verification_evidence(
        "capabilities" => join(moshi_extension_capability_names(), ","),
        "capability_source" => "Moshi",
    )
end

function moshi_extension_search_detail(
    scope::JuliaProjectHarnessScope,
    dependencies::Vector{String},
)
    "Moshi optional extension weakdeps=$(join(dependencies, ",")) " *
    "activation=$(extension_activation_state(scope, dependencies)) " *
    "capabilities=$(join(moshi_extension_capability_names(), ","))"
end

function moshi_extension_search_text(
    extension_name::AbstractString,
    dependencies::Vector{String},
)
    join(
        vcat(
            [
                "Moshi",
                "extension",
                extension_name,
                "optional",
                "weakdeps",
                join(dependencies, " "),
            ],
            MOSHI_EXTENSION_CAPABILITY_LINES,
        ),
        " ",
    )
end

function moshi_extension_capability_names()
    [first(split(line, ":"; limit=2)) for line in MOSHI_EXTENSION_CAPABILITY_LINES]
end
