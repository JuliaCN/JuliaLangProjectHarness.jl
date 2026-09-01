using Base64
using HTTP
using JSON
using Test

@testset "resident ASP Client Server owns warm Julia lifecycle" begin
    environment = Dict(
        "ASP_PROVIDER_ARTIFACT_DIGEST" => "blake3-256:artifact",
        "ASP_PROVIDER_REGISTRATION_DIGEST" => "blake3-256:registration",
        "ASP_PROVIDER_RUNTIME_CONTRACT_DIGEST" => "blake3-256:contract",
        "ASP_PROVIDER_ID" => "asp-julia",
        "ASP_PROVIDER_LANGUAGE_ID" => "julia",
        "ASP_CLIENT_SERVER_HOST" => "127.0.0.1:0",
    )
    bootstrap_output = IOBuffer()
    task = @async AspJulia.run_asp_client_server(
        ; environment, bootstrap_output,
    )
    bootstrap_deadline = time() + 10
    while position(bootstrap_output) == 0 && !istaskdone(task) && time() < bootstrap_deadline
        sleep(0.01)
    end
    istaskfailed(task) && fetch(task)
    @test position(bootstrap_output) > 0
    seekstart(bootstrap_output)
    bootstrap = JSON.parse(readline(bootstrap_output), Dict{String,Any})
    endpoint = bootstrap["endpoint"]
    @test bootstrap["schemaId"] == "agent.semantic-protocols.asp-client-server-bootstrap"
    @test bootstrap["schemaVersion"] == "1"
    @test bootstrap["providerId"] == "asp-julia"
    @test bootstrap["transport"] == "http-json"
    @test bootstrap["state"] == "ready"
    @test startswith(endpoint, "http://127.0.0.1:")
    @test !startswith(endpoint, "http://127.0.0.1:0/")
    base_url = rstrip(endpoint, '/')

    health = HTTP.get("$base_url/health"; proxy=HTTP.ProxyConfig())
    health_payload = JSON.parse(String(health.body), Dict{String,Any})
    @test health.status == 200
    @test health_payload["providerId"] == "asp-julia"
    @test health_payload["languageId"] == "julia"
    @test health_payload["transport"] == "http-json"
    operations = health_payload["operations"]
    @test length(operations) == 2
    @test operations[1]["operation"] == "projection-batch"
    @test operations[2]["operation"] == "project-resolution"

    source = "function projected(value)\n    value\nend\n"
    projection_header = Dict{String,Any}(
        "schemaId" => "agent.semantic-protocols.provider-language-projection-batch-request",
        "schemaVersion" => "1",
        "languageId" => "julia",
        "providerId" => "asp-julia",
        "workspaceIdentity" => "workspace-test",
        "generationRootDigest" => "blake3-256:generation",
        "parserIdentityDigest" => "blake3-256:parser",
        "queryPackDigest" => "blake3-256:query-pack",
        "owners" => Any[
            Dict{String,Any}(
                "ownerPath" => "src/projected.jl",
                "sourceLeafDigest" => "blake3-256:owner",
                "sourceEncoding" => "utf8",
                "sourceText" => source,
            ),
        ],
        "auxiliaryOwners" => Any[
            Dict{String,Any}(
                "ownerPath" => "Project.toml",
                "sourceLeafDigest" => "blake3-256:config",
                "sourceEncoding" => "utf8",
                "sourceText" => "name = \"Fixture\"\n",
            ),
        ],
    )
    projection_request = Dict{String,Any}(
        "schemaId" => "agent.semantic-protocols.provider-runtime-request-frame",
        "schemaVersion" => "1",
        "requestId" => "projection-batch",
        "operation" => "projection-batch",
        "payload" => projection_header,
    )
    projection_response = HTTP.post(
        "$base_url/v1/provider-runtime",
        ["Content-Type" => "application/json"],
        JSON.json(projection_request);
        proxy=HTTP.ProxyConfig(),
    )
    projection_frame_response = JSON.parse(
        String(projection_response.body),
        Dict{String,Any},
    )
    projection_frame_response["outcome"] == "ready" ||
        error("resident projection failed: $(projection_frame_response)")
    @test projection_frame_response["outcome"] == "ready"
    projection_payload = projection_frame_response["payload"]
    @test projection_payload["schemaId"] ==
          "agent.semantic-protocols.provider-language-projection-batch-response"
    @test projection_payload["providerId"] == "asp-julia"
    @test only(projection_payload["owners"])["ownerPath"] == "src/projected.jl"
    @test any(
        item -> item["selector"] == "julia://src/projected.jl#item/function/projected",
        only(projection_payload["owners"])["items"],
    )

    unknown = Dict{String,Any}(
        "schemaId" => "agent.semantic-protocols.provider-runtime-request-frame",
        "schemaVersion" => "1",
        "requestId" => "unknown-operation",
        "operation" => "unknown-operation",
        "payload" => Dict{String,Any}(),
    )
    response = HTTP.post(
        "$base_url/v1/provider-runtime",
        ["Content-Type" => "application/json"],
        JSON.json(unknown);
        proxy=HTTP.ProxyConfig(),
    )
    response_payload = JSON.parse(String(response.body), Dict{String,Any})
    @test response.status == 200
    @test response_payload["outcome"] == "error"

    shutdown = HTTP.post("$base_url/shutdown", [], "{}"; proxy=HTTP.ProxyConfig())
    @test shutdown.status == 200
    @test fetch(task) == 0
end
