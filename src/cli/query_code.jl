const JULIA_MAX_EXACT_DIRECT_READ_LINES = 40

function julia_query_selector_range(selector::AbstractString)
    matched = match(r"^(.*):([0-9]+)(?::|-)([0-9]+)$", selector)
    isnothing(matched) && return (julia_query_owner_selector(String(selector)), nothing)
    start_line = Base.parse(Int, matched.captures[2])
    end_line = Base.parse(Int, matched.captures[3])
    if end_line < start_line
        start_line, end_line = end_line, start_line
    end
    return (julia_query_owner_selector(String(matched.captures[1])), (start_line, end_line))
end

function render_julia_query_code_selector(selector::AbstractString, project_root::AbstractString)::String
    owner_path, line_range = julia_query_selector_range(selector)
    source_path = isabspath(owner_path) ? owner_path : joinpath(project_root, owner_path)
    isfile(source_path) || return "# missing parser-visible Julia source $(owner_path)\n"

    if !isnothing(line_range)
        return render_julia_direct_read_source_window(owner_path, source_path, line_range)
    end

    parsed = parse_julia_file(source_path)
    facts = parsed.syntax_facts
    items = julia_query_candidate_items(facts, line_range)
    isempty(items) && (items = julia_query_inline_facts(facts, line_range))
    isempty(items) && return "# no compact Julia syntax facts for $(owner_path)\n"

    lines = String[]
    seen = Set{String}()
    for item in sort(items; by = julia_query_fact_line)
        item_line = julia_query_fact_line(item)
        item_end = julia_query_fact_end_line(item)
        julia_query_push_compact_line!(lines, seen, julia_query_fact_code(item))
        for fact in julia_query_projection_facts(facts)
            fact === item && continue
            fact_line = julia_query_fact_line(fact)
            julia_query_line_in_range(fact_line, line_range) || continue
            item_line <= fact_line <= item_end || continue
            julia_query_push_compact_line!(lines, seen, julia_query_fact_code(fact))
        end
    end

    return join(lines, "\n") * "\n"
end

function render_julia_query_read_packet_selector(selector::AbstractString, project_root::AbstractString)::String
    owner_path, line_range = julia_query_selector_range(selector)
    isnothing(line_range) && error("query direct-source-read read-packet requires a line selector")
    source_path = isabspath(owner_path) ? owner_path : joinpath(project_root, owner_path)
    isfile(source_path) || error("missing parser-visible Julia source $(owner_path)")
    packet = julia_direct_read_packet(owner_path, selector, project_root, source_path, line_range)
    return JSON.json(packet) * "\n"
end

function render_julia_direct_read_source_window(
    owner_path::AbstractString,
    source_path::AbstractString,
    line_range,
)::String
    lines = readlines(source_path)
    start_line, end_line = julia_direct_read_clamped_range(line_range, length(lines))
    line_count = end_line - start_line + 1
    if line_count > JULIA_MAX_EXACT_DIRECT_READ_LINES
        return render_julia_direct_read_plan(owner_path, line_range, start_line, end_line)
    end
    return join(lines[start_line:end_line], "\n") * "\n"
end

