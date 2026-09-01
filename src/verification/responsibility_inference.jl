const JULIA_VERIFICATION_RESPONSIBILITY_ORDER = [
    "public_api",
    "external_dependency",
    "persistence",
    "security_boundary",
    "latency_sensitive",
    "availability_critical",
]

const JULIA_VERIFICATION_TASK_ORDER = [
    "pkg_test",
    "syntax_search",
    "stress",
    "performance",
    "chaos",
    "security",
]

const JULIA_VERIFICATION_TASKS_BY_RESPONSIBILITY = Dict(
    "public_api" => ["pkg_test", "syntax_search", "stress"],
    "external_dependency" => ["pkg_test", "chaos"],
    "persistence" => ["pkg_test", "chaos"],
    "security_boundary" => ["pkg_test", "security"],
    "latency_sensitive" => ["pkg_test", "performance"],
    "availability_critical" => ["pkg_test", "chaos"],
)

const ASP_JULIA_ONLY_DEPENDENCY_ROOTS = Set(["AspJulia"])
const JULIA_NETWORK_ROOTS = Set(["Downloads", "HTTP", "LibCURL", "Sockets", "URIs"])
const JULIA_PERSISTENCE_ROOTS = Set([
    "Arrow",
    "CSV",
    "DelimitedFiles",
    "DuckDB",
    "HDF5",
    "JLD2",
    "JSON",
    "JSON",
    "LibPQ",
    "ODBC",
    "Parquet",
    "Serialization",
    "SQLite",
    "TOML",
])
const JULIA_SECURITY_ROOTS = Set([
    "Argon2",
    "JWT",
    "LibGit2",
    "MbedTLS",
    "OAuth",
    "OpenSSL",
    "SHA",
    "Sodium",
])
const JULIA_PERFORMANCE_ROOTS = Set([
    "AMDGPU",
    "Arrow",
    "CUDA",
    "DataFrames",
    "Distributed",
    "LinearAlgebra",
    "SparseArrays",
    "Statistics",
    "StatsBase",
])
const JULIA_FILE_IO_CALLS = Set([
    "cp",
    "eachline",
    "mkpath",
    "mkdir",
    "mv",
    "open",
    "read",
    "readdir",
    "readlines",
    "rm",
    "touch",
    "walkdir",
    "write",
])
const JULIA_PROCESS_CALLS = Set(["pipeline", "readchomp", "run", "success"])
const JULIA_PERFORMANCE_CALLS = Set([
    "ccall",
    "llvmcall",
    "mapreduce",
    "pmap",
    "reduce",
])
const JULIA_PERFORMANCE_MACROS = Set(["distributed", "simd", "spawn", "threads"])
const JULIA_ALGORITHM_SHAPE_LABEL_ORDER = ["branchy", "nested-loop", "broad-body"]
const MIN_VERIFICATION_BRANCHY_BRANCH_COUNT = 2
const MIN_VERIFICATION_LOOP_NESTING_DEPTH = 2
const MIN_VERIFICATION_BROAD_BODY_STATEMENTS = 8

Base.@kwdef mutable struct JuliaVerificationResponsibilitySignals
    public_names::Set{String} = Set{String}()
    direct_dependency_roots::Set{String} = Set{String}()
    imported_dependency_roots::Set{String} = Set{String}()
    network_roots::Set{String} = Set{String}()
    persistence_roots::Set{String} = Set{String}()
    security_roots::Set{String} = Set{String}()
    performance_roots::Set{String} = Set{String}()
    file_io_calls::Set{String} = Set{String}()
    process_calls::Set{String} = Set{String}()
    performance_calls::Set{String} = Set{String}()
    performance_macros::Set{String} = Set{String}()
    algorithm_shapes::Set{String} = Set{String}()
    hot_functions::Set{String} = Set{String}()
end

function project_responsibility_profile_candidate(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
)
    signals = julia_verification_responsibility_signals(scope, parsed_files)
    responsibilities = inferred_julia_verification_responsibilities(signals)
    isempty(responsibilities) && return nothing
    JuliaVerificationProfileCandidate(
        scope.project_root,
        preferred_source_owner_path(scope),
        "inferred",
        responsibilities,
        task_kinds_for_julia_responsibilities(responsibilities),
        verification_responsibility_evidence(signals),
    )
end

