using HTTP

const ASP_CLIENT_SERVER_REQUEST_PATH = "/v1/provider-runtime"
const ASP_CLIENT_SERVER_HEALTH_PATH = "/health"
const ASP_CLIENT_SERVER_SHUTDOWN_PATH = "/shutdown"

function asp_client_server_json_response(
    status::Int,
    payload::Dict{String,Any},
)::HTTP.Response
    return HTTP.Response(
        status;
        headers=["Content-Type" => "application/json"],
        body=JSON.json(payload),
    )
end

function asp_client_server_handler(
    cache::Base.RefValue{Union{Nothing,AspClientServerCacheEntry}},
    environment,
    shutdown::Channel{Nothing},
)
    return function (request::HTTP.Request)
        target = String(request.target)
        if request.method == "GET" && target == ASP_CLIENT_SERVER_HEALTH_PATH
            return asp_client_server_json_response(
                200,
                asp_client_server_contract(environment),
            )
        end
        if request.method == "POST" && target == ASP_CLIENT_SERVER_REQUEST_PATH
            length(request.body) <= ASP_CLIENT_SERVER_MAX_BODY_BYTES ||
                return asp_client_server_json_response(
                    400,
                    Dict{String,Any}(
                        "schemaId" => "agent.semantic-protocols.asp-client-server-error",
                        "schemaVersion" => "1",
                        "error" => "resident ASP Client Server body exceeds the admitted limit",
                    ),
                )
            frame = try
                JSON.parse(String(request.body), Dict{String,Any})
            catch caught
                return asp_client_server_json_response(
                    400,
                    asp_client_server_error_response(
                        Dict{String,Any}("requestId" => "invalid-request"),
                        caught,
                    ),
                )
            end
            response = try
                asp_client_server_response(frame, cache)
            catch caught
                asp_client_server_error_response(frame, caught)
            end
            return asp_client_server_json_response(200, response)
        end
        if request.method == "POST" && target == ASP_CLIENT_SERVER_SHUTDOWN_PATH
            @async begin
                yield()
                put!(shutdown, nothing)
            end
            return asp_client_server_json_response(
                200,
                Dict{String,Any}(
                    "schemaId" => "agent.semantic-protocols.asp-client-server-shutdown",
                    "schemaVersion" => "1",
                    "state" => "draining",
                ),
            )
        end
        return asp_client_server_json_response(
            404,
            Dict{String,Any}(
                "schemaId" => "agent.semantic-protocols.asp-client-server-error",
                "schemaVersion" => "1",
                "error" => "resident ASP Client Server route is not admitted",
            ),
        )
    end
end

"""Run one warm ASP Client Server owned by ASP Runtime Server."""
function run_asp_client_server(; environment=ENV, bootstrap_output=stdout)::Int
    address = get(environment, "ASP_CLIENT_SERVER_HOST", "127.0.0.1:0")
    parts = rsplit(address, ':'; limit=2)
    length(parts) == 2 || error("invalid ASP_CLIENT_SERVER_HOST: $address")
    host, port_text = parts
    !isempty(host) || error("invalid ASP_CLIENT_SERVER_HOST: $address")
    port = tryparse(Int, port_text)
    port !== nothing && 0 <= port <= 65535 ||
        error("invalid ASP_CLIENT_SERVER_HOST port: $address")
    cache = Ref{Union{Nothing,AspClientServerCacheEntry}}(nothing)
    shutdown = Channel{Nothing}(1)
    handler = asp_client_server_handler(cache, environment, shutdown)
    server = HTTP.serve!(handler, host, port; listenany=true, verbose=false)
    bound_port = HTTP.port(server)
    write(
        bootstrap_output,
        JSON.json(
            Dict{String,Any}(
        "schemaId" => "agent.semantic-protocols.asp-client-server-bootstrap",
                "schemaVersion" => "1",
                "providerId" => get(environment, "ASP_PROVIDER_ID", "asp-julia"),
                "transport" => "http-json",
                "state" => "ready",
                "endpoint" => "http://$host:$bound_port/",
            ),
        ),
        '\n',
    )
    flush(bootstrap_output)
    take!(shutdown)
    HTTP.forceclose(server)
    return 0
end
