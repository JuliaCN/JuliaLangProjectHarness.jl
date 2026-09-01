function julia_project_json_string_array!(
    cursor::JuliaProjectJsonCursor,
)::Vector{String}
    values = String[]
    julia_project_json_take!(cursor, 0x5b)
    julia_project_json_skip_whitespace!(cursor)
    if cursor.position <= length(cursor.bytes) && cursor.bytes[cursor.position] == 0x5d
        cursor.position += 1
        return values
    end
    first = true
    while true
        first || julia_project_json_take!(cursor, 0x2c)
        first = false
        push!(values, julia_project_json_string!(cursor))
        julia_project_json_skip_whitespace!(cursor)
        if cursor.bytes[cursor.position] == 0x5d
            cursor.position += 1
            return values
        end
    end
end

function julia_project_json_candidate_generation!(
    cursor::JuliaProjectJsonCursor,
)::JuliaCandidateGeneration
    algorithm = nothing
    digest = nothing
    authorities = String[]
    julia_project_json_take!(cursor, 0x7b)
    first = true
    while true
        key = julia_project_json_next_key!(cursor, first)
        isnothing(key) && break
        first = false
        if key == "algorithm"
            algorithm = julia_project_json_string!(cursor)
        elseif key == "digest"
            digest = julia_project_json_string!(cursor)
        elseif key == "authorities"
            authorities = julia_project_json_string_array!(cursor)
        else
            julia_project_json_skip_value!(cursor)
        end
    end
    return (
        algorithm=something(algorithm, ""),
        digest=something(digest, ""),
        authorities=authorities,
    )
end

function julia_project_json_collection_scope!(
    cursor::JuliaProjectJsonCursor,
)::JuliaProjectResolutionCollectionScope
    kind = nothing
    owner_paths = String[]
    julia_project_json_take!(cursor, 0x7b)
    first = true
    while true
        key = julia_project_json_next_key!(cursor, first)
        isnothing(key) && break
        first = false
        if key == "kind"
            kind = julia_project_json_string!(cursor)
        elseif key == "ownerPaths"
            owner_paths = julia_project_json_string_array!(cursor)
        else
            julia_project_json_skip_value!(cursor)
        end
    end
    return (kind=something(kind, ""), ownerPaths=owner_paths)
end

function julia_project_json_policy_exclusion!(
    cursor::JuliaProjectJsonCursor,
)::JuliaProjectResolutionPolicyExclusion
    path = nothing
    authority = nothing
    reason_kind = nothing
    julia_project_json_take!(cursor, 0x7b)
    first = true
    while true
        key = julia_project_json_next_key!(cursor, first)
        isnothing(key) && break
        first = false
        if key == "path"
            path = julia_project_json_string!(cursor)
        elseif key == "authority"
            authority = julia_project_json_string!(cursor)
        elseif key == "reasonKind"
            reason_kind = julia_project_json_string!(cursor)
        else
            julia_project_json_skip_value!(cursor)
        end
    end
    return (
        path=something(path, ""),
        authority=something(authority, ""),
        reasonKind=something(reason_kind, ""),
    )
end

function julia_project_json_policy_exclusions!(
    cursor::JuliaProjectJsonCursor,
)::Vector{JuliaProjectResolutionPolicyExclusion}
    values = JuliaProjectResolutionPolicyExclusion[]
    julia_project_json_take!(cursor, 0x5b)
    julia_project_json_skip_whitespace!(cursor)
    if cursor.position <= length(cursor.bytes) && cursor.bytes[cursor.position] == 0x5d
        cursor.position += 1
        return values
    end
    first = true
    while true
        first || julia_project_json_take!(cursor, 0x2c)
        first = false
        push!(values, julia_project_json_policy_exclusion!(cursor))
        julia_project_json_skip_whitespace!(cursor)
        if cursor.bytes[cursor.position] == 0x5d
            cursor.position += 1
            return values
        end
    end
end

function julia_project_resolution_request_json(text::String)::JuliaProjectResolutionRequest
    cursor = JuliaProjectJsonCursor(text)
    schema_id = nothing
    schema_version = nothing
    language_id = nothing
    provider_id = nothing
    candidate_base = nothing
    candidate_generation = nothing
    collection_scope = nothing
    candidate_paths = String[]
    policy_exclusions = JuliaProjectResolutionPolicyExclusion[]
    julia_project_json_take!(cursor, 0x7b)
    first = true
    while true
        key = julia_project_json_next_key!(cursor, first)
        isnothing(key) && break
        first = false
        if key == "schemaId"
            schema_id = julia_project_json_string!(cursor)
        elseif key == "schemaVersion"
            schema_version = julia_project_json_string!(cursor)
        elseif key == "languageId"
            language_id = julia_project_json_string!(cursor)
        elseif key == "providerId"
            provider_id = julia_project_json_string!(cursor)
        elseif key == "candidateBase"
            candidate_base = julia_project_json_string!(cursor)
        elseif key == "candidateGeneration"
            candidate_generation = julia_project_json_candidate_generation!(cursor)
        elseif key == "collectionScope"
            collection_scope = julia_project_json_collection_scope!(cursor)
        elseif key == "candidatePaths"
            candidate_paths = julia_project_json_string_array!(cursor)
        elseif key == "policyExclusions"
            policy_exclusions = julia_project_json_policy_exclusions!(cursor)
        else
            julia_project_json_skip_value!(cursor)
        end
    end
    julia_project_json_skip_whitespace!(cursor)
    cursor.position == length(cursor.bytes) + 1 ||
        throw(ArgumentError("trailing project-resolution JSON input"))
    return (
        schemaId=something(schema_id, ""),
        schemaVersion=something(schema_version, ""),
        languageId=something(language_id, ""),
        providerId=something(provider_id, ""),
        candidateBase=something(candidate_base, ""),
        candidateGeneration=something(
            candidate_generation,
            (algorithm="", digest="", authorities=String[]),
        ),
        collectionScope=something(collection_scope, (kind="", ownerPaths=String[])),
        candidatePaths=candidate_paths,
        policyExclusions=policy_exclusions,
    )
end
