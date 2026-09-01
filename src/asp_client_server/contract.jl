const ASP_CLIENT_SERVER_MAX_BODY_BYTES = 64 * 1024 * 1024
const ASP_CLIENT_SERVER_REQUEST_SCHEMA =
    "agent.semantic-protocols.provider-runtime-request-frame"
const ASP_CLIENT_SERVER_RESPONSE_SCHEMA =
    "agent.semantic-protocols.provider-runtime-response-frame"
const ASP_CLIENT_SERVER_RECEIPT_SCHEMA =
    "agent.semantic-protocols.provider-runtime-contract-receipt"
const ASP_CLIENT_SERVER_PROJECT_RESOLUTION_OPERATION = Dict(
    "operation" => "project-resolution",
    "requestSchema" => Dict("schemaId" => "agent.semantic-protocols.provider-project-resolution-request", "schemaVersion" => "1"),
    "responseSchema" => Dict("schemaId" => "agent.semantic-protocols.provider-project-resolution-response", "schemaVersion" => "1"),
)
const ASP_CLIENT_SERVER_PROJECTION_BATCH_OPERATION = Dict(
    "operation" => "projection-batch",
    "requestSchema" => Dict("schemaId" => "agent.semantic-protocols.provider-language-projection-batch-request", "schemaVersion" => "1"),
    "responseSchema" => Dict("schemaId" => "agent.semantic-protocols.provider-language-projection-batch-response", "schemaVersion" => "1"),
)

function asp_client_server_contract(environment)::Dict{String,Any}
    return Dict{String,Any}(
        "schemaId" => ASP_CLIENT_SERVER_RECEIPT_SCHEMA,
        "schemaVersion" => "1",
        "providerId" => get(environment, "ASP_PROVIDER_ID", ""),
        "languageId" => get(environment, "ASP_PROVIDER_LANGUAGE_ID", ""),
        "artifactDigest" => get(environment, "ASP_PROVIDER_ARTIFACT_DIGEST", ""),
        "registrationDigest" => get(environment, "ASP_PROVIDER_REGISTRATION_DIGEST", ""),
        "contractDigest" => get(environment, "ASP_PROVIDER_RUNTIME_CONTRACT_DIGEST", ""),
        "transport" => "http-json",
        "operations" => Any[
            ASP_CLIENT_SERVER_PROJECTION_BATCH_OPERATION,
            ASP_CLIENT_SERVER_PROJECT_RESOLUTION_OPERATION,
        ],
    )
end

function asp_client_server_project_resolution(payload::Dict{String,Any})::Dict{String,Any}
    request = julia_project_resolution_request_json(JSON.json(payload))
    return julia_project_resolution_response(julia_project_resolution(request))
end

struct AspClientServerCacheEntry
    operation::String
    request_payload::Dict{String,Any}
    response_payload::Dict{String,Any}
end

function asp_client_server_response(
    frame::Dict{String,Any},
    cache::Base.RefValue{Union{Nothing,AspClientServerCacheEntry}},
)::Dict{String,Any}
    request_id = get(frame, "requestId", nothing)
    operation = get(frame, "operation", nothing)
    payload = get(frame, "payload", nothing)
    if get(frame, "schemaId", nothing) != ASP_CLIENT_SERVER_REQUEST_SCHEMA ||
       get(frame, "schemaVersion", nothing) != "1" ||
       !(request_id isa String) || isempty(request_id) ||
       !(operation isa String) || !(payload isa AbstractDict)
        error("resident Julia HTTP provider request identity is invalid")
    end
    payload = Dict{String,Any}(payload)
    operation in ("projection-batch", "project-resolution") ||
        error("resident Julia HTTP provider operation is not admitted: $(operation)")
    cached = cache[]
    response_payload = if !isnothing(cached) &&
                          cached.operation == operation &&
                          cached.request_payload == payload
        cached.response_payload
    else
        projected = operation == "projection-batch" ?
            render_julia_projection_batch(payload) :
            asp_client_server_project_resolution(payload)
        cache[] = AspClientServerCacheEntry(operation, payload, projected)
        projected
    end
    return Dict{String,Any}(
        "schemaId" => ASP_CLIENT_SERVER_RESPONSE_SCHEMA,
        "schemaVersion" => "1",
        "requestId" => request_id,
        "outcome" => "ready",
        "payload" => response_payload,
    )
end

function asp_client_server_error_response(
    frame::Dict{String,Any},
    caught,
)::Dict{String,Any}
    return Dict{String,Any}(
        "schemaId" => ASP_CLIENT_SERVER_RESPONSE_SCHEMA,
        "schemaVersion" => "1",
        "requestId" => string(get(frame, "requestId", "invalid-request")),
        "outcome" => "error",
        "error" => julia_cli_error_message(caught),
    )
end
