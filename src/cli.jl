mutable struct JuliaHarnessCliOptions
    project_root::String
    json::Bool
    agent_snapshot::Bool
    advice::Bool
    verification_tasks::Bool
    verification_tasks_json::Bool
    verification_profile::Bool
    verification_profile_json::Bool
    verification_receipt_template::Bool
    verification_receipts_path::Union{Nothing,String}
    verification_receipts_json::Bool
    search_query::Union{Nothing,String}
    tags::Vector{String}
    limit::Int
    help::Bool
end

function default_julia_harness_cli_options()
    JuliaHarnessCliOptions(
        pwd(),
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        nothing,
        false,
        nothing,
        String[],
        25,
        false,
    )
end

"""Run the Julia project harness command-line interface."""
function run_julia_project_harness_cli(args=ARGS; out=stdout, err=stderr)
    try
        run_julia_project_harness_cli_checked(String.(collect(args)); out, err)
    catch caught
        println(err, "error: $(compact_error_message(caught))")
        2
    end
end

function run_julia_project_harness_cli_checked(args::Vector{String}; out=stdout, err=stderr)
    protocol_status = run_julia_project_harness_protocol_cli(args; out)
    !isnothing(protocol_status) && return protocol_status

    options = parse_julia_harness_cli_args(args)
    if options.help
        print(out, julia_harness_cli_usage())
        return 0
    end
    validate_julia_harness_cli_options(options)
    if !isnothing(options.search_query)
        results = search_julia_project(
            options.project_root,
            options.search_query;
            tags=options.tags,
            limit=options.limit,
        )
        print(out, render_julia_search_results(results; project_root=options.project_root))
        return 0
    elseif options.verification_tasks
        index = build_julia_verification_task_index(options.project_root)
        print(out, render_julia_verification_task_index(index))
        return 0
    elseif options.verification_tasks_json
        index = build_julia_verification_task_index(options.project_root)
        print(out, render_julia_verification_task_index_json(index))
        print(out, "\n")
        return 0
    elseif options.verification_profile
        profile = build_julia_project_verification_profile(options.project_root)
        print(out, render_julia_verification_profile(profile))
        return 0
    elseif options.verification_profile_json
        profile = build_julia_project_verification_profile(options.project_root)
        print(out, render_julia_verification_profile_json(profile))
        print(out, "\n")
        return 0
    elseif options.verification_receipt_template
        index = build_julia_verification_task_index(options.project_root)
        print(out, render_julia_verification_receipt_template(index))
        print(out, "\n")
        return 0
    elseif !isnothing(options.verification_receipts_path)
        index = build_julia_verification_task_index(options.project_root)
        receipts = read_julia_verification_receipts_json(options.verification_receipts_path)
        reviews = review_julia_verification_receipts(index, receipts)
        if options.verification_receipts_json
            print(out, render_julia_verification_receipt_reviews_json(reviews))
            print(out, "\n")
        else
            print(
                out,
                render_julia_verification_receipt_reviews(
                    reviews;
                    project_root=index.project_root,
                ),
            )
        end
        return all(is_julia_verification_receipt_review_clean, reviews) ? 0 : 1
    elseif options.agent_snapshot
        print(out, render_julia_project_harness_agent_snapshot(options.project_root))
        return 0
    end

    report = run_julia_project_harness(options.project_root)
    if options.json
        print(out, render_julia_project_harness_json(report))
        print(out, "\n")
    elseif options.advice
        print(out, render_julia_project_harness_advice(report))
    else
        print(out, render_julia_project_harness(report))
    end
    is_clean(report) ? 0 : 1
end

function run_julia_project_harness_protocol_cli(args::Vector{String}; out=stdout)
    isempty(args) && return nothing
    command = first(args)
    if command == "agent"
        length(args) >= 2 || error("agent requires a subcommand")
        args[2] == "guide" || error("unknown agent subcommand: $(args[2])")
        project_root = length(args) >= 3 ? args[3] : pwd()
        print(out, julia_harness_agent_guide(project_root))
        return 0
    elseif command == "search"
        return run_julia_harness_search_cli(args[2:end]; out)
    elseif command == "check"
        return run_julia_harness_check_cli(args[2:end]; out)
    end
    nothing
end

