module AspJuliaApp

using AspJulia

if get(ENV, "ASP_JULIA_AOT_BUILD", "0") == "1"
    AspJulia.configure_juliac_aot_syntax!()
end

const NativeOutputIO = IOStream
const NativeInputIO = IOStream

function native_standard_iostream(name::String, fd::Cint)::IOStream
    duplicate_fd = ccall(:dup, Cint, (Cint,), fd)
    duplicate_fd >= 0 || error("failed to duplicate native stdin descriptor")
    return Base.fdio(name, duplicate_fd, true)
end

native_input_iostream(input::IOStream)::IOStream = input

function read_native_input(input::NativeInputIO)::String
    stream = native_input_iostream(input)
    try
        return read(stream, String)
    finally
        close(stream)
    end
end

function run_prime_route(args::Vector{String}, out::NativeOutputIO, err::NativeOutputIO)::Cint
    options = AspJulia.parse_julia_search_args(args[3:end])
    rendered = AspJulia.render_julia_native_prime_packet_json(
        options.project_root,
        options.render_view,
    )
    print(out, rendered)
    return Cint(0)
end

function run_owner_route(args::Vector{String}, out::NativeOutputIO, err::NativeOutputIO)::Cint
    length(args) >= 3 || error("search owner requires an owner path")
    owner_path = args[3]
    options = AspJulia.parse_julia_search_args(args[4:end])
    return Cint(AspJulia.run_julia_native_owner_items_query_cli(
        owner_path,
        options.query_terms,
        options.project_root,
        out,
    ))
end

function run_lexical_route(args::Vector{String}, out::NativeOutputIO, err::NativeOutputIO)::Cint
    query_terms, rest = AspJulia.parse_julia_lexical_search_args(args[3:end])
    options = AspJulia.parse_julia_search_args(rest)
    query = join(query_terms, " ")
    rendered = AspJulia.render_julia_native_lexical_packet_json(
        query,
        query_terms,
        options.project_root,
        options.render_view,
    )
    print(out, rendered)
    return Cint(0)
end

function run_ingest_route(
    args::Vector{String},
    out::NativeOutputIO,
    err::NativeOutputIO,
    input::NativeInputIO,
)::Cint
    options = AspJulia.parse_julia_search_args(args[3:end])
    stdin_text = read_native_input(input)
    rendered = AspJulia.render_julia_native_ingest_packet_json(
        stdin_text,
        options.project_root,
        options.render_view,
    )
    print(out, rendered)
    return Cint(0)
end

function run_serve_route(args, out, err)
    args == ["serve"] ||
        return invalid_provider_route("serve does not accept arguments", err)
    return Cint(AspJulia.run_asp_client_server())
end

run_dependency_topology_route(
    args::Vector{String},
    out::NativeOutputIO,
    err::NativeOutputIO,
)::Cint =
    Cint(AspJulia.run_julia_dependency_topology_cli(args[3:end], out))

run_export_route(
    args::Vector{String},
    out::NativeOutputIO,
    err::NativeOutputIO,
)::Cint =
    Cint(AspJulia.run_julia_harness_export_cli(args[2:end]; out))

function run_guide_route(args::Vector{String}, out::NativeOutputIO, err::NativeOutputIO)::Cint
    try
        project_root = length(args) >= 3 ? args[3] : pwd()
        print(out, AspJulia.julia_harness_agent_guide(project_root))
        return Cint(0)
    catch
        println(err, "error: guide route failed")
        return Cint(2)
    end
end

function invalid_provider_route(message::String, err::NativeOutputIO)::Cint
    println(err, "error: ", message)
    return Cint(2)
end

function run_cli(
    args::Vector{String},
    out::NativeOutputIO,
    err::NativeOutputIO,
    input::NativeInputIO,
)::Cint
    try
        isempty(args) && return invalid_provider_route("missing provider route", err)
        command = first(args)
        if command == "serve"
            return run_serve_route(args, out, err)
        elseif command == "search" && length(args) >= 2 && args[2] == "ingest"
            return run_ingest_route(args, out, err, input)
        end
        return run_cli_without_stdin(args, out, err)
    catch
        println(err, "error: provider route failed")
        return Cint(2)
    end
end

function run_cli_without_stdin(
    args::Vector{String},
    out::NativeOutputIO,
    err::NativeOutputIO,
)::Cint
    try
        isempty(args) && return invalid_provider_route("missing provider route", err)
        command = first(args)
        if command == "search"
            length(args) >= 2 || return invalid_provider_route("missing search route", err)
            route = args[2]
            route == "prime" && return run_prime_route(args, out, err)
            route == "owner" && return run_owner_route(args, out, err)
            route == "lexical" && return run_lexical_route(args, out, err)
            route == "dependency-topology" && return run_dependency_topology_route(args, out, err)
            return invalid_provider_route("unsupported search route: $(route)", err)
        elseif command == "export"
            return run_export_route(args, out, err)
        elseif command == "guide" || (command == "agent" && length(args) >= 2 && args[2] == "guide")
            return run_guide_route(args, out, err)
        end
        return invalid_provider_route("unsupported provider route: $(command)", err)
    catch
        println(err, "error: provider route failed")
        return Cint(2)
    end
end

function native_route_needs_input(args::Vector{String})::Bool
    return !isempty(args) &&
           (
               first(args) == "search" &&
               length(args) >= 2 &&
               args[2] == "ingest"
           )
end

function run_native_cli_concrete(
    args::Vector{String},
    out::O,
    err::E,
    input::I,
)::Cint where {O<:NativeOutputIO,E<:NativeOutputIO,I<:NativeInputIO}
    if native_route_needs_input(args)
        return run_cli(args, out, err, input)
    end
    return run_cli_without_stdin(args, out, err)
end

function run_native_cli(args::Vector{String})::Cint
    input = native_standard_iostream("asp-julia-native-stdin", Cint(0))
    out = native_standard_iostream("asp-julia-native-stdout", Cint(1))
    err = native_standard_iostream("asp-julia-native-stderr", Cint(2))
    try
        return run_native_cli_concrete(args, out, err, input)
    finally
        flush(out)
        flush(err)
        close(input)
        close(out)
        close(err)
    end
end

Base.Experimental.entrypoint(run_native_cli, (Vector{String},))

function run_app(args::Vector{String})::Cint
    return run_native_cli(args)
end

end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(AspJuliaApp.run_app(ARGS))
end

function (@main)(args::Vector{String})::Cint
    return AspJuliaApp.run_app(args)
end
