function julia_source_read_error_message(err::SystemError)
    string("failed to read Julia source: SystemError: ", err.prefix)
end

function julia_syntax_parse_error_message(err::JuliaSyntax.ParseError)
    isempty(err.diagnostics) && return "failed to parse Julia source"
    diagnostic::JuliaSyntax.Diagnostic = first(err.diagnostics)
    string("ParseError: ", diagnostic.message)
end

function parse_julia_file(path::AbstractString)
    path_string = String(path)
    source = try
        read(path_string, String)
    catch err
        error_message = err isa SystemError ?
                        julia_source_read_error_message(err) :
                        "failed to read Julia source"
        return ParsedJuliaFile(
            JuliaFileReport(path_string, false, error_message),
            "",
            JuliaSourceMetrics(0, 0),
            empty_julia_native_syntax_facts(),
        )
    end

    metrics = source_metrics(source)
    try
        syntax = JuliaSyntax.parseall(JuliaSyntax.SyntaxNode, source; filename=path_string)
        ParsedJuliaFile(
            JuliaFileReport(path_string, true, nothing),
            source,
            metrics,
            julia_native_syntax_facts(syntax, path_string),
        )
    catch err
        error_message = err isa JuliaSyntax.ParseError ?
                        julia_syntax_parse_error_message(err) :
                        "failed to parse Julia source"
        ParsedJuliaFile(
            JuliaFileReport(path_string, false, error_message),
            source,
            metrics,
            empty_julia_native_syntax_facts(),
        )
    end
end

function source_line(source::AbstractString, line::Int)
    lines = split(source, '\n'; keepempty=true)
    1 <= line <= length(lines) ? lines[line] : nothing
end

function source_metrics(source::AbstractString)
    lines = split(source, '\n'; keepempty=true)
    JuliaSourceMetrics(length(lines), count(line -> !isempty(strip(line)), lines))
end

function empty_julia_native_syntax_facts()
    JuliaNativeSyntaxFacts(
        false,
        JuliaModuleSyntax[],
        JuliaIncludeSyntax[],
        JuliaImportSyntax[],
        JuliaExportSyntax[],
        JuliaFunctionSyntax[],
        JuliaTypeSyntax[],
        JuliaBindingSyntax[],
        JuliaMacroInvocationSyntax[],
        JuliaMoshiSyntax[],
        JuliaCallSyntax[],
        JuliaDocstringSyntax[],
        JuliaIdentifierSyntax[],
        JuliaTestSyntax[],
        JuliaSourceObservation[],
    )
end

function julia_native_syntax_facts(
    syntax::JuliaSyntax.SyntaxNode,
    source_path::String,
)::JuliaNativeSyntaxFacts
    collector = JuliaSyntaxFactCollector(
        JuliaModuleSyntax[],
        JuliaIncludeSyntax[],
        JuliaImportSyntax[],
        JuliaExportSyntax[],
        JuliaFunctionSyntax[],
        JuliaTypeSyntax[],
        JuliaBindingSyntax[],
        JuliaMacroInvocationSyntax[],
        JuliaMoshiSyntax[],
        JuliaCallSyntax[],
        JuliaDocstringSyntax[],
        JuliaIdentifierSyntax[],
        JuliaTestSyntax[],
        JuliaSourceObservation[],
    )
    collect_julia_syntax_facts!(collector, syntax, source_path)
    JuliaNativeSyntaxFacts(
        true,
        collector.modules,
        collector.includes,
        collector.imports,
        collector.exports,
        collector.functions,
        collector.types,
        collector.bindings,
        collector.macro_invocations,
        collector.moshi,
        collector.calls,
        collector.docstrings,
        collector.identifiers,
        collector.tests,
        collector.source_observations,
    )
end

