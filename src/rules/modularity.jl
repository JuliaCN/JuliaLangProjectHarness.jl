function evaluate_modularity_rules(
    scope::Union{Nothing,JuliaProjectHarnessScope},
    parsed_files::Vector{ParsedJuliaFile},
)
    isnothing(scope) && return JuliaHarnessFinding[]
    rules = rules_by_id()
    findings = JuliaHarnessFinding[]
    parsed_by_path = Dict(parsed.report.path => parsed for parsed in parsed_files)
    for parsed in parsed_files
        parsed.report.is_valid || continue
        for include in parsed.syntax_facts.includes
            if !include.is_literal
                push!(
                    findings,
                    finding_from_rule_typed(
                        rules[JULIA_MOD_R003],
                        "Parser facts found `$(include.expression)`, whose target is not statically known.",
                        SourceLocation(parsed.report.path, include.line, include.column),
                        source_line(parsed.source, include.line),
                        "replace dynamic include with a literal include or document the exception",
                    ),
                )
            elseif !isfile(include.resolved_target)
                push!(
                    findings,
                    finding_from_rule_typed(
                        rules[JULIA_MOD_R004],
                        "`$(include.expression)` resolves to missing file `$(include.resolved_target)`.",
                        SourceLocation(parsed.report.path, include.line, include.column),
                        source_line(parsed.source, include.line),
                        "create the included file or update the literal include path",
                    ),
                )
            end
        end
    end
    append!(findings, project_jl_owner_budget_findings(scope, parsed_files, rules))
    append!(findings, include_cycle_findings(parsed_by_path, rules))
    append!(findings, orphan_source_findings(scope, parsed_files, parsed_by_path, rules))
    append!(findings, generic_owner_bucket_findings(scope, parsed_files, rules))
    findings
end

function project_jl_owner_budget_findings(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
    rules::Dict{String,JuliaHarnessRule},
)
    findings = JuliaHarnessFinding[]
    for parsed in parsed_files
        parsed.report.is_valid || continue
        owner_root = first_project_jl_owner_root(scope, parsed.report.path)
        isnothing(owner_root) && continue
        if !isnothing(scope.package_entry_path) && parsed.report.path == scope.package_entry_path
            has_literal_includes(parsed) && continue
            parsed.metrics.nonblank_line_count > MAX_ENTRY_FACADE_NONBLANK_LINES || continue
            push!(
                findings,
                finding_from_rule_typed(
                    rules[JULIA_MOD_R001],
                    "Package entry `$(parsed.report.path)` has $(parsed.metrics.nonblank_line_count) nonblank lines and no literal include owners.",
                    SourceLocation(parsed.report.path, 1, 0),
                    source_line(parsed.source, 1),
                    "move implementation into included owner files and keep the entry module as a facade",
                ),
            )
            continue
        end
        parsed.metrics.nonblank_line_count > MAX_SOURCE_FILE_NONBLANK_LINES || continue
        push!(
            findings,
            finding_from_rule_typed(
                rules[JULIA_MOD_R002],
                "Julia owner file `$(parsed.report.path)` has $(parsed.metrics.nonblank_line_count) nonblank lines.",
                SourceLocation(parsed.report.path, 1, 0),
                source_line(parsed.source, 1),
                project_jl_owner_budget_label(scope, parsed.report.path),
            ),
        )
    end
    findings
end

function project_jl_owner_budget_label(scope::JuliaProjectHarnessScope, path::AbstractString)
    if any(test_path -> is_path_under(path, test_path), scope.test_paths)
        return "split this test owner into focused included test files"
    elseif any(extension_path -> is_path_under(path, extension_path), scope.extension_paths)
        return "split this extension owner into focused extension files"
    end
    "split this file into named Julia owner files with literal includes"
end

function include_cycle_findings(
    parsed_by_path::Dict{String,ParsedJuliaFile},
    rules::Dict{String,JuliaHarnessRule},
)
    findings = JuliaHarnessFinding[]
    states = Dict{String,Symbol}()
    reported_cycles = Set{String}()
    for path in sort!(collect(keys(parsed_by_path)))
        get(states, path, :unseen) == :unseen || continue
        visit_include_graph!(
            findings,
            states,
            reported_cycles,
            String[],
            path,
            parsed_by_path,
            rules,
        )
    end
    findings
end

