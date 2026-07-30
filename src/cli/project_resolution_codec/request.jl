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

function julia_project_json_repository_identity!(
    cursor::JuliaProjectJsonCursor,
)::JuliaRepositoryIdentity
    repository_id = nothing
    identity_basis = nothing
    git_common_dir = nothing
    julia_project_json_take!(cursor, 0x7b)
    first = true
    while true
        key = julia_project_json_next_key!(cursor, first)
        isnothing(key) && break
        first = false
        if key == "repositoryId"
            repository_id = julia_project_json_string!(cursor)
        elseif key == "identityBasis"
            identity_basis = julia_project_json_string!(cursor)
        elseif key == "gitCommonDir"
            git_common_dir = julia_project_json_string!(cursor)
        else
            julia_project_json_skip_value!(cursor)
        end
    end
    return (
        repositoryId=something(repository_id, ""),
        identityBasis=something(identity_basis, ""),
        gitCommonDir=something(git_common_dir, ""),
    )
end

function julia_project_json_worktree_identity!(
    cursor::JuliaProjectJsonCursor,
)::JuliaWorktreeIdentity
    worktree_id = nothing
    worktree_root = nothing
    git_dir = nothing
    julia_project_json_take!(cursor, 0x7b)
    first = true
    while true
        key = julia_project_json_next_key!(cursor, first)
        isnothing(key) && break
        first = false
        if key == "worktreeId"
            worktree_id = julia_project_json_string!(cursor)
        elseif key == "worktreeRoot"
            worktree_root = julia_project_json_string!(cursor)
        elseif key == "gitDir"
            git_dir = julia_project_json_string!(cursor)
        else
            julia_project_json_skip_value!(cursor)
        end
    end
    return (
        worktreeId=something(worktree_id, ""),
        worktreeRoot=something(worktree_root, ""),
        gitDir=something(git_dir, ""),
    )
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

function julia_project_json_candidate!(
    cursor::JuliaProjectJsonCursor,
)::JuliaRepositoryCandidate
    path = nothing
    state = nothing
    authority = nothing
    julia_project_json_take!(cursor, 0x7b)
    first = true
    while true
        key = julia_project_json_next_key!(cursor, first)
        isnothing(key) && break
        first = false
        if key == "path"
            path = julia_project_json_string!(cursor)
        elseif key == "state"
            state = julia_project_json_string!(cursor)
        elseif key == "authority"
            authority = julia_project_json_string!(cursor)
        else
            julia_project_json_skip_value!(cursor)
        end
    end
    return (
        path=something(path, ""),
        state=something(state, ""),
        authority=something(authority, ""),
    )
end

function julia_project_json_candidates!(
    cursor::JuliaProjectJsonCursor,
)::Vector{JuliaRepositoryCandidate}
    values = JuliaRepositoryCandidate[]
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
        push!(values, julia_project_json_candidate!(cursor))
        julia_project_json_skip_whitespace!(cursor)
        if cursor.bytes[cursor.position] == 0x5d
            cursor.position += 1
            return values
        end
    end
end

function julia_project_json_metrics!(
    cursor::JuliaProjectJsonCursor,
)::JuliaRepositoryCandidateMetrics
    index_entry_count = 0
    worktree_addition_count = 0
    candidate_count = 0
    full_workspace_reads = 0
    full_merkle_rebuilds = 0
    direct_db_opens = 0
    julia_project_json_take!(cursor, 0x7b)
    first = true
    while true
        key = julia_project_json_next_key!(cursor, first)
        isnothing(key) && break
        first = false
        if key == "indexEntryCount"
            index_entry_count = julia_project_json_int!(cursor)
        elseif key == "worktreeAdditionCount"
            worktree_addition_count = julia_project_json_int!(cursor)
        elseif key == "candidateCount"
            candidate_count = julia_project_json_int!(cursor)
        elseif key == "fullWorkspaceReads"
            full_workspace_reads = julia_project_json_int!(cursor)
        elseif key == "fullMerkleRebuilds"
            full_merkle_rebuilds = julia_project_json_int!(cursor)
        elseif key == "directDbOpens"
            direct_db_opens = julia_project_json_int!(cursor)
        else
            julia_project_json_skip_value!(cursor)
        end
    end
    return (
        indexEntryCount=index_entry_count,
        worktreeAdditionCount=worktree_addition_count,
        candidateCount=candidate_count,
        fullWorkspaceReads=full_workspace_reads,
        fullMerkleRebuilds=full_merkle_rebuilds,
        directDbOpens=direct_db_opens,
    )
end

function julia_project_json_snapshot!(
    cursor::JuliaProjectJsonCursor,
)::JuliaRepositoryCandidateSnapshot
    schema_id = nothing
    schema_version = nothing
    mode = nothing
    repository_identity = nothing
    worktree_identity = nothing
    candidate_generation = nothing
    candidates = JuliaRepositoryCandidate[]
    metrics = nothing
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
        elseif key == "mode"
            mode = julia_project_json_string!(cursor)
        elseif key == "repositoryIdentity"
            repository_identity = julia_project_json_repository_identity!(cursor)
        elseif key == "worktreeIdentity"
            worktree_identity = julia_project_json_worktree_identity!(cursor)
        elseif key == "candidateGeneration"
            candidate_generation = julia_project_json_candidate_generation!(cursor)
        elseif key == "candidates"
            candidates = julia_project_json_candidates!(cursor)
        elseif key == "metrics"
            metrics = julia_project_json_metrics!(cursor)
        else
            julia_project_json_skip_value!(cursor)
        end
    end
    return (
        schemaId=something(schema_id, ""),
        schemaVersion=something(schema_version, ""),
        mode=something(mode, ""),
        repositoryIdentity=something(
            repository_identity,
            (repositoryId="", identityBasis="", gitCommonDir=""),
        ),
        worktreeIdentity=something(
            worktree_identity,
            (worktreeId="", worktreeRoot="", gitDir=""),
        ),
        candidateGeneration=something(
            candidate_generation,
            (algorithm="", digest="", authorities=String[]),
        ),
        candidates=candidates,
        metrics=something(
            metrics,
            (
                indexEntryCount=0,
                worktreeAdditionCount=0,
                candidateCount=0,
                fullWorkspaceReads=0,
                fullMerkleRebuilds=0,
                directDbOpens=0,
            ),
        ),
    )
end

function julia_project_resolution_request_json(text::String)::JuliaProjectResolutionRequest
    cursor = JuliaProjectJsonCursor(text)
    schema_id = nothing
    schema_version = nothing
    language_id = nothing
    provider_id = nothing
    workspace_root = nothing
    snapshot = nothing
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
        elseif key == "workspaceRoot"
            workspace_root = julia_project_json_string!(cursor)
        elseif key == "repositoryCandidates"
            snapshot = julia_project_json_snapshot!(cursor)
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
        workspaceRoot=something(workspace_root, ""),
        repositoryCandidates=something(
            snapshot,
            (
                schemaId="",
                schemaVersion="",
                mode="",
                repositoryIdentity=(repositoryId="", identityBasis="", gitCommonDir=""),
                worktreeIdentity=(worktreeId="", worktreeRoot="", gitDir=""),
                candidateGeneration=(algorithm="", digest="", authorities=String[]),
                candidates=JuliaRepositoryCandidate[],
                metrics=(
                    indexEntryCount=0,
                    worktreeAdditionCount=0,
                    candidateCount=0,
                    fullWorkspaceReads=0,
                    fullMerkleRebuilds=0,
                    directDbOpens=0,
                ),
            ),
        ),
    )
end
