# Julia Syntax Harness Alignment Design

Status: ready for user review
Date: 2026-05-20
Repository: `julia-lang-project-harness`

## Purpose

This design starts a Julia project harness that learns from the
`rust-lang-project-harness` without copying Rust-specific rules into Julia.

The goal is a Julia-native, parser-first, repair-oriented harness for coding
agents. It should help an agent understand a Julia package through stable
project facts, compact findings, and a low-noise reasoning snapshot. The
harness is not a replacement for Julia, `Pkg.test`, formatting tools, or static
analysis packages. It is a structural policy layer that makes the next repair
action visible.

## Design Posture

The Rust harness is an experience source, not a template.

The reusable experience is:

- build one native parser fact layer before policy runs;
- make policy consume facts instead of raw text;
- render compact repair contracts for agents by default;
- keep structured JSON available for tools;
- keep default severity split clear: blocking policy vs advisory agent repair;
- self-apply the harness so rule drift is found in the package itself;
- permit local exceptions only when the project records a reason;
- expose a project reasoning snapshot so agents do not start from a file list.

The Julia adaptation must be based on Julia's own project and language model:

- `Project.toml` defines the package boundary;
- `src/<PackageName>.jl` is the package entry module and facade candidate;
- `include(...)` builds the practical file graph;
- `module` and `baremodule` define namespaces but do not automatically map to
  files;
- `using` and `import` define package and module dependency facts;
- `export` and Julia 1.11+ `public` define public API intent;
- method families matter more than isolated function declarations;
- macros and generated behavior are syntax facts at first, not expanded
  semantic facts;
- `test/runtests.jl`, `Pkg.test`, and `Test.@testset` define the first test
  gate surface.

The source-grounded Julia quality model for this harness lives in
`docs/superpowers/research/2026-05-20-julia-project-quality-for-agents.md`.
It translates the Julia manual, Pkg/Documenter guidance, and mature package
practices from SciML, JuMP, DataFrames, and BlueStyle into Agent-facing project
quality signals. Later policy slices should use that note as calibration input
instead of copying Rust-specific design rules.

## Non-Goals

The first implementation will not:

- evaluate or include project files;
- expand macros;
- infer runtime dispatch behavior;
- require all Julia packages to use one physical source layout;
- port Rust rules such as `mod.rs`, `build.rs`, `crate::...`, or
  `#[cfg(test)]`;
- implement the full verification report subsystem from the Rust harness;
- claim dynamic `include` calls are resolved when they are not parser-stable.

## Package Shape

The package should be a normal Julia package:

- `Project.toml`
- `src/JuliaLangProjectHarness.jl`
- `src/parser/...`
- `src/rules/...`
- `src/render/...`
- `src/runner/...`
- `test/runtests.jl`
- `test/unit/...`
- `bin/julia-project-harness.jl`

The root module should remain a facade. It should include owned modules and
re-export stable public API, but implementation should live in leaf files. This
is a Julia-native version of the "thin package boundary" lesson, not a Rust
`lib.rs` clone.

The public module name should be `JuliaLangProjectHarness` unless package
registration constraints require a different name. The repository name can stay
`julia-lang-project-harness`.

## Parser Boundary

`JuliaSyntax.jl` is the only Julia syntax parser used by the harness.

The parser layer owns all direct calls to JuliaSyntax. Rule packs, runners, and
renderers must consume parser-owned facts. They must not call JuliaSyntax or
scan source text directly except through parser helper functions.

The strict parse path should parse each `.jl` file with filename-aware
JuliaSyntax APIs. The design should prefer a path that preserves diagnostics
and source locations. `parseall(JuliaSyntax.SyntaxNode, source; filename=path)`
is the simple strict interface. `parse!(JuliaSyntax.SyntaxNode, io; rule=:all)`
is available when diagnostics need to be retained without losing the tree.

The parser layer should expose these internal facts:

- `ParsedJuliaFile`
- `JuliaFileReport`
- `JuliaNativeSyntaxFacts`
- `JuliaSourceMetrics`
- `JuliaTopLevelItemSyntax`
- `JuliaModuleSyntax`
- `JuliaIncludeSyntax`
- `JuliaImportSyntax`
- `JuliaExportSyntax`
- `JuliaFunctionSyntax`
- `JuliaMethodSignatureSyntax`
- `JuliaStructSyntax`
- `JuliaMacroInvocationSyntax`
- `JuliaCallSyntax`
- `JuliaDocstringSyntax`
- `JuliaIdentifierSyntax`
- `JuliaTestSyntax`

