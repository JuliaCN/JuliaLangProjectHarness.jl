const MUTABLE_GLOBAL_INITIALIZER_NAMES = Set([
    "Base.RefValue",
    "Channel",
    "Condition",
    "Dict",
    "IdDict",
    "ReentrantLock",
    "Ref",
    "RefValue",
    "Set",
    "Threads.Atomic",
    "Vector",
    "WeakKeyDict",
])

const MUTABLE_GLOBAL_INITIALIZER_KINDS = Set([
    "ref",
    "vect",
])

function mutable_global_state_findings(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
    rules::Dict{String,JuliaHarnessRule},
)
    findings = JuliaHarnessFinding[]
    for parsed in parsed_files
        parsed.report.is_valid || continue
        is_test_path(scope, parsed.report.path) && continue
        for binding_fact in parsed.syntax_facts.bindings
            binding_fact.is_constant && continue
            is_mutable_global_initializer(binding_fact) || continue
            push!(
                findings,
                finding_from_rule_typed(
                    rules[AGENT_JL_R024],
                    "Package source defines mutable global binding `$(binding_fact.name)` initialized as $(mutable_global_initializer_summary(binding_fact)).",
                    SourceLocation(
                        parsed.report.path,
                        binding_fact.line,
                        binding_fact.column,
                    ),
                    source_line(parsed.source, binding_fact.line),
                    "move mutable state into an explicit owner object or document a const reset/lifecycle contract",
                ),
            )
        end
    end
    findings
end

function is_mutable_global_initializer(binding_fact::JuliaBindingSyntax)
    if !isnothing(binding_fact.initializer_name)
        name = binding_fact.initializer_name
        name in MUTABLE_GLOBAL_INITIALIZER_NAMES && return true
        terminal_public_name(name) in MUTABLE_GLOBAL_INITIALIZER_NAMES && return true
    end
    isnothing(binding_fact.initializer_kind) && return false
    binding_fact.initializer_kind in MUTABLE_GLOBAL_INITIALIZER_KINDS
end

function mutable_global_initializer_summary(binding_fact::JuliaBindingSyntax)
    !isnothing(binding_fact.initializer_name) && return "`$(binding_fact.initializer_name)`"
    !isnothing(binding_fact.initializer_kind) && return "`$(binding_fact.initializer_kind)`"
    "`<unknown>`"
end
