function literal_path_argument(node::JuliaSyntax.SyntaxNode)
    literal = string_literal_value(node)
    !isnothing(literal) && return literal
    is_call_named(node, "joinpath") || return nothing
    segments = String[]
    for argument in call_arguments(node)
        segment = string_literal_value(argument)
        isnothing(segment) && return nothing
        push!(segments, segment)
    end
    isempty(segments) && return nothing
    path::String = first(segments)
    for index::Int in 2:length(segments)
        path = joinpath(path, segments[index])
    end
    path
end

function string_literal_value(node::JuliaSyntax.SyntaxNode)
    syntax_kind(node) == "string" || return nothing
    children = syntax_children(node)
    isempty(children) && return ""
    all(child -> syntax_kind(child) == "String", children) || return nothing
    join(String(JuliaSyntax.sourcetext(child)) for child in children)
end

function import_path_names(node::JuliaSyntax.SyntaxNode)
    paths = String[]
    collect_import_path_names!(paths, node)
    paths
end

function collect_import_path_names!(paths::Vector{String}, node::JuliaSyntax.SyntaxNode)
    if syntax_kind(node) == "importpath"
        push!(paths, join(identifier_texts(node), "."))
        return
    end
    for child in syntax_children(node)
        collect_import_path_names!(paths, child)
    end
end

function first_identifier_text(node::JuliaSyntax.SyntaxNode)
    for child in syntax_children(node)
        syntax_kind(child) == "Identifier" && return String(JuliaSyntax.sourcetext(child))
    end
    nothing
end

function identifier_texts(node::JuliaSyntax.SyntaxNode)
    names = String[]
    collect_identifier_texts!(names, node)
    names
end

function collect_identifier_texts!(names::Vector{String}, node::JuliaSyntax.SyntaxNode)
    if syntax_kind(node) == "Identifier"
        push!(names, String(JuliaSyntax.sourcetext(node)))
        return
    end
    for child in syntax_children(node)
        collect_identifier_texts!(names, child)
    end
end

function is_call_named(node::JuliaSyntax.SyntaxNode, name::AbstractString)
    syntax_kind(node) == "call" || return false
    children = syntax_children(node)
    isempty(children) && return false
    first = children[1]
    syntax_kind(first) == "Identifier" && String(JuliaSyntax.sourcetext(first)) == name
end

function call_arguments(node::JuliaSyntax.SyntaxNode)
    children = syntax_children(node)
    length(children) <= 1 ? JuliaSyntax.SyntaxNode[] : children[2:end]
end

function syntax_children(node::JuliaSyntax.SyntaxNode)
    children = JuliaSyntax.children(node)
    isnothing(children) ? JuliaSyntax.SyntaxNode[] : collect(children)
end

syntax_kind(node::JuliaSyntax.SyntaxNode) = String(Symbol(JuliaSyntax.kind(node)))