Each fact that can trigger a finding must carry a stable source location:

- path
- one-based line
- zero-based column
- source line when useful

The parser layer should classify these constructs in the first slice:

- `module Name ... end`
- `baremodule Name ... end`
- `include("file.jl")`
- `include(joinpath("dir", "file.jl"))` when every segment is literal
- dynamic `include(...)`
- `using Package`
- `using Package: name, name2`
- `import Package`
- `import Package: name`
- `export name`
- `public name` when supported by the configured Julia syntax version
- `const NAME = value` and typed `const NAME::T = value` public bindings
- `global NAME = value` bindings when they are part of the declared public
  surface
- package-level `NAME = value` bindings with initializer kind/head facts so
  policy can identify mutable global state without scanning raw text
- long-form function definitions
- short-form function definitions
- Julia dispatch signature facts for typed positional arguments, return
  annotations, and `where` parameters
- function argument facts for positional and keyword arguments, including type
  annotations, defaults, boolean flags, and stringly domain arguments
- function algorithm-shape facts for control-flow depth, branch count, loop
  count, loop nesting depth, and encountered control-flow kinds
- argument-level search entries for Julia method signatures
- function and constructor call references, excluding definition signatures
- docstring bindings through JuliaSyntax `doc` nodes for named modules,
  functions, macros, types, and constants
- identifier occurrences with the immediate JuliaSyntax parent context, as the
  conservative substrate for reference search
- macro definitions
- macro invocations
- mutable and immutable struct definitions
- struct field names, type annotations, and defaulted fields from native syntax
- field-level search entries for Julia type shapes
- primitive type aliases visible through syntax
- `Test.@testset` and direct `@test` usage

The parser layer must preserve "unknown but real" syntax nodes. If a syntax
form is parseable but not yet classified, the harness should keep the file
valid and avoid inventing policy from partial knowledge.

## Project Discovery

Project runner mode starts from a project root.

Discovery should treat `Project.toml` as the package authority. It should read
project facts through `Pkg.Types.read_project`, not by ad hoc string search.
The first facts needed are:

- package name;
- uuid when present;
- direct dependencies;
- weak dependencies when present;
- extras and targets used by tests;
- configured test target shape when present;
- local source dependencies from `[sources].path`;
- workspace member projects.

Default project scope should be Pkg-derived:

- the package entry root from `entryfile` or `src/<PackageName>.jl`;
- declared package extension roots when `[extensions]` is present;
- `test/runtests.jl` and additional `.jl` files under `test/` when tests are
  included;
- workspace members from `[workspace]`;
- local package dependencies from `[sources].path`;
- optional `examples/` only as package examples, not public source API
- optional `benchmark/` and `perf/` later through verification policy, not in
  the first blocking rule set

Ignored directories should include:

- `.git`
- `.jj`
- `.direnv`
- `.cache`
- `.vscode`
- `.idea`
- `node_modules`
- `deps/usr`
- `artifacts`
- `scratchspaces`

Explicit-path runner mode accepts files or directories and runs syntax parsing
only. It has no project graph, no include reachability, and no package policy.
This mirrors the useful runner split from the Rust harness while keeping the
Julia policy semantics separate.

## Reasoning Tree

The Julia reasoning tree should summarize package structure for agents.

It should derive from parser facts and discovery facts:

- package root;
- package module name;
- package entry file;
- source files;
- test files;
- literal include edges;
- dynamic include sites;
- module declarations;
- exports and public names;
- package imports;
- local module imports;
- method families;
- public API candidates;
- orphan source files;
- include cycles;
- owner branches.

An owner branch is not a Rust module branch. In Julia it is a repair ownership
unit inferred from one or more of:

- package entry module;
- file included by the entry module;
- file that includes child files;
- top-level module declaration;
- path namespace under `src/`;
- exported or public API family.

The snapshot renderer should stay compact. A clean small package might render:

```text
Package: Example
Files: source=5 test=2
ReasoningTree:
- root package=Example entry=src/Example.jl
- owner src/Example.jl role=entry modules=Example public=run includes=src/api.jl,src/parser.jl
- owner src/parser.jl role=source includes=src/syntax.jl methods=parse_file,parse_project
Imports:
- Test only in test/runtests.jl
```