function visit_include_graph!(
    findings::Vector{JuliaHarnessFinding},
    states::Dict{String,Symbol},
    reported_cycles::Set{String},
    stack::Vector{String},
    path::String,
    parsed_by_path::Dict{String,ParsedJuliaFile},
    rules::Dict{String,JuliaHarnessRule},
)
    states[path] = :visiting
    push!(stack, path)
    parsed = parsed_by_path[path]
    for include in parsed.syntax_facts.includes
        include.is_literal || continue
        target = include.resolved_target
        isnothing(target) && continue
        haskey(parsed_by_path, target) || continue
        target_index = findfirst(==(target), stack)
        if !isnothing(target_index)
            cycle_paths = vcat(stack[target_index:end], [target])
            cycle_key = join(sort(unique(cycle_paths)), "\0")
            if !(cycle_key in reported_cycles)
                push!(reported_cycles, cycle_key)
                push!(
                    findings,
                    finding_from_rule_typed(
                        rules[JULIA_MOD_R005],
                        "Literal include cycle detected: $(join(cycle_paths, " -> ")).",
                        SourceLocation(parsed.report.path, include.line, include.column),
                        source_line(parsed.source, include.line),
                        "break the include cycle by moving shared declarations behind one acyclic owner",
                    ),
                )
            end
            continue
        end
        get(states, target, :unseen) == :unseen || continue
        visit_include_graph!(findings, states, reported_cycles, stack, target, parsed_by_path, rules)
    end
    pop!(stack)
    states[path] = :visited
end

function orphan_source_findings(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
    parsed_by_path::Dict{String,ParsedJuliaFile},
    rules::Dict{String,JuliaHarnessRule},
)
    isnothing(scope.package_entry_path) && return JuliaHarnessFinding[]
    source_files = Set(
        parsed.report.path for parsed in parsed_files if any(
            source_path -> is_path_under(parsed.report.path, source_path),
            scope.source_paths,
        )
    )
    reachable = reachable_source_files(scope.package_entry_path, parsed_by_path)
    orphaned = sort!(collect(setdiff(source_files, reachable)))
    findings = JuliaHarnessFinding[]
    for path in orphaned
        push!(
            findings,
            finding_from_rule_typed(
                rules[JULIA_MOD_R006],
                "`$(path)` is under `src/` but is not reachable from `$(scope.package_entry_path)` through literal includes.",
                SourceLocation(path, 1, 0),
                source_line(parsed_by_path[path].source, 1),
                "include this source from the package entry graph or document why it is intentionally separate",
            ),
        )
    end
    findings
end

function reachable_source_files(entry_path::String, parsed_by_path::Dict{String,ParsedJuliaFile})
    reachable = Set{String}()
    pending = [entry_path]
    while !isempty(pending)
        path = pop!(pending)
        path in reachable && continue
        push!(reachable, path)
        parsed = get(parsed_by_path, path, nothing)
        isnothing(parsed) && continue
        for include in parsed.syntax_facts.includes
            include.is_literal || continue
            isnothing(include.resolved_target) && continue
            include.resolved_target in reachable && continue
            haskey(parsed_by_path, include.resolved_target) && push!(pending, include.resolved_target)
        end
    end
    reachable
end

function normalized_absolute_path(path::AbstractString)
    normpath(abspath(String(path)))
end

function path_has_root_prefix(path::String, root::String)
    path == root && return true
    separator = string(Base.Filesystem.path_separator)
    root_prefix = endswith(root, separator) ? root : root * separator
    startswith(path, root_prefix)
end

function is_path_under(path::AbstractString, root::AbstractString)
    normalized_path = normalized_absolute_path(path)
    normalized_root = normalized_absolute_path(root)
    path_has_root_prefix(normalized_path, normalized_root)
end

function generic_owner_bucket_findings(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
    rules::Dict{String,JuliaHarnessRule},
)
    findings = JuliaHarnessFinding[]
    for parsed in parsed_files
        source_root = first_source_root(scope, parsed.report.path)
        isnothing(source_root) && continue
        generic_segment = first_generic_owner_segment(source_root, parsed.report.path)
        isnothing(generic_segment) && continue
        push!(
            findings,
            finding_from_rule_typed(
                rules[JULIA_MOD_R007],
                "`$(parsed.report.path)` is under generic source owner `$(generic_segment)`.",
                SourceLocation(parsed.report.path, 1, 0),
                source_line(parsed.source, 1),
                "rename the source directory to the domain owner it represents",
            ),
        )
    end
    findings
end

function first_source_root(scope::JuliaProjectHarnessScope, path::AbstractString)
    for source_path in scope.source_paths
        is_path_under(path, source_path) && return source_path
    end
    nothing
end

function first_project_jl_owner_root(scope::JuliaProjectHarnessScope, path::AbstractString)
    for owner_root in vcat(scope.source_paths, scope.extension_paths, scope.test_paths)
        is_path_under(path, owner_root) && return owner_root
    end
    nothing
end

function first_generic_owner_segment(source_root::AbstractString, path::AbstractString)
    normalized_root = normalized_absolute_path(source_root)
    owner_directory = normalized_absolute_path(dirname(path))
    path_has_root_prefix(owner_directory, normalized_root) || return nothing
    owner_directory == normalized_root && return nothing
    separator = string(Base.Filesystem.path_separator)
    root_prefix = endswith(normalized_root, separator) ?
                  normalized_root :
                  normalized_root * separator
    relative = String(chopprefix(owner_directory, root_prefix))
    for segment in splitpath(relative)
        normalized = lowercase(String(segment))
        normalized in GENERIC_SOURCE_OWNER_SEGMENTS && return segment
    end
    nothing
end
