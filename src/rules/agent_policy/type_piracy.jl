const TYPE_PIRACY_CONTRACT_DOC_TOKENS = (
    "external method",
    "foreign function",
    "foreign type",
    "interop",
    "type piracy",
)

function external_method_extension_findings(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
    rules::Dict{String,AspJuliaRule},
)
    owned_type_names = package_owned_type_names(parsed_files)
    local_method_roots = package_method_roots(scope, parsed_files)
    findings = AspJuliaFinding[]
    for parsed in parsed_files
        parsed.report.is_valid || continue
        is_test_path(scope, parsed.report.path) && continue
        for function_fact in parsed.syntax_facts.functions
            root = external_method_root(function_fact, local_method_roots)
            isnothing(root) && continue
            has_owned_dispatch_argument(function_fact, owned_type_names) && continue
            has_type_piracy_contract_doc(parsed, function_fact) && continue
            push!(
                findings,
                finding_from_rule_typed(
                    rules[AGENT_JL_R021],
                    type_piracy_summary(function_fact, root, owned_type_names),
                    SourceLocation(
                        parsed.report.path,
                        function_fact.line,
                        function_fact.column,
                    ),
                    source_line(parsed.source, function_fact.line),
                    "dispatch the external method on a package-owned type or document the interop contract",
                ),
            )
        end
    end
    findings
end

function package_owned_type_names(parsed_files::Vector{ParsedJuliaFile})
    names = Set{String}()
    for parsed in parsed_files
        parsed.report.is_valid || continue
        for type_fact in parsed.syntax_facts.types
            push!(names, terminal_public_name(type_fact.name))
        end
    end
    names
end

function package_method_roots(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
)
    roots = Set{String}()
    !isnothing(scope.package_name) && push!(roots, scope.package_name)
    for parsed in parsed_files
        parsed.report.is_valid || continue
        for module_fact in parsed.syntax_facts.modules
            push!(roots, module_fact.name)
        end
    end
    roots
end

function external_method_root(
    function_fact::JuliaFunctionSyntax,
    local_method_roots::Set{String},
)
    parts = split(function_fact.name, ".")
    length(parts) >= 2 || return nothing
    root = first(parts)
    root in local_method_roots && return nothing
    root
end

function has_owned_dispatch_argument(
    function_fact::JuliaFunctionSyntax,
    owned_type_names::Set{String},
)
    isempty(owned_type_names) && return false
    dispatch_names = Set{String}()
    for argument in function_fact.argument_facts
        isnothing(argument.type_annotation) && continue
        union!(dispatch_names, annotation_identifier_names(argument.type_annotation))
    end
    for parameter in function_fact.where_parameters
        union!(dispatch_names, annotation_identifier_names(parameter))
    end
    !isempty(intersect(dispatch_names, owned_type_names))
end

function annotation_identifier_names(annotation::AbstractString)
    names = Set{String}()
    identifier = Char[]
    for character in annotation
        if isempty(identifier)
            Base.is_id_start_char(character) || continue
        elseif !Base.is_id_char(character)
            push!(names, String(identifier))
            empty!(identifier)
            Base.is_id_start_char(character) || continue
        end
        push!(identifier, character)
    end
    isempty(identifier) || push!(names, String(identifier))
    names
end

function has_type_piracy_contract_doc(
    parsed::ParsedJuliaFile,
    function_fact::JuliaFunctionSyntax,
)
    any(matching_function_docstrings(parsed, function_fact)) do text
        lower_text = lowercase(text)
        any(token -> occursin(token, lower_text), TYPE_PIRACY_CONTRACT_DOC_TOKENS)
    end
end

function matching_function_docstrings(
    parsed::ParsedJuliaFile,
    function_fact::JuliaFunctionSyntax,
)
    [
        docstring.text for docstring in parsed.syntax_facts.docstrings if
        docstring.target_kind == function_fact.kind &&
        docstring.target_name == function_fact.name
    ]
end

function type_piracy_summary(
    function_fact::JuliaFunctionSyntax,
    root::AbstractString,
    owned_type_names::Set{String},
)
    owned = isempty(owned_type_names) ? "<none>" : join(sort!(collect(owned_type_names)), ", ")
    "Method `$(function_fact.name)` extends external function root `$(root)` without a parser-visible package-owned dispatch type. Package-owned types: $(owned)."
end