The exact text can change during implementation, but the contract is stable:
agents get owner, dependency, and verification shape without reading a full JSON
report. The snapshot should include a compact `Verification:` section with task
kind, phase, owner, command when runnable, selected evidence, and required
receipt keys when external evidence is needed.

## Search Index

Search is a first-class consumer of parser facts, not a separate text scanner.

The harness should expose a compact syntax search index that can power both
LLM context selection and ordinary project lookup. The index must be derived
from `JuliaSyntax` facts owned by the parser layer, so search behavior and
policy behavior agree on source locations and syntax classification.

Initial entries should cover project owners, verification tasks, definitions,
public API declarations, imports, tests, includes, call references, bindings,
docstrings, and identifier occurrences. Owner and verification entries are only emitted in
Project.toml-rooted mode, where the runner has enough scope facts to identify
entry, source, extension, test owners, and project-owned verification gates. A
verification entry should reuse the task index rather than reconstructing
project policy from strings. A call reference is a real invocation in code,
macro arguments, or test expressions. Function and macro definition signatures
are not call references. A docstring entry is only emitted from a JuliaSyntax
`doc` node with a named target; ordinary string literals are not treated as
documentation. An identifier entry is a syntax occurrence with its immediate
parent kind; it is intentionally low-level so later reference classifiers can
build on real syntax facts instead of rescanning text.

Each search entry should carry:

- stable source location;
- kind, such as `owner`, `verification`, `module`, `function`, `struct`,
  `call`, `doc`, `identifier`, `include`, or `test`;
- name;
- detail text for disambiguation;
- combined search fzf;
- tags for filtering, such as `owner`, `reasoning-tree`, `public`, `method`,
  `control-flow`, `nested-loop`, `call`, `dependency`, and `test`.

The public search API should also provide deterministic local query helpers over
this index. Query helpers should return scored results, apply tag filters as hard
filters, and avoid hidden external services or fuzzy state. Ranking should favor
exact symbol-name matches, then name containment, tag matches, detail matches,
and broader search fzf matches.

## CLI Surface

The package should expose a small command-line entrypoint comparable to the Rust
harness CLI while staying Julia-native:

- default output renders the compact repair report;
- `--json` renders the structured report;
- `--agent-snapshot` renders the low-noise project summary;
- `--advice` renders only advisory findings;
- `--search QUERY` renders scored search results from JuliaSyntax-derived
  index entries;
- `--tag TAG` and `--limit N` constrain search output.
- `--verification-tasks` renders agent-runnable verification duties;
- `--verification-tasks-json` renders the same duties as structured JSON.

The CLI is a thin wrapper over public library functions. It should not own
policy, parsing, or search behavior.

## Verification Task Index

The Julia harness should expose a compact verification task index so agents can
plan the next validation step without inferring it from policy text.

The first Julia-native task families are:

- `pkg_test`: run `Pkg.test()` from the discovered `Project.toml` root;
- `harness_policy`: run the package harness self-policy gate when the package
  depends on this harness;
- `syntax_search`: smoke the JuliaSyntax-derived search index when this harness
  is available in the project;
- `extension_boundary`: run package tests with package extension weakdeps in
  scope; if the extension weakdeps are not mounted in the test target, emit
  Agent advice to add or run an extension activation path before treating the
  package test gate as complete.
- `docs_build`: run a Documenter docs build, including doctests, when
  `docs/Project.toml` depends on Documenter and `docs/make.jl` exists.
- `example_run`: run a package-owned examples project when
  `examples/Project.toml` exists with `runexamples.jl`, `runtests.jl`, or
  `examples.jl`; this uses the examples environment rather than assuming loose
  scripts belong to the root package gate.
- `performance`: run a project-owned benchmark or strict perf entry discovered
  from `benchmark/`, `benchmarks/`, `perf/`, or `test/perf/`. A local benchmark
  `Project.toml` owns activation when present; otherwise the root package
  project owns the command.

Each task should carry a stable fingerprint, kind, state, phase, project root,
owner path, command, compact evidence, and short reason. This is intentionally
lighter than the Rust verification subsystem until Julia projects have their
own configured-skill contracts.

## Rule Packs

Default project execution order:

1. `julia.syntax`
2. `julia.project_policy`
3. `julia.modularity`
4. `julia.agent_policy`