function run_julia_harness_search_cli(args::Vector{String}; out=stdout)
    length(args) >= 1 || error("search requires a view")
    view = args[1]
    if view == "prime"
        options = parse_julia_search_args(args[2:end])
        options.render_view == "seeds" || error("unknown search render mode: $(options.render_view)")
        print(out, render_julia_prime_search(options.project_root))
    elseif view == "owner"
        length(args) >= 2 || error("search owner requires an owner path")
        owner_path = args[2]
        options = parse_julia_search_args(args[3:end])
        options.render_view == "seeds" || error("unknown search render mode: $(options.render_view)")
        print(out, render_julia_owner_search(owner_path, options.pipes; project_root=options.project_root))
    elseif view == "fzf"
        length(args) >= 2 || error("search fzf requires a query")
        query = args[2]
        options = parse_julia_search_args(args[3:end])
        options.render_view == "seeds" || error("unknown search render mode: $(options.render_view)")
        print(out, render_julia_text_search(query, options.pipes; project_root=options.project_root))
    elseif view == "ingest"
        options = parse_julia_search_args(args[2:end])
        options.render_view == "seeds" || error("unknown search render mode: $(options.render_view)")
        print(out, render_julia_ingest_search(read(stdin, String), options.pipes; project_root=options.project_root))
    elseif view == "policy"
        length(args) >= 2 || error("search policy requires a rule id or alias")
        query = args[2]
        options = parse_julia_search_args(args[3:end])
        options.render_view == "seeds" || error("unknown search render mode: $(options.render_view)")
        print(out, render_julia_policy_search(query, options.pipes; project_root=options.project_root))
    else
        error("unknown search view: $(view)")
    end
    0
end

function run_julia_harness_check_cli(args::Vector{String}; out=stdout)
    isempty(args) || args[1] == "--changed" || error("unknown check option: $(args[1])")
    project_root = length(args) >= 2 ? args[2] : pwd()
    report = run_julia_project_harness(project_root)
    print(out, render_julia_project_harness(report))
    is_clean(report) ? 0 : 1
end

function parse_julia_harness_cli_args(args::Vector{String})
    options = default_julia_harness_cli_options()
    positionals = String[]
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg in ("-h", "--help")
            options.help = true
        elseif arg == "--json"
            options.json = true
        elseif arg == "--agent-snapshot"
            options.agent_snapshot = true
        elseif arg == "--advice"
            options.advice = true
        elseif arg == "--verification-tasks"
            options.verification_tasks = true
        elseif arg == "--verification-tasks-json"
            options.verification_tasks_json = true
        elseif arg == "--verification-profile"
            options.verification_profile = true
        elseif arg == "--verification-profile-json"
            options.verification_profile_json = true
        elseif arg == "--verification-receipt-template"
            options.verification_receipt_template = true
        elseif arg == "--verification-receipts"
            index += 1
            index <= length(args) || error("--verification-receipts requires a JSON file")
            options.verification_receipts_path = args[index]
        elseif arg == "--verification-receipts-json"
            index += 1
            index <= length(args) || error("--verification-receipts-json requires a JSON file")
            options.verification_receipts_path = args[index]
            options.verification_receipts_json = true
        elseif arg == "--search"
            index += 1
            index <= length(args) || error("--search requires a query")
            options.search_query = args[index]
        elseif arg == "--tag"
            index += 1
            index <= length(args) || error("--tag requires a tag")
            append!(options.tags, split_cli_tags(args[index]))
        elseif arg == "--limit"
            index += 1
            index <= length(args) || error("--limit requires an integer")
            options.limit = Base.parse(Int, args[index])
        elseif startswith(arg, "--")
            error("unknown option: $(arg)")
        else
            push!(positionals, arg)
        end
        index += 1
    end
    length(positionals) <= 1 || error("expected at most one PROJECT_ROOT")
    !isempty(positionals) && (options.project_root = only(positionals))
    options
end

function validate_julia_harness_cli_options(options::JuliaHarnessCliOptions)
    modes = count(identity, [
        options.json,
        options.agent_snapshot,
        options.advice,
        options.verification_tasks,
        options.verification_tasks_json,
        options.verification_profile,
        options.verification_profile_json,
        options.verification_receipt_template,
        !isnothing(options.verification_receipts_path),
        !isnothing(options.search_query),
    ])
    modes <= 1 || error("expected only one output mode")
    options.limit >= 0 || error("--limit must be non-negative")
    options
end

function split_cli_tags(value::AbstractString)
    [strip(tag) for tag in split(String(value), ',') if !isempty(strip(tag))]
end

function julia_harness_cli_usage()
    """
    julia-project-harness [agent guide | search policy RULE owner tests --view seeds | --json | --agent-snapshot | --advice | --verification-tasks | --verification-tasks-json | --verification-profile | --verification-profile-json | --verification-receipt-template | --verification-receipts FILE | --verification-receipts-json FILE | --search QUERY] [options] [PROJECT_ROOT]

    Compact text is the default agent-facing repair surface.
    Use agent guide to print provider-owned agent commands.
    Use search policy RULE owner tests --view seeds to resolve policy handles.
    Use --agent-snapshot to emit a low-noise project summary.
    Use --verification-tasks to emit agent-runnable verification duties.
    Use --verification-receipt-template to emit a JSON receipt skeleton.
    Use --verification-receipts FILE to review agent-submitted verification receipts.
    Use --verification-profile to emit the in-test verification profile.
    Use --search QUERY with --tag TAG and --limit N to query JuliaSyntax facts.
    """
end