function julia_verification_responsibility_signals(
    scope::JuliaProjectHarnessScope,
    parsed_files::Vector{ParsedJuliaFile},
)
    signals = JuliaVerificationResponsibilitySignals()
    union!(signals.public_names, package_public_names(parsed_files))
    stdlib_roots = julia_stdlib_import_roots()
    direct_roots = runtime_direct_dependency_roots(scope, stdlib_roots)
    for root in direct_roots
        push!(signals.direct_dependency_roots, root)
        add_julia_dependency_root_signal!(signals, root)
    end
    for parsed in parsed_files
        parsed.report.is_valid || continue
        collect_import_responsibility_signals!(signals, parsed, direct_roots)
        collect_call_responsibility_signals!(signals, parsed)
        collect_algorithm_shape_responsibility_signals!(signals, scope, parsed)
    end
    signals
end

function runtime_direct_dependency_roots(
    scope::JuliaProjectHarnessScope,
    stdlib_roots::Set{String},
)
    Set(
        root for root in keys(scope.direct_dependencies) if
        !(root in stdlib_roots) && !(root in ASP_JULIA_ONLY_DEPENDENCY_ROOTS)
    )
end

function collect_import_responsibility_signals!(
    signals::JuliaVerificationResponsibilitySignals,
    parsed::ParsedJuliaFile,
    direct_roots::Set{String},
)
    for imported in parsed.syntax_facts.imports
        is_relative_import(imported) && continue
        root = imported.root
        if root in direct_roots && !(root in ASP_JULIA_ONLY_DEPENDENCY_ROOTS)
            push!(signals.imported_dependency_roots, root)
        end
        add_julia_dependency_root_signal!(signals, root)
    end
end

function collect_call_responsibility_signals!(
    signals::JuliaVerificationResponsibilitySignals,
    parsed::ParsedJuliaFile,
)
    for call in parsed.syntax_facts.calls
        name = call.terminal_name
        name in JULIA_FILE_IO_CALLS && push!(signals.file_io_calls, name)
        name in JULIA_PROCESS_CALLS && push!(signals.process_calls, name)
        name in JULIA_PERFORMANCE_CALLS && push!(signals.performance_calls, name)
    end
    for invocation in parsed.syntax_facts.macro_invocations
        name = lowercase(invocation.terminal_name)
        name in JULIA_PERFORMANCE_MACROS && push!(signals.performance_macros, name)
    end
end

function collect_algorithm_shape_responsibility_signals!(
    signals::JuliaVerificationResponsibilitySignals,
    scope::JuliaProjectHarnessScope,
    parsed::ParsedJuliaFile,
)
    is_test_path(scope, parsed.report.path) && return signals
    for function_fact in parsed.syntax_facts.functions
        labels = algorithm_shape_labels(function_fact)
        isempty(labels) && continue
        union!(signals.algorithm_shapes, labels)
        push!(
            signals.hot_functions,
            algorithm_shape_owner_label(scope, parsed, function_fact, labels),
        )
    end
    signals
end

function algorithm_shape_labels(function_fact::JuliaFunctionSyntax)
    labels = Set{String}()
    function_fact.branch_count >= MIN_VERIFICATION_BRANCHY_BRANCH_COUNT &&
        push!(labels, "branchy")
    function_fact.loop_nesting_depth >= MIN_VERIFICATION_LOOP_NESTING_DEPTH &&
        push!(labels, "nested-loop")
    function_fact.body_statement_count >= MIN_VERIFICATION_BROAD_BODY_STATEMENTS &&
        push!(labels, "broad-body")
    ordered_labels(labels, JULIA_ALGORITHM_SHAPE_LABEL_ORDER)
end

function algorithm_shape_owner_label(
    scope::JuliaProjectHarnessScope,
    parsed::ParsedJuliaFile,
    function_fact::JuliaFunctionSyntax,
    labels::Vector{String},
)
    owner = verification_owner_fingerprint_part(scope, parsed.report.path)
    "$(owner):$(function_fact.terminal_name):$(join(labels, "+"))"
end