The first three packs are blocking by default. `julia.agent_policy` is advisory
in the library runner. The package test gate can promote advisory findings to
visible test feedback, with an explicit config escape hatch and explanation.

### `julia.syntax`

Initial rule:

- `JULIA-SYN-R001`: Julia source must parse through `JuliaSyntax.jl`.

This rule is syntax-only and applies in both project and explicit-path runner
modes.

### `julia.project_policy`

Initial rules:

- `JULIA-PROJ-R001`: package projects should have a `Project.toml` with a
  package name.
- `JULIA-PROJ-R002`: package projects should expose the package entry module
  through `src/<PackageName>.jl`, unless config records a reason.
- `JULIA-PROJ-R003`: harness-enabled packages should mount a configured
  `Pkg.test` gate from `test/runtests.jl`.
- `JULIA-PROJ-R004`: `test/runtests.jl` should stay a thin test aggregate when
  it grows beyond small package scale.
- `JULIA-PROJ-R005`: custom source or test scope paths need concrete
  explanations.
- `JULIA-PROJ-R006`: removing conventional source or test scope needs a
  concrete explanation.
- `JULIA-PROJ-R014`: harness config escape surfaces need concrete
  explanations.

The first implementation can keep `JULIA-PROJ-R003` narrow: if the package
depends on this harness or calls its assertion API, the test gate must be
configured. Comments and strings do not count.

### `julia.modularity`

Initial rules:

- `JULIA-MOD-R001`: `src/<PackageName>.jl` should act as a package facade,
  not a large implementation file.
- `JULIA-MOD-R002`: every project-owned Julia file discovered from
  `Project.toml` scope should stay within a configured size and responsibility
  budget, including source, extension, and test owners.
- `JULIA-MOD-R003`: dynamic `include(...)` hides the repair graph and should
  be replaced with parser-stable literal includes or a documented exception.
- `JULIA-MOD-R004`: literal include targets must exist.
- `JULIA-MOD-R005`: literal include graph must not contain cycles.
- `JULIA-MOD-R006`: scanned source files under `src/` should be reachable from
  the package entry include graph, unless config records a reason.
- `JULIA-MOD-R007`: source path segments should avoid generic owner buckets
  such as `utils`, `common`, `helpers`, and `misc`.
- `JULIA-MOD-R008`: nested module ownership should be explicit; large nested
  modules inside files should move to named files or carry a documented reason.

These rules are Julia-specific. They protect the include graph and namespace
surface instead of Rust's module tree.

### `julia.agent_policy`

Initial advisory rules:

- `AGENT-JL-R001`: exported or `public` API lacks an intent doc.
- `AGENT-JL-R002`: public method family has too many positional parameters.
- `AGENT-JL-R003`: public method family exposes multiple `Bool` flags instead
  of a named option or keyword config shape.
- `AGENT-JL-R004`: public method uses stringly state, mode, kind, type, tag,
  phase, or status arguments without a named domain carrier.
- `AGENT-JL-R005`: exported names conflict across owner files or method
  families.
- `AGENT-JL-R006`: owner file fans out to many local owners without an intent
  doc.
- `AGENT-JL-R007`: public function body hides algorithm shape behind deeply
  nested control flow.
- `AGENT-JL-R008`: broad public function should split into named pipeline
  steps.
- `AGENT-JL-R009`: method family is scattered across unrelated owner files
  without a clear extension pattern.
- `AGENT-JL-R010`: macro-heavy public API lacks a syntax-level contract note.
- `AGENT-JL-R011`: public struct fields omit explicit type annotations.
- `AGENT-JL-R012`: public struct exposes stringly domain fields such as mode,
  status, category, or type.
- `AGENT-JL-R013`: public mutable struct lacks a mutation contract note.
- `AGENT-JL-R014`: package tests omit the in-test harness verification profile
  hook.
- `AGENT-JL-R015`: internal implementation function nests traversal loops and
  guard branches instead of exposing named iterator, predicate, or data
  processing helpers for agent repair.
- `AGENT-JL-R016`: exported mutating method lacks a mutation contract note
  explaining which arguments or state are changed.
- `AGENT-JL-R017`: non-test code uses `eval`, `ccall`, external process
  execution, `@eval`, or `@inbounds` without a concrete safety/performance
  reason and focused verification evidence.
