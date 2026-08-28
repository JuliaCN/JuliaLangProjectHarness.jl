const JULIA_PROJECTION_BATCH_REQUEST_SCHEMA =
    "agent.semantic-protocols.provider-language-projection-batch-request"
const JULIA_PROJECTION_BATCH_RESPONSE_SCHEMA =
    "agent.semantic-protocols.provider-language-projection-batch-response"
const JULIA_PROJECTION_BATCH_IDENTITY_SCHEMA =
    "agent.semantic-protocols.canonical-language-item-identity"

struct JuliaProjectionBatchOwner
    path::String
    digest::String
    source::Vector{UInt8}
end

function decode_julia_projection_batch(
    header::Dict{String,Any},
)::Tuple{Dict{String,Any},Vector{JuliaProjectionBatchOwner},Vector{JuliaProjectionBatchOwner}}
    get(header, "schemaId", nothing) == JULIA_PROJECTION_BATCH_REQUEST_SCHEMA &&
        get(header, "schemaVersion", nothing) == "1" &&
        get(header, "languageId", nothing) == "julia" &&
        get(header, "providerId", nothing) isa String &&
        !isempty(header["providerId"]) &&
        get(header, "generationRootDigest", nothing) isa String &&
        !isempty(header["generationRootDigest"]) &&
        get(header, "parserIdentityDigest", nothing) isa String &&
        !isempty(header["parserIdentityDigest"]) &&
        get(header, "queryPackDigest", nothing) isa String &&
        !isempty(header["queryPackDigest"]) ||
        error("projection batch request identity mismatch")
    owners = decode_julia_projection_batch_owners(get(header, "owners", nothing), "owners")
    auxiliary_owners = decode_julia_projection_batch_owners(
        get(header, "auxiliaryOwners", Any[]),
        "auxiliaryOwners",
    )
    paths = [owner.path for owner in vcat(owners, auxiliary_owners)]
    length(paths) == length(Set(paths)) || error("projection batch owner paths must be unique")
    return header, owners, auxiliary_owners
end

function decode_julia_projection_batch_owners(owner_headers, field::String)
    owner_headers isa Vector || error("projection batch $(field) must be an array")
    owners = JuliaProjectionBatchOwner[]
    for raw_owner in owner_headers
        raw_owner isa AbstractDict || error("projection batch owner must be an object")
        path = get(raw_owner, "ownerPath", nothing)
        digest = get(raw_owner, "sourceLeafDigest", nothing)
        path isa String && !isempty(path) &&
            digest isa String && !isempty(digest) ||
            error("projection batch owner is incomplete")
        normalized = normpath(path)
        !isabspath(path) && normalized != ".." && !startswith(normalized, "../") ||
            error("projection batch owner path escapes the workspace: $(path)")
        source_encoding = get(raw_owner, "sourceEncoding", nothing)
        source_text = get(raw_owner, "sourceText", nothing)
        source_bytes_base64 = get(raw_owner, "sourceBytesBase64", nothing)
        source = if source_encoding == "utf8" && source_text isa String &&
                    source_bytes_base64 === nothing
            Vector{UInt8}(codeunits(source_text))
        elseif source_encoding == "base64" && source_text === nothing &&
                source_bytes_base64 isa String
            try
                base64decode(source_bytes_base64)
            catch
                error("projection batch owner base64 is invalid: $(path)")
            end
        else
            error("projection batch owner source encoding mismatch: $(path)")
        end
        push!(owners, JuliaProjectionBatchOwner(replace(normalized, '\\' => '/'), digest, source))
    end
    return owners
end

function julia_projection_batch_line_range(source::Vector{UInt8}, line::Int, column::Int)
    line >= 1 || error("projection batch parser returned an invalid source line")
    starts = Int[0]
    append!(starts, index for (index, byte) in pairs(source) if byte == 0x0a)
    line <= length(starts) || error("projection batch parser returned a line outside owner bytes")
    line_start = starts[line]
    line_end = line == length(starts) ? length(source) : max(line_start, starts[line + 1] - 1)
    start = min(line_end, line_start + max(0, column))
    return start, line_end
end

function julia_projection_batch_item(
    entry::JuliaSearchIndexEntry,
    owner::JuliaProjectionBatchOwner,
)::Dict{String,Any}
    kind = asp_fact_kind(entry)
    name = String(entry.name)
    selector = "julia://$(owner.path)#item/$(kind)/$(name)"
    source_start, source_end = julia_projection_batch_line_range(
        owner.source,
        entry.location.line,
        entry.location.column,
    )
    return Dict{String,Any}(
        "itemId" => "item:$(selector)",
        "ownerId" => "owner:$(owner.path)",
        "kind" => kind,
        "name" => name,
        "selector" => selector,
        "sourceByteStart" => source_start,
        "sourceByteEnd" => source_end,
        "identity" => Dict{String,Any}(
            "schemaId" => JULIA_PROJECTION_BATCH_IDENTITY_SCHEMA,
            "schemaVersion" => "1",
            "languageId" => "julia",
            "kind" => kind,
            "symbol" => name,
            "scopes" => Any[],
        ),
        "projections" => Any[],
    )
end

function project_julia_projection_batch_owner(
    owner::JuliaProjectionBatchOwner,
    entries::Vector{JuliaSearchIndexEntry},
    project_root::AbstractString,
)::Dict{String,Any}
    items = Dict{String,Any}[]
    selectors = Set{String}()
    for entry in entries
        asp_project_path(entry.location.path, project_root) == owner.path || continue
        item = julia_projection_batch_item(entry, owner)
        selector = item["selector"]
        selector in selectors && continue
        push!(selectors, selector)
        push!(items, item)
    end
    return Dict{String,Any}(
        "ownerPath" => owner.path,
        "sourceLeafDigest" => owner.digest,
        "items" => items,
        "relations" => Any[],
    )
end

function render_julia_projection_batch(header::Dict{String,Any})::Dict{String,Any}
    header, owners, auxiliary_owners = decode_julia_projection_batch(header)
    projected = mktempdir() do project_root
        for owner in vcat(owners, auxiliary_owners)
            target = joinpath(project_root, split(owner.path, '/')...)
            mkpath(dirname(target))
            write(target, owner.source)
        end
        entries = julia_project_search_index(project_root; config=default_julia_harness_config())
        [project_julia_projection_batch_owner(owner, entries, project_root) for owner in owners]
    end
    return Dict{String,Any}(
        "schemaId" => JULIA_PROJECTION_BATCH_RESPONSE_SCHEMA,
        "schemaVersion" => "1",
        "languageId" => "julia",
        "providerId" => header["providerId"],
        "generationRootDigest" => header["generationRootDigest"],
        "owners" => projected,
    )
end