function julia_direct_read_packet(
    owner_path::AbstractString,
    selector::AbstractString,
    project_root::AbstractString,
    source_path::AbstractString,
    line_range,
)
    lines = readlines(source_path)
    start_line, end_line = julia_direct_read_clamped_range(line_range, length(lines))
    line_count = end_line - start_line + 1
    packet = Dict{String,Any}(
        "schemaId" => "agent.semantic-protocols.semantic-read-packet",
        "schemaVersion" => "1",
        "protocolId" => "agent.semantic-protocols.semantic-language",
        "protocolVersion" => "1",
        "languageId" => "julia",
        "providerId" => "asp-julia",
        "binary" => "asp-julia",
        "namespace" => "agent.semantic-protocols.languages.julia.asp-julia",
        "method" => "query/direct-source-read",
        "projectRoot" => abspath(project_root),
        "ownerPath" => String(owner_path),
        "selector" => String(selector),
        "fromHook" => "direct-source-read",
        "outputMode" => "read-packet",
        "truncated" => false,
        "notes" => Any[],
    )
    if line_count > JULIA_MAX_EXACT_DIRECT_READ_LINES
        packet["readPlan"] = julia_direct_read_plan_packet(owner_path, line_range, start_line, end_line)
    else
        text = join(lines[start_line:end_line], "\n")
        packet["sourceWindows"] = [
            Dict{String,Any}(
                "ownerPath" => String(owner_path),
                "location" => Dict{String,Any}(
                    "path" => String(owner_path),
                    "lineRange" => "$(start_line):$(end_line)",
                ),
                "read" => "$(owner_path):$(start_line):$(end_line)",
                "lineCount" => line_count,
                "reason" => "direct-selector",
                "text" => text,
                "lines" => [
                    Dict{String,Any}("number" => line_number, "text" => lines[line_number])
                    for line_number in start_line:end_line
                ],
                "truncated" => false,
            ),
        ]
    end
    return packet
end

function julia_direct_read_clamped_range(line_range, source_line_count::Int)
    start_line, requested_end = line_range
    start_line = max(1, start_line)
    end_line = min(requested_end, source_line_count)
    end_line >= start_line || error("query direct-source-read selector is outside source range")
    return (start_line, end_line)
end

function render_julia_direct_read_plan(owner_path::AbstractString, requested_range, start_line::Int, end_line::Int)::String
    windows = julia_direct_read_plan_windows(owner_path, start_line, end_line)
    header =
        "[read-plan] q=$(owner_path) selector=$(owner_path):$(requested_range[1]):$(requested_range[2]) " *
        "mode=range-frontier code=false reason=wide-selector maxWindow=$(JULIA_MAX_EXACT_DIRECT_READ_LINES) " *
        "alg=range-split frontier=$(julia_direct_read_frontier(length(windows))) " *
        "avoid=repeat-wide-read,manual-window-scan,raw-read"
    range_line =
        "|range path=$(owner_path) requested=$(requested_range[1]):$(requested_range[2]) " *
        "selected=$(start_line):$(end_line) matched=$(start_line):$(end_line) coverage=full density=unknown"
    window_lines = [
        "|window path=$(window["path"]) lineRange=$(window["lineRange"]) read=$(window["read"]) " *
        "lineCount=$(window["lineCount"]) reason=split" for window in windows
    ]
    return join(vcat([header, range_line], window_lines), "\n") * "\n"
end

function julia_direct_read_plan_packet(owner_path::AbstractString, requested_range, start_line::Int, end_line::Int)
    windows = julia_direct_read_plan_windows(owner_path, start_line, end_line)
    return Dict{String,Any}(
        "mode" => "range-frontier",
        "code" => false,
        "reason" => "wide-selector",
        "maxWindowLines" => JULIA_MAX_EXACT_DIRECT_READ_LINES,
        "algorithm" => "range-split",
        "frontier" => julia_direct_read_frontier_packet(windows),
        "avoid" => ["repeat-wide-read", "manual-window-scan", "raw-read"],
        "omit" => ["code"],
        "ranges" => [
            Dict{String,Any}(
                "path" => String(owner_path),
                "requested" => "$(requested_range[1]):$(requested_range[2])",
                "selected" => "$(start_line):$(end_line)",
                "matched" => "$(start_line):$(end_line)",
                "coverage" => "full",
                "density" => "unknown",
            ),
        ],
        "windows" => windows,
    )
end

function julia_direct_read_plan_windows(owner_path::AbstractString, start_line::Int, end_line::Int)
    windows = Dict{String,Any}[]
    current = start_line
    while current <= end_line
        window_end = min(current + JULIA_MAX_EXACT_DIRECT_READ_LINES - 1, end_line)
        push!(
            windows,
            Dict{String,Any}(
                "path" => String(owner_path),
                "lineRange" => "$(current):$(window_end)",
                "read" => "$(owner_path):$(current):$(window_end)",
                "lineCount" => window_end - current + 1,
                "reason" => "split",
            ),
        )
        current = window_end + 1
    end
    return windows