- `AGENT-JL-R018`: exported generic methods with explicit `where` type
  parameters lack parser-visible tests across more than one relevant input
  type.
- `AGENT-JL-R019`: Documenter docs lack executable `jldoctest`, `@example`,
  or `@repl` examples for exported/public API names.
- `AGENT-JL-R020`: exported stringly domain methods with branch dispatch lack a
  typed domain model; if Moshi is chosen, it should stay optional through
  `[weakdeps]` and `[extensions]` unless it is core API. The harness self-applies
  this by exposing `JuliaLangProjectHarnessMoshiExt`, which uses Moshi only when
  the weak dependency is loaded. Snapshot and search surfaces should still show
  the Moshi extension activation state and capability labels from project facts
  so agents can plan the typed-domain repair before loading the weak dependency.
  Verification task/profile evidence should include those capability labels so
  the package-test loop can guide the agent toward the same repair path. R020
  findings should include project-local labels for whether Moshi is missing,
  only a weak dependency, or already extension-backed, plus the likely extension
  repair target. Configuration alone must not silence the rule; R020 is
  satisfied only when JuliaSyntax facts show a Moshi modeling surface that
  covers the parser-visible stringly branch literals when those literals can be
  extracted from branch conditions.
- `AGENT-JL-R021`: external method definitions lack a parser-visible
  package-owned dispatch type or a concrete interop/type-piracy contract.
- `AGENT-JL-R022`: Moshi `@data` domain models that cover stringly branch
  literals lack parser-visible `@match` cases or typed methods that show how
  the real project logic uses the model. This prevents agents from stopping at
  an unused ADT and guides them toward a Moshi-backed branch bridge.
- `AGENT-JL-R023`: exported methods with concrete return annotations lack a
  return/type-stability contract. This keeps agents from adding narrow runtime
  return assertions as cosmetic precision when the public API does not state
  that contract.
- `AGENT-JL-R024`: package source defines non-const mutable global state
  through parser-visible binding initializer shape. This pushes agents toward
  explicit state owners, dependency-injected caches, or documented `const`
  lifecycle/reset handles instead of hidden package globals.
- `AGENT-JL-R025`: public structs expose `Any`, `Function`, or broad abstract
  field annotations. This pushes agents toward concrete fields or type
  parameters that keep the public data contract inferable.
- `AGENT-JL-R026`: exported methods call `error`, `throw`, or `@assert`
  without documenting the failure, exception, assertion, or precondition
  contract. This keeps invalid-input behavior visible to agents before they
  change the public API.
- `AGENT-JL-R027`: documented public failure contracts lack parser-visible
  `@test_throws` coverage in package tests. This keeps invalid-input behavior
  executable in `Pkg.test` instead of stopping at doc text.
- `AGENT-JL-R028`: documented public `!` mutation contracts lack
  parser-visible package tests that call the mutating API. This keeps in-place
  behavior executable in `Pkg.test` instead of stopping at doc text.
- `AGENT-JL-R029`: parser-visible package testsets nest loops plus guard
  branches. This pushes agents to split broad scenario scaffolding into named
  testsets or helper assertions that can be repaired one behavior at a time.
- `AGENT-JL-R030`: documented public safety or performance evidence contracts
  for unsafe constructs lack parser-visible package tests that call the public
  API. This prevents agents from satisfying risky code paths with prose-only
  verification claims.
- `AGENT-JL-R031`: documented concrete return/type-stability contracts lack
  parser-visible `@inferred` package tests. This keeps public return precision
  executable in `Pkg.test` instead of stopping at doc text.

The implemented subset currently locked by tests is `AGENT-JL-R001` through
`AGENT-JL-R031`. Later advisory rules can land only after the needed
JuliaSyntax facts are present and the tests lock the emitted advice.

## Public API

The package should expose a library-first API:

