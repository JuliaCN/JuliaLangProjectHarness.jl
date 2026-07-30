function moshi_extension_repair_state(scope::JuliaProjectHarnessScope)
    haskey(scope.direct_dependencies, "Moshi") && return "direct_dep_enabled"
    has_moshi_optional_extension(scope) && return "extension_without_model"
    haskey(scope.weak_dependencies, "Moshi") && return "weakdep_without_extension"
    "missing_weakdep"
end

function moshi_extension_repair_name(scope::JuliaProjectHarnessScope)
    entries = moshi_optional_extension_entries(scope)
    !isempty(entries) && return first(first(entries))
    "$(something(scope.package_name, "<PackageName>"))MoshiExt"
end

function moshi_extension_repair_target(scope::JuliaProjectHarnessScope)
    "ext/$(moshi_extension_repair_name(scope)).jl"
end

function moshi_extension_repair_shape(scope::JuliaProjectHarnessScope)
    if project_moshi_policy(scope) == "enable"
        return moshi_source_repair_shape(scope)
    end
    extension_name = moshi_extension_repair_name(scope)
    join(
        [
            "[weakdeps].Moshi",
            "[compat].Moshi",
            "[extensions].$(extension_name) = \"Moshi\"",
            "[extras].Moshi",
            "[targets].test includes Moshi",
            "$(moshi_extension_repair_target(scope))",
        ],
        " | ",
    )
end

function moshi_source_repair_shape(
    scope::JuliaProjectHarnessScope;
    repair_target::AbstractString = moshi_source_repair_target(scope),
)
    join(
        [
            "[deps].Moshi",
            "[compat].Moshi",
            "$(repair_target) imports Moshi.Data and Moshi.Match",
        ],
        " | ",
    )
end

function moshi_source_repair_target(scope::JuliaProjectHarnessScope)
    entry_path = scope.package_entry_path
    if !isnothing(entry_path)
        return display_public_owner_path(scope, entry_path)
    end
    source_paths = sort(scope.source_paths)
    isempty(source_paths) && return "src/"
    display_public_owner_path(scope, first(source_paths))
end

function moshi_model_repair_target(scope::JuliaProjectHarnessScope)
    project_moshi_policy(scope) == "enable" && return moshi_source_repair_target(scope)
    moshi_extension_repair_target(scope)
end