end

function julia_direct_read_frontier(window_count::Int)::String
    return join(julia_direct_read_frontier_list(window_count), ",")
end

function julia_direct_read_frontier_list(window_count::Int)::Vector{String}
    return [index == 1 ? "W.code" : "W$(index).code" for index in 1:window_count]
end

function julia_direct_read_frontier_packet(windows::Vector{Dict{String,Any}})
    return [
        Dict{String,Any}(
            "id" => index == 1 ? "W" : "W$(index)",
            "kind" => "window",
            "target" => "$(window["path"])@$(window["lineRange"])",
            "read" => window["read"],
            "action" => "code",
            "rank" => index,
            "reason" => "split",
        ) for (index, window) in enumerate(windows)
    ]
end

function julia_query_candidate_items(facts, line_range)::Vector{Any}
    candidates = Any[]
    append!(candidates, facts.functions)
    append!(candidates, facts.types)
    append!(candidates, facts.bindings)
    append!(candidates, facts.tests)
    isnothing(line_range) && return candidates
    return [item for item in candidates if julia_query_fact_overlaps_range(item, line_range)]
end

function julia_query_inline_facts(facts, line_range)::Vector{Any}
    inline = Any[]
    for fact in julia_query_projection_facts(facts)
        julia_query_line_in_range(julia_query_fact_line(fact), line_range) && push!(inline, fact)
    end
    return inline
end

function julia_query_projection_facts(facts)::Vector{Any}
    projected = Any[]
    append!(projected, facts.modules)
    append!(projected, facts.includes)
    append!(projected, facts.imports)
    append!(projected, facts.exports)
    append!(projected, facts.types)
    append!(projected, facts.bindings)
    append!(projected, facts.functions)
    append!(projected, facts.macro_invocations)
    append!(projected, facts.calls)
    append!(projected, facts.tests)
    return projected
end

function julia_query_fact_line(fact)::Int
    return getproperty(fact, :line)
end

function julia_query_fact_end_line(fact)::Int
    if hasproperty(fact, :expression)
        expression = getproperty(fact, :expression)
        isempty(expression) && return julia_query_fact_line(fact)
        return julia_query_fact_line(fact) + length(split(expression, '\n')) - 1
    end
    return julia_query_fact_line(fact)
end

function julia_query_fact_overlaps_range(fact, line_range)::Bool
    isnothing(line_range) && return true
    start_line, end_line = line_range
    fact_line = julia_query_fact_line(fact)
    fact_end = julia_query_fact_end_line(fact)
    return fact_line <= end_line && fact_end >= start_line
end

function julia_query_line_in_range(line::Int, line_range)::Bool
    isnothing(line_range) && return true
    start_line, end_line = line_range
    return start_line <= line <= end_line
end

function julia_query_fact_code(fact)::String
    if hasproperty(fact, :expression)
        expression = getproperty(fact, :expression)
        if !isempty(expression)
            return julia_query_compact_code_line(first(split(expression, '\n')))
        end
    end
    if hasproperty(fact, :name)
        return string(julia_query_fact_kind_name(fact), " ", getproperty(fact, :name))
    end
    return string(typeof(fact))
end

function julia_query_fact_kind_name(fact)::String
    hasproperty(fact, :kind) && return String(getproperty(fact, :kind))
    name = string(nameof(typeof(fact)))
    replace(name, r"^Julia|Syntax$" => "")
end

function julia_query_compact_code_line(text::AbstractString; limit::Int = 180)::String
    compact = replace(strip(text), r"\s+" => " ")
    length(compact) <= limit && return compact
    return first(compact, limit - 3) * "..."
end

function julia_query_push_compact_line!(lines::Vector{String}, seen::Set{String}, line::String)::Nothing
    isempty(line) && return nothing
    line in seen && return nothing
    push!(seen, line)
    push!(lines, line)
    return nothing
end
