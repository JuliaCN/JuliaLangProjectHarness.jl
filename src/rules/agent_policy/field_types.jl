const BROAD_PUBLIC_FIELD_TYPE_NAMES = Set([
    "AbstractArray",
    "AbstractDict",
    "AbstractSet",
    "AbstractString",
    "AbstractVector",
    "Any",
    "Function",
    "Integer",
    "Number",
    "Real",
    "Signed",
    "Unsigned",
])

function public_abstract_field_type_findings(
    parsed_files::Vector{ParsedJuliaFile},
    public_names::Set{String},
    rules::Dict{String,JuliaHarnessRule},
)
    findings = JuliaHarnessFinding[]
    for parsed in parsed_files
        parsed.report.is_valid || continue
        for type_fact in parsed.syntax_facts.types
            type_fact.kind == "struct" || continue
            name = terminal_public_name(type_fact.name)
            name in public_names || continue
            broad_fields = [
                field for field in type_fact.field_facts if is_broad_public_field_type(field)
            ]
            isempty(broad_fields) && continue
            first_field = first(broad_fields)
            push!(
                findings,
                finding_from_rule_typed(
                    rules[AGENT_JL_R025],
                    "Exported/public struct `$(name)` has broadly abstract fields: $(join(display_broad_field.(broad_fields), ", ")).",
                    SourceLocation(
                        parsed.report.path,
                        first_field.line,
                        first_field.column,
                    ),
                    source_line(parsed.source, first_field.line),
                    "replace broad field annotations with concrete fields or a typed parameterized data shape",
                ),
            )
        end
    end
    findings
end

function is_broad_public_field_type(field::JuliaTypeFieldSyntax)
    isnothing(field.type_annotation) && return false
    identifiers = annotation_identifier_names(field.type_annotation)
    any(is_broad_public_field_type_name, identifiers)
end

function is_broad_public_field_type_name(name::AbstractString)
    name in BROAD_PUBLIC_FIELD_TYPE_NAMES && return true
    startswith(String(name), "Abstract")
end

function display_broad_field(field::JuliaTypeFieldSyntax)
    "$(field.name)::$(something(field.type_annotation, "?"))"
end
