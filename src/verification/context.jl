function verification_task_index_from_context(context, config::AspJuliaConfig)
    records = JuliaVerificationTaskRecord[]
    for task_scope in vcat([context.scope], context.workspace_member_scopes)
        scoped_files = parsed_files_for_scope(task_scope, context.parsed_files)
        append!(records, verification_task_records_for_scope(task_scope, config, scoped_files))
    end
    sort!(records; by=record -> (record.kind, record.owner_path, record.fingerprint))
    JuliaVerificationTaskIndex(context.scope.project_root, records)
end

function verification_profile_index_from_context(context, config::AspJuliaConfig)
    candidates = JuliaVerificationProfileCandidate[]
    for candidate_scope in vcat([context.scope], context.workspace_member_scopes)
        scoped_files = parsed_files_for_scope(candidate_scope, context.parsed_files)
        append!(
            candidates,
            verification_profile_candidates_for_scope(candidate_scope, scoped_files),
        )
    end
    sort!(
        candidates;
        by=candidate -> (
            candidate.project_root,
            candidate.owner_path,
            join(candidate.responsibilities, ","),
        ),
    )
    JuliaVerificationProfileIndex(context.scope.project_root, candidates)
end
