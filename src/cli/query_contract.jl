const JULIA_QUERY_FACADE_VALUE_OPTIONS = Set([
    "--asp-provider-id",
    "--asp-parser-identity-digest",
    "--asp-query-pack-digest",
    "--source-snapshot-envelope",
])

function strip_julia_query_facade_options(args::Vector{String})
    normalized = String[]
    index = 1
    while index <= length(args)
        option = args[index]
        if option in JULIA_QUERY_FACADE_VALUE_OPTIONS
            index == length(args) && error("missing value for query option: $(option)")
            index += 2
            continue
        end
        push!(normalized, option)
        index += 1
    end
    normalized
end