```julia
default_julia_harness_config()
run_julia_project_harness(project_root::AbstractString; config=default_julia_harness_config())
run_julia_lang_harness(paths::Vector{<:AbstractString}; config=default_julia_harness_config())
assert_julia_project_harness_clean(project_root::AbstractString; config=default_julia_harness_config())
assert_julia_project_harness_pkg_test_clean(project_root::AbstractString; config=default_julia_harness_config())
build_julia_project_verification_profile(project_root::AbstractString=pwd(); config=default_julia_harness_config())
build_julia_verification_profile_index(project_root::AbstractString; config=default_julia_harness_config())
assert_julia_project_harness_test_profile_clean(project_root::AbstractString=pwd(); config=default_julia_harness_config(), advice_io=stdout)
render_julia_project_harness(report)
render_julia_project_harness_json(report)
render_julia_project_harness_advice(report)
render_julia_project_harness_agent_snapshot(project_root::AbstractString; config=default_julia_harness_config())
render_julia_search_results(results::Vector{JuliaSearchResult}; project_root=nothing)
build_julia_verification_task_index(project_root::AbstractString; config=default_julia_harness_config())
render_julia_verification_profile(profile::JuliaVerificationProfile)
render_julia_verification_profile_json(profile::JuliaVerificationProfile)
render_julia_verification_profile_index(index::JuliaVerificationProfileIndex)
render_julia_verification_profile_index_json(index::JuliaVerificationProfileIndex)
render_julia_verification_pending_advice(profile::JuliaVerificationProfile)
render_julia_verification_task_index(index::JuliaVerificationTaskIndex)
render_julia_verification_task_index_json(index::JuliaVerificationTaskIndex)
render_julia_verification_receipt_template(index::JuliaVerificationTaskIndex)
read_julia_verification_receipts_json(path::AbstractString)
review_julia_verification_receipts(index::JuliaVerificationTaskIndex, receipts)
assert_julia_verification_receipts_accepted(index::JuliaVerificationTaskIndex, receipts)
render_julia_verification_receipt_reviews(reviews::Vector{JuliaVerificationReceiptReview})
render_julia_verification_receipt_reviews_json(reviews::Vector{JuliaVerificationReceiptReview})
julia_project_search_index(project_root::AbstractString; config=default_julia_harness_config())
julia_lang_search_index(paths::Vector{<:AbstractString}; config=default_julia_harness_config())
search_julia_index(entries::Vector{JuliaSearchIndexEntry}, query::AbstractString; tags=String[], limit=25)
search_julia_project(project_root::AbstractString, query::AbstractString; config=default_julia_harness_config(), tags=String[], limit=25)
search_julia_lang(paths::Vector{<:AbstractString}, query::AbstractString; config=default_julia_harness_config(), tags=String[], limit=25)
run_julia_project_harness_cli(args=ARGS; out=stdout, err=stderr)
julia_rule_pack_descriptors()
julia_syntax_rules()
julia_project_policy_rules()
julia_modularity_rules()
julia_agent_policy_rules()
```

The package test gate should be an ordinary Julia test assertion, for example:

```julia
using Test
using JuliaLangProjectHarness

@testset "julia project harness" begin
    config = default_julia_harness_config()
    assert_julia_project_harness_test_profile_clean(pkgdir(JuliaLangProjectHarness); config)
end
```

The exact function signatures can be adjusted during implementation, but the
API shape should remain library-first and runnable from `Pkg.test`.

## Report Model

The report model should be serializable and compact:

- `JuliaDiagnosticSeverity`: `info`, `warning`, `error`
- `JuliaRulePack`
- `JuliaHarnessRule`
- `JuliaHarnessFinding`
- `JuliaFileReport`
- `JuliaSearchIndexEntry`
- `JuliaSearchResult`
- `JuliaVerificationProfileCandidate`
- `JuliaVerificationProfileIndex`
- `JuliaVerificationTaskRecord`
- `JuliaVerificationTaskIndex`
- `JuliaVerificationReceiptReview`
- `JuliaVerificationProfile`
- `JuliaProjectHarnessScope`
- `JuliaHarnessConfig`
- `JuliaHarnessReport`

Each finding should contain:

- stable rule id;
- stable pack id;
- severity;
- short title;
- concrete summary;
- source location;
- stable requirement;
- optional source line;
- short fix label;
- labels for tooling.

`Warning` and `Error` block by default. `Info` remains advisory in the library
runner. The package test assertion may fail on advisory findings so `Pkg.test`
does not hide repair feedback.

## Rendering Contract

Compact text is the default agent surface.

Finding format:

```text
[JULIA-MOD-R003] Warning: Dynamic include hides source graph
@ src/Example.jl:12:5
fix: replace dynamic include with literal include or document the exception
line: 12 | include(path)
Help: parser facts found an include call whose target is not statically known.
Contract: Keep Julia package source graphs parser-stable for repair agents.
```

