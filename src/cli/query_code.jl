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
        return string(getproperty(fact, :kind), " ", getproperty(fact, :name))
    end
    return string(typeof(fact))
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