mutable struct JuliaSyntaxFactCollector
    modules::Vector{JuliaModuleSyntax}
    includes::Vector{JuliaIncludeSyntax}
    imports::Vector{JuliaImportSyntax}
    exports::Vector{JuliaExportSyntax}
    functions::Vector{JuliaFunctionSyntax}
    types::Vector{JuliaTypeSyntax}
    bindings::Vector{JuliaBindingSyntax}
    macro_invocations::Vector{JuliaMacroInvocationSyntax}
    moshi::Vector{JuliaMoshiSyntax}
    calls::Vector{JuliaCallSyntax}
    docstrings::Vector{JuliaDocstringSyntax}
    identifiers::Vector{JuliaIdentifierSyntax}
    tests::Vector{JuliaTestSyntax}
    source_observations::Vector{JuliaSourceObservation}
end

function collect_julia_syntax_facts!(
    collector::JuliaSyntaxFactCollector,
    node::JuliaSyntax.SyntaxNode,
    source_path::String,
    parent::JuliaSyntax.SyntaxNode,
    local_scope_depth::Int,
)::Nothing
    kind = syntax_kind(node)
    if kind == "doc"
        docstring_fact = docstring_syntax_from_node(node)
        !isnothing(docstring_fact) && push!(collector.docstrings, docstring_fact)
    elseif is_module_node(node)
        push!(collector.modules, module_syntax_from_node(node))
    elseif is_call_named(node, "include")
        push!(collector.includes, include_syntax_from_call(node, source_path))
    elseif kind in ("using", "import")
        append!(collector.imports, import_syntax_from_node(node))
    elseif kind in ("export", "public")
        push!(collector.exports, export_syntax_from_node(node))
    elseif kind in ("function", "macro")
        function_fact = function_syntax_from_node(node)
        !isnothing(function_fact) && push!(collector.functions, function_fact)
    elseif kind in ("struct", "abstract", "primitive")
        type_fact = type_syntax_from_node(node)
        !isnothing(type_fact) && push!(collector.types, type_fact)
    elseif kind in ("const", "global")
        binding_fact = binding_syntax_from_node(node)
        !isnothing(binding_fact) && push!(collector.bindings, binding_fact)
    elseif kind == "=" && local_scope_depth == 0 && !is_wrapped_binding_assignment(parent)
        binding_fact = binding_syntax_from_node(node)
        !isnothing(binding_fact) && push!(collector.bindings, binding_fact)
    elseif kind == "macrocall"
        macro_invocation = macro_invocation_syntax_from_node(node)
        if !isnothing(macro_invocation)
            push!(collector.macro_invocations, macro_invocation)
            moshi_fact = moshi_syntax_from_macro_invocation(node, macro_invocation)
            !isnothing(moshi_fact) && push!(collector.moshi, moshi_fact)
            test_fact = test_syntax_from_macro_invocation(node, macro_invocation)
            !isnothing(test_fact) && push!(collector.tests, test_fact)
            observation = source_observation_from_macro_invocation(node, macro_invocation)
            !isnothing(observation) && push!(collector.source_observations, observation)
        end
    elseif kind == "call"
        call_fact = call_syntax_from_node(node, parent)
        !isnothing(call_fact) && push!(collector.calls, call_fact)
    elseif kind == "Identifier"
        identifier_fact = identifier_syntax_from_node(node, parent)
        !isnothing(identifier_fact) && push!(collector.identifiers, identifier_fact)
    end
    signature = kind in ("function", "macro") ? function_signature_node(node) : nothing
    child_local_scope_depth = local_scope_depth + (starts_local_syntax_scope(kind) ? 1 : 0)
    for child in syntax_children(node)
        child === signature && continue
        collect_julia_syntax_facts!(
            collector,
            child,
            source_path,
            node,
            child_local_scope_depth,
        )
    end
    return nothing
end

function collect_julia_syntax_facts!(
    collector::JuliaSyntaxFactCollector,
    node::JuliaSyntax.SyntaxNode,
    source_path::String,
)::Nothing
    collect_julia_syntax_facts!(collector, node, source_path, node, 0)
    return nothing
end

function starts_local_syntax_scope(kind::AbstractString)
    kind in ("function", "macro", "struct", "let", "for", "while", "try", "do", "->")
end

function is_wrapped_binding_assignment(parent::Union{Nothing,JuliaSyntax.SyntaxNode})
    isnothing(parent) && return false
    syntax_kind(parent) in ("const", "global", "local")
end