Clean output:

```text
[ok] julia
```

The renderer should avoid:

- human audit headers;
- file counters before the repair action;
- large JSON by default;
- decorative code frames;
- empty sections.

JSON is available through the structured renderer. Agents should not need JSON
for the common repair loop.

## Agent-First Verification Inference

The harness is primarily run by agents, so verification configuration should be
derived before it is hand-authored. Project facts from `Project.toml` and native
JuliaSyntax facts from imports, calls, macros, Moshi modeling forms, exports,
extensions, and test entrypoints should produce compact `VerificationProfiles`
that tell an agent which responsibility family is present:

- `public_api` asks for ordinary package tests, syntax-search smoke coverage,
  and stress-style API validation;
- `external_dependency`, `persistence`, and `availability_critical` ask for
  dependency/chaos-style checks;
- `security_boundary` asks for security-oriented evidence;
- `latency_sensitive` asks for performance evidence.

This is an adaptation of the Rust harness verification profile design, but the
signals are Julia-native: package dependencies, stdlibs such as `SHA` or
`LinearAlgebra`, data/persistence packages such as `JSON3`, network packages
such as `HTTP`, file/process calls, performance-related calls/macros, and
parser-visible algorithm shapes such as `branchy`, `nested-loop`, and
`broad-body`. The agent should use this inferred profile as the default
verification plan and only write explicit config when it needs to explain a true
exception.

The task index should project these inferred responsibilities into pending
agent obligations. Ordinary `pkg_test`, self-policy, extension, and syntax-search
records can carry runnable commands. Explicit benchmark/perf records should also
carry runnable commands and should replace duplicate inferred performance
records for the same scope. External evidence families such as
`stress`, `performance`, `chaos`, and `security` should carry owner path,
fingerprint, lifecycle phase, compact parser/project evidence, and a reason for
what the agent should add or run next. They should also expose required evidence
keys. For example, performance requires benchmark command, baseline, regression
threshold, runtime or allocation metric, and artifact; security requires scanned
attack classes and an authorization-boundary result; chaos requires injected
failure, degraded behavior, and recovery result; stress requires load steps,
latency percentiles, threshold, and result. Compact text renders should include
the fingerprint so future receipts or waivers can bind evidence to the exact
inferred obligation. The harness must not pretend those tasks are satisfied
merely because package tests pass.

The package-test assertion should stay non-blocking for pending external
evidence, but it should emit a compact `[verify-advice]` section by default
when such tasks exist. That keeps ordinary `Pkg.test` green while still putting
the next agent actions in the test log. Programmatic callers may pass
`advice_io=nothing` when they need a quiet assertion.

Receipts are a separate Agent-facing contract. A receipt should bind to the
task fingerprint and provide the required evidence keys for its family. The
reviewer should classify receipts as accepted, incomplete, missing, orphan, or
waived. Missing keys, blank values, and placeholder values such as `todo`
remain incomplete. Waivers are allowed only when the receipt records a concrete
explanation, so an Agent cannot silently skip expensive verification by adding a
lightweight config escape. The CLI review mode should return success only when
every required external receipt is accepted or concretely waived.
If a receipt includes task metadata such as `kind` or `owner_path`, those fields
must match the fingerprint-bound task. This keeps copied or stale receipt
templates from silently certifying the wrong owner.

The harness should also emit a JSON receipt template from the same task index.
Template values are intentionally blank: they help the Agent fill the required
keys, but they must not pass review until replaced with concrete evidence. This
keeps the loop tight without turning the template itself into an escape path.
The CLI exposes this as `--verification-receipt-template`.

The in-test verification profile should review the default project receipt file
at `.julia-harness/verification-receipts.json` when it exists. A missing receipt
file leaves external evidence tasks advisory, but an existing incomplete or
mismatched receipt should fail `assert_julia_project_harness_test_profile_clean`
and render the receipt review in the test failure. Accepted or concretely waived
receipts should suppress the corresponding pending advice entry.

## Configuration

Config is an escape and tuning surface, not the primary source of truth. It
should support:

- ignored directory names;
- blocking severities;
- disabled rule ids;
- disabled rule explanations;
- rule severity overrides;
- rule severity override explanations;
- blocking severity explanations;
- source scope paths;
- test scope paths;
- source path explanations;
- test path explanations;
- source path exclusion explanations;
- test path exclusion explanations;
- agent advice allow explanation;
- syntax version when JuliaSyntax supports version-sensitive parsing;
- reserved verification policy field for a later design slice.

