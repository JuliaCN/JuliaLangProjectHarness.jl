function julia_ingest_search_packet(stdin_text::AbstractString, project_root::AbstractString; render_mode::AbstractString="seeds")
    candidate_paths = ingest_candidate_paths(stdin_text, project_root)
    tests = filter(is_julia_test_path, candidate_paths)
    owners = filter(path -> !(path in tests), candidate_paths)
    packet = julia_search_packet_base("ingest", render_mode, project_root)
    input_lines = [line for line in split(String(stdin_text), '\n') if !isempty(line)]
    packet["inputDetection"] = Dict{String,Any}(
        "source" => "path-list",
        "lineCount" => length(input_lines),
        "byteCount" => sizeof(String(stdin_text)),
        "sample" => compact_cli_value(isempty(input_lines) ? "" : first(input_lines)),
    )
    julia_search_attach_frontier!(
        packet,
        owners,
        tests;
        algorithm="stdin-candidate-paths",
        scope="ingest",
        summary="Resolved stdin candidate paths",
    )
end
