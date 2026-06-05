function run_julia_harness_search_cli(args::Vector{String}; out=stdout)
    length(args) >= 1 || error("search requires a view")
    view = args[1]
    if view == "workspace"
        options = parse_julia_search_args(args[2:end])
        if options.json
            print(out, render_julia_search_packet_json("workspace"; project_root=options.project_root, render_mode=options.render_view))
            print(out, "\n")
            return 0
        end
        options.render_view == "seeds" || error("unknown search render mode: $(options.render_view)")
        print(out, render_julia_search_graph("workspace"; project_root=options.project_root, render_mode=options.render_view))
    elseif view == "prime"
        options = parse_julia_search_args(args[2:end])
        if options.json
            print(
                out,
                render_julia_search_packet_json(
                    "prime";
                    project_root=options.project_root,
                    render_mode=options.render_view,
                ),
            )
            print(out, "\n")
            return 0
        end
        options.render_view == "seeds" || error("unknown search render mode: $(options.render_view)")
        print(out, render_julia_search_graph("prime"; project_root=options.project_root, render_mode=options.render_view))
    elseif view == "owner"
        length(args) >= 2 || error("search owner requires an owner path")
        owner_path = args[2]
        options = parse_julia_search_args(args[3:end])
        if options.json
            print(
                out,
                render_julia_search_packet_json(
                    "owner";
                    project_root=options.project_root,
                    render_mode=options.render_view,
                    owner_path,
                ),
            )
            print(out, "\n")
            return 0
        end
        options.render_view == "seeds" || error("unknown search render mode: $(options.render_view)")
        print(out, render_julia_search_graph("owner"; project_root=options.project_root, render_mode=options.render_view, owner_path=owner_path))
    elseif view == "fzf"
        length(args) >= 2 || error("search fzf requires a query")
        query = args[2]
        options = parse_julia_search_args(args[3:end])
        if options.json
            print(
                out,
                render_julia_search_packet_json(
                    "fzf";
                    project_root=options.project_root,
                    render_mode=options.render_view,
                    query,
                ),
            )
            print(out, "\n")
            return 0
        end
        options.render_view == "seeds" || error("unknown search render mode: $(options.render_view)")
        print(out, render_julia_search_graph("fzf"; project_root=options.project_root, render_mode=options.render_view, query=query))
    elseif view == "ingest"
        options = parse_julia_search_args(args[2:end])
        stdin_text = read(stdin, String)
        if options.json
            print(
                out,
                render_julia_search_packet_json(
                    "ingest";
                    project_root=options.project_root,
                    render_mode=options.render_view,
                    stdin_text,
                ),
            )
            print(out, "\n")
            return 0
        end
        options.render_view == "seeds" || error("unknown search render mode: $(options.render_view)")
        print(out, render_julia_search_graph("ingest"; project_root=options.project_root, render_mode=options.render_view, stdin_text=stdin_text))
    elseif view == "query"
        options = parse_julia_search_query_args(args[2:end])
        if options.json
            print(
                out,
                render_julia_search_packet_json(
                    "query";
                    project_root=options.project_root,
                    render_mode=options.render_view,
                    selector=options.selector,
                    terms=options.terms,
                    pipes=options.pipes,
                    from_hook=options.from_hook,
                    intent=options.intent,
                ),
            )
            print(out, "\n")
            return 0
        end
        options.render_view == "seeds" || error("unknown search render mode: $(options.render_view)")
        print(
            out,
            render_julia_search_graph("query"; project_root=options.project_root, render_mode=options.render_view, selector=options.selector, terms=options.terms, pipes=options.pipes, from_hook=options.from_hook, intent=options.intent),
        )
    elseif view == "policy"
        length(args) >= 2 || error("search policy requires a rule id or alias")
        query = args[2]
        options = parse_julia_search_args(args[3:end])
        if options.json
            print(
                out,
                render_julia_search_packet_json(
                    "policy";
                    project_root=options.project_root,
                    render_mode=options.render_view,
                    query,
                ),
            )
            print(out, "\n")
            return 0
        end
        options.render_view == "seeds" || error("unknown search render mode: $(options.render_view)")
        print(out, render_julia_search_graph("policy"; project_root=options.project_root, render_mode=options.render_view, query=query))
    else
        error("unknown search view: $(view)")
    end
    0
end