Custom scope additions and removals should require concrete explanations.
This is a direct adaptation of the Rust harness lesson: exceptions are allowed,
but silent scope shrinkage is not.

Config surfaces that let an agent escape policy must also require concrete
explanations, not placeholders such as `todo` or `n/a`. Disabling a rule,
lowering a rule severity, removing a default blocking severity, or allowing
advisory findings is valid only when the config records why. The escape guard
must be appended after config filtering so the same config cannot silently
suppress the finding that reports the escape.

## Self-Apply Contract

The harness must apply itself before it is treated as ready for downstream use.

The first self-apply target is `Pkg.test`:

- `test/runtests.jl` mounts the package's own harness assertion;
- the assertion uses explicit config;
- config explains intentional early exceptions;
- the compact render for self policy is covered by snapshot tests;
- advisory policy is either fixed or explicitly allowed with an explanation.

This is the Julia-native equivalent of the Rust source-backed cargo test gate.
There is no first-slice `build.rs` equivalent.

## Testing Strategy

The first implementation should add tests in this order:

1. parser fixtures for JuliaSyntax facts;
2. explicit-path runner syntax-only behavior;
3. package-root discovery from `Project.toml`;
4. literal include graph facts;
5. dynamic include finding;
6. compact render snapshots;
7. JSON shape smoke test;
8. package self-apply gate.

Expected local validation commands after implementation:

```shell
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. -e 'using Pkg; Pkg.test()'
git diff --check
```

If formatting or lint tools are added later, they should be explicit package
dependencies or documented developer tools. They should not be assumed in the
bootstrap design.

## Implementation Stages

Stage 1: Bootstrap package and parser substrate.

- Create `Project.toml`.
- Add `JuliaSyntax` and `Test` dependencies.
- Add parser fact types and strict file parsing.
- Add explicit-path runner with syntax-only reporting.
- Add compact renderer and JSON renderer.

Stage 2: Project discovery and include graph.

- Parse `Project.toml`.
- Discover package entry file and source/test scope.
- Extract literal include graph.
- Detect dynamic includes, missing targets, cycles, and orphan source files.
- Add agent snapshot renderer.

Stage 3: First policy packs and self-apply.

- Add rule catalog descriptors.
- Add `julia.syntax`, `julia.project_policy`, and first `julia.modularity`
  rules.
- Add a small first subset of `julia.agent_policy`.
- Mount the package's own `Pkg.test` harness gate.
- Record intentional exceptions in config only when needed.

Stage 4: Julia API shape advice.

- Build method-family facts.
- Add exported/public documentation advice.
- Add parameter-shape, flag-shape, and broad-function advice.
- Keep all advice non-blocking in the library runner.

Stage 5: Reserved verification planning slice.

- Do not port the Rust verification subsystem wholesale.
- Design Julia verification around `Pkg.test`, benchmarks, examples, and
  package-specific evidence.
- Keep task contracts, required evidence, and receipt review as compact
  Agent-facing surfaces.

## Approval Criteria

This design is approved when the reviewer agrees that:

- Rust harness lessons are used as principles, not copied rules;
- JuliaSyntax owns all Julia syntax parsing;
- the first project graph is based on `Project.toml`, package entry modules,
  literal includes, modules, imports, exports, and tests;
- dynamic language features are represented honestly as bounded syntax facts;
- compact repair output remains the primary agent interface;
- self-apply is required before downstream use;
- implementation can proceed in staged slices without building the full
  verification subsystem first.

## References

- Local Rust harness boundary:
  `/Users/guangtao/ghq/github.com/tao3k/rust-lang-project-harness/docs/01_core/101_harness_boundary.md`
- Local Rust runner modes:
  `/Users/guangtao/ghq/github.com/tao3k/rust-lang-project-harness/docs/03_features/202_runner_modes.md`
- Local Rust rule catalog:
  `/Users/guangtao/ghq/github.com/tao3k/rust-lang-project-harness/docs/03_features/201_rule_catalog.md`
- JuliaSyntax API:
  `https://julialang.github.io/JuliaSyntax.jl/dev/api/`
- JuliaSyntax syntax trees:
  `https://julialang.github.io/JuliaSyntax.jl/dev/reference/`
