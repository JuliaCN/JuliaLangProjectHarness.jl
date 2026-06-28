module Criterion

export nested_route, summarize_orders

"Route a symbol through a deliberately nested decision shape."
function nested_route(kind::Symbol; ready::Bool, valid::Bool)
    if ready
        if valid
            if kind === :create
                return 1
            elseif kind === :update
                return 2
            elseif kind === :delete
                return 3
            else
                return 0
            end
        else
            return -1
        end
    else
        return -2
    end
end

"Summarize values through a deliberately broad accumulation loop."
function summarize_orders(values)
    total = 0
    count = 0
    flagged = String[]
    for value in values
        count += 1
        if value > 10
            push!(flagged, "large")
        else
            push!(flagged, "small")
        end
        total += value
    end
    return (; total, count, flagged)
end

end