function add_julia_dependency_root_signal!(
    signals::JuliaVerificationResponsibilitySignals,
    root::AbstractString,
)
    if root_matches_julia_taxonomy(root, JULIA_NETWORK_ROOTS)
        push!(signals.network_roots, String(root))
    end
    if root_matches_julia_taxonomy(root, JULIA_PERSISTENCE_ROOTS)
        push!(signals.persistence_roots, String(root))
    end
    if root_matches_julia_taxonomy(root, JULIA_SECURITY_ROOTS)
        push!(signals.security_roots, String(root))
    end
    if root_matches_julia_taxonomy(root, JULIA_PERFORMANCE_ROOTS)
        push!(signals.performance_roots, String(root))
    end
end

function root_matches_julia_taxonomy(root::AbstractString, taxonomy::Set{String})
    root in taxonomy && return true
    any(prefix -> startswith(root, prefix * "."), taxonomy)
end

function inferred_julia_verification_responsibilities(
    signals::JuliaVerificationResponsibilitySignals,
)
    responsibilities = Set{String}()
    !isempty(signals.public_names) && push!(responsibilities, "public_api")
    if !isempty(signals.direct_dependency_roots) ||
       !isempty(signals.imported_dependency_roots) ||
       !isempty(signals.network_roots) ||
       !isempty(signals.persistence_roots) ||
       !isempty(signals.security_roots)
        push!(responsibilities, "external_dependency")
    end
    (!isempty(signals.persistence_roots) || !isempty(signals.file_io_calls)) &&
        push!(responsibilities, "persistence")
    (!isempty(signals.security_roots) || !isempty(signals.process_calls)) &&
        push!(responsibilities, "security_boundary")
    if !isempty(signals.performance_roots) ||
       !isempty(signals.performance_calls) ||
       !isempty(signals.performance_macros) ||
       !isempty(signals.algorithm_shapes)
        push!(responsibilities, "latency_sensitive")
    end
    !isempty(signals.network_roots) && push!(responsibilities, "availability_critical")
    ordered_labels(responsibilities, JULIA_VERIFICATION_RESPONSIBILITY_ORDER)
end

function task_kinds_for_julia_responsibilities(responsibilities::Vector{String})
    tasks = Set{String}()
    for responsibility in responsibilities
        union!(tasks, get(JULIA_VERIFICATION_TASKS_BY_RESPONSIBILITY, responsibility, String[]))
    end
    ordered_labels(tasks, JULIA_VERIFICATION_TASK_ORDER)
end

function verification_responsibility_evidence(
    signals::JuliaVerificationResponsibilitySignals,
)
    evidence = Dict{String,String}()
    add_count_evidence!(evidence, "public", length(signals.public_names))
    add_capped_set_evidence!(evidence, "exports", signals.public_names, 8)
    add_set_evidence!(evidence, "direct_deps", signals.direct_dependency_roots)
    add_set_evidence!(evidence, "imported_deps", signals.imported_dependency_roots)
    add_set_evidence!(evidence, "network_roots", signals.network_roots)
    add_set_evidence!(evidence, "persistence_roots", signals.persistence_roots)
    add_set_evidence!(evidence, "security_roots", signals.security_roots)
    add_set_evidence!(evidence, "performance_roots", signals.performance_roots)
    add_set_evidence!(evidence, "file_io_calls", signals.file_io_calls)
    add_set_evidence!(evidence, "process_calls", signals.process_calls)
    add_set_evidence!(evidence, "performance_calls", signals.performance_calls)
    add_set_evidence!(evidence, "performance_macros", signals.performance_macros)
    add_set_evidence!(evidence, "algorithm_shapes", signals.algorithm_shapes)
    add_count_evidence!(evidence, "hot_function_count", length(signals.hot_functions))
    add_capped_set_evidence!(evidence, "hot_functions", signals.hot_functions, 4)
    evidence
end

function add_count_evidence!(evidence::Dict{String,String}, key::String, value::Int)
    value > 0 && (evidence[key] = string(value))
    evidence
end

function add_set_evidence!(evidence::Dict{String,String}, key::String, values::Set{String})
    !isempty(values) && (evidence[key] = join(sort!(collect(values)), ","))
    evidence
end

function add_capped_set_evidence!(
    evidence::Dict{String,String},
    key::String,
    values::Set{String},
    limit::Int,
)
    isempty(values) && return evidence
    evidence[key] = join(first(sort!(collect(values)), min(limit, length(values))), ",")
    evidence
end

function ordered_labels(labels::Set{String}, order::Vector{String})
    [label for label in order if label in labels]
end
