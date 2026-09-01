function run_julia_harness_query_cli(
    _args::Vector{String};
    out::IO = stdout,
)
    println(
        out,
        "Julia does not declare typed native exact projection; use `asp julia search owner <owner-path> items --query <symbol> --workspace <workspace-root> --view seeds` for discovery",
    )
    return 2
end
