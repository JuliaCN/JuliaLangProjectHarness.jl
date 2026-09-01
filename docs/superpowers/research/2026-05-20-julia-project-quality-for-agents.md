# Julia Project Quality Notes for Agents

Status: research note
Date: 2026-05-20
Repository: `asp-julia`

## Purpose

This note turns Julia project quality guidance into harness design input for
coding agents. The goal is not to make agents memorize a generic style guide.
The goal is to make Julia project structure, API intent, algorithm shape,
performance risk, tests, documentation, and escape-policy surfaces visible
enough that an agent can repair a package without writing brittle "AI-shaped"
Julia.

The Rust harness remains an experience source, but the Julia harness must use
Julia-native authority:

- `Project.toml`, `Pkg`, and workspace environments define project boundaries.
- `JuliaSyntax.jl` facts define syntax, search, and advisory policy inputs.
- `Pkg.test`, package docs, doctests, and focused verification receipts define
  the first evidence surface.

## Sources Reviewed

Official references:

- [Julia Style Guide](https://docs.julialang.org/en/v1/manual/style-guide/)
- [Julia Performance Tips](https://docs.julialang.org/en/v1/manual/performance-tips/)
- [Julia Modules](https://docs.julialang.org/en/v1/manual/modules/)
- [Julia Code Loading](https://docs.julialang.org/en/v1/manual/code-loading/)
- [Julia Documentation](https://docs.julialang.org/en/v1/manual/documentation/)
- [Pkg Creating Packages](https://pkgdocs.julialang.org/v1/creating-packages/)
- [Pkg Project.toml and Manifest.toml](https://pkgdocs.julialang.org/dev/toml-files/)
- [Pkg Compatibility](https://pkgdocs.julialang.org/v1/compatibility/)
- [Documenter Package Guide](https://documenter.juliadocs.org/stable/man/guide/index.html)
- [Documenter Doctests](https://documenter.juliadocs.org/stable/man/doctests/)

Mature project and ecosystem references:

- [SciML Style Guide](https://docs.sciml.ai/SciMLStyle/dev/)
- [BlueStyle](https://github.com/JuliaDiff/BlueStyle)
- [JuMP Style Guide](https://jump.dev/JuMP.jl/stable/developers/style/)
- [JuMP Contributing Guide](https://jump.dev/JuMP.jl/stable/developers/contributing/)
- [JuMP AI Policy](https://jump.dev/JuMP.jl/stable/developers/ai_policy/)
- [DataFrames.jl contributing guide](https://raw.githubusercontent.com/JuliaData/DataFrames.jl/main/CONTRIBUTING.md)
- [Moshi.jl](https://rogerluo.dev/Moshi.jl/)

These sources do not fully agree on every style detail. That is useful signal:
the harness should prefer project-local consistency, parser-visible intent, and
verification receipts over universal formatting taste.

## Quality Model

### 1. Project Boundary Is A Pkg Boundary

High-quality Julia project work starts from the active package environment, not
from a loose directory scan. `Project.toml` owns package identity, direct
dependencies, weak dependencies, extensions, compatibility, extras, targets,
local source dependencies, and workspace membership. `Manifest.toml` can be
important evidence for applications or shared workspaces, but harness policy
should not invent a version lock where the package intends resolver-compatible
library behavior.

Agent implication:

- Discover the project root from `Project.toml`.
- Read `[deps]`, `[weakdeps]`, `[extensions]`, `[compat]`, `[extras]`,
  `[targets]`, `[sources]`, and `[workspace]` as structured package facts.
- Use `entryfile`, declared extensions, `[sources].path`, and workspace
  members to decide the harness scope before falling back to configured
  directories.
- Treat `test/`, `docs/`, and `benchmarks/` projects as first-class package
  environments when they have their own `Project.toml`.
- Prefer compat and resolver facts over arbitrary branch or version pinning.
- Use `[weakdeps]` plus `[extensions]` for feature-like optional runtime
  capabilities, and keep docs/test-only dependencies in their own
  environments.

Harness implication:

- Root discovery must stay `Project.toml`/Pkg-driven.
- Policy should flag missing compat or unexplained dependency source overrides,
  but it should not force an arbitrary `#main` rev or a generated lockfile.
- Verification tasks should know whether they are running package tests, docs,
  extension tests, or benchmark/performance checks.
- Policy should distinguish required runtime dependencies from optional
  extension, docs, and test dependencies instead of pushing every helper into
  root `[deps]`.

### 2. The Entry Module Is A Facade, Not A Dumping Ground

Julia modules do not map to files the way Rust modules do. A package commonly
has `src/<PackageName>.jl` as the entry module, then uses literal `include`
calls to evaluate owned files in that module. File names and module expressions
are related by convention and ownership, not by a compiler-enforced file tree.

Agent implication:

- Start from the entry module and literal include graph.
- Keep the entry file small: imports, exports/public API, includes, and facade
  definitions belong there; large algorithms usually belong in owner files.
- Avoid dynamic `include(...)` unless the project documents why that flexibility
  is necessary.
- Use local module imports explicitly so owner and dependency edges remain
  searchable.

Harness implication:

- Owner branches should be inferred from entry files, include edges, local
  modules, public API families, and path namespaces.
- Search entries for owners are a central Agent surface, not a convenience
  feature.
- Dynamic include sites should stay policy-visible because they hide the repair
  graph.

### 3. API Shape Should Express Multiple-Dispatch Intent

Julia quality is not "classes with methods." Good Julia APIs expose operations
as functions, use exported or `public` names as the contract, and keep fields as
implementation detail unless documented otherwise. Argument order should feel
like Base where possible. Mutating functions should use `!`, and their
docstrings should say what is mutated when several arguments are present.

Agent implication:

- Add methods to a coherent function family instead of inventing near-duplicate
  names.
- Prefer named keyword options or domain carriers over clusters of positional
  `Bool` flags or stringly mode/status arguments.
- Avoid type piracy and accidental extension of external methods.
- Keep exported/public names documented and searchable.

Harness implication:

- Public API, exported names, method families, argument facts, bool flags,
  stringly domains, concrete return annotations, and docstring bindings are
  core parser facts.
- Advisory policy should push agents toward explicit API intent, not merely
  toward shorter functions.
- Exported methods with concrete return annotations should document the return
  or type-stability contract so agents do not add narrow runtime assertions as
  cosmetic precision.

### 4. Algorithm Shape Must Be Agent-Readable

The target reader is also an agent. A function can be correct for Julia and
still be hard for an agent to safely repair if it mixes traversal, filtering,
mutation, branching, and result shaping in one broad nested loop. Nested loops
are not automatically bad, especially in numeric kernels. The smell is an
unexplained traversal shape where the repair intent is hidden.

Agent implication:

- Put hot or broad code inside functions, not scripts.
- Split traversal from predicates, mapping, accumulation, and formatting when
  the body becomes broad or deeply nested.
- Prefer named iterator, predicate, reducer, or pipeline helpers when they make
  the algorithm easier to search and patch.
- Use broadcasting or generic iteration when it accurately expresses the data
  contract. Do not turn every loop into clever syntax.
- Keep macros around syntax convenience or domain notation; do not hide core
  behavior from parser/search unless the macro contract is documented.

Harness implication:

- Function facts should include control-flow depth, branch count, loop count,
  loop nesting depth, macro count, broad-body shape, and named call pipelines.
- Search tags such as `control-flow`, `loop`, `nested-loop`, `branchy`,
  `broad-body`, `macro`, and `pipeline` are quality-navigation signals.
- Advisory rules should separate public API algorithm shape from internal
  traversal shape. The repair advice for each is different.
- Testset facts should carry the same parser-visible shape signals so `Pkg.test`
  can point agents away from broad nested scenario scaffolding and toward named
  behavioral cases.

### 5. Performance Quality Is Evidence-Driven

Julia performance guidance repeatedly comes back to the same pattern: place
performance-critical code in functions, avoid untyped globals, keep types
stable, avoid abstract fields and ambiguous containers in hot structures, and
use measurement tools before making low-level changes. Mature ecosystem guides
add a pragmatic rule: either write non-allocating code with explicit cache
reuse, or write out-of-place code that treats inputs as immutable. Mixing both
styles without a reason is hard to maintain and hard for agents to repair.

Agent implication:

- Before optimizing, identify the hot owner and record the verification command
  that proves the concern.
- Avoid non-const mutable globals in package source. Prefer explicit state
  owners, dependency-injected caches, or `const` handles with documented
  lifecycle/reset behavior.
- Avoid `Any`, `Function`, and broad abstract field types in public structs.
  Use concrete fields or type parameters so public data contracts stay
  inferable.
- Document public failure behavior when exported methods throw, call `error`,
  or use assertions. Hidden failure paths make agent repair brittle because the
  input preconditions are not visible at the API boundary.
- Cover those documented failure contracts with `@test_throws` so invalid-input
  behavior remains executable in the same package test loop.
- Cover documented public mutation contracts by calling the `!` API in package
  tests, so in-place behavior is not only described in prose.
- Cover documented concrete return/type-stability contracts with `@inferred`
  tests so public precision remains executable in `Pkg.test`.
- Cover public safety or performance evidence contracts by calling the unsafe
  owner API in package tests, so risky implementation choices stay executable
  in `Pkg.test`.
- Prefer type-stable helper boundaries and function barriers over scattered
  local annotations.
- Use `@inbounds`, `ccall`, `eval`, process execution, and unsafe operations
  only with a concrete reason and focused tests.
- For numerical and collection code, test more than one relevant input type
  when the API claims generic behavior.

Harness implication:

- Performance verification should be inferred from project evidence: benchmark
  files, test receipts, JET/profile receipts, explicit hot-owner tags, or
  parser-visible algorithm shapes such as `nested-loop`, `branchy`, and
  `broad-body`.
- Parser facts should capture package-level binding initializer shape so policy
  can distinguish local scratch assignments from mutable global state.
- Public field type annotations should feed advisory policy for abstract field
  risks, not just missing-field-type checks.
- Public method failure paths should be derived from call and macro facts so
  `Pkg.test` can remind agents to document errors and preconditions.
- Test facts should connect `@test_throws` coverage back to public failure
  contracts by parser-visible call names.
- Test call facts should connect public `!` method contracts back to package
  tests that actually exercise the mutating API.
- Test facts should connect `@inferred` coverage back to public concrete
  return/type-stability contracts.
- Testset shape facts should flag nested loops plus guard branches in package
  tests, because those broad scenario matrices are hard for agents to repair
  one behavior at a time.
- Unsafe construct facts should connect documented public evidence contracts
  back to package tests that call the public API, rather than accepting
  verification prose as enough.
- Unsafe and escape-like constructs should require explanation and evidence,
  not a silent config disable.

### 6. Tests And Docs Are Part Of The Project Contract

High-quality Julia packages use tests and docs as project surfaces. `Pkg.test`
is the first common test gate. Mature projects commonly keep `runtests.jl` as
an aggregate, split test files by owner or feature, and add tests with behavior
changes. Documentation is not separate prose: docstrings, manual pages,
examples, and doctests help keep public API behavior executable.

Harness modularity should therefore apply to every project-owned Julia file
discovered from `Project.toml` scope, not only `src/`. Oversized `ext/` and
`test/` owners are just as costly for agents as oversized implementation files.

Agent implication:

- Pair new functionality with tests, and bug fixes with regression tests.
- Keep `test/runtests.jl` as a runner/aggregate once a package grows.
- Add or update docstrings for exported/public names.
- Prefer doctestable examples for public API examples when the docs use
  Documenter.
- Run the package's existing test command before adding new verification
  surfaces.

Harness implication:

- Verification profiles should guide agents toward `Pkg.test`, docs/doctests,
  extension tests, and focused receipts.
- The harness should remind the agent to improve verification based on current
  project facts. It should not wait for the user to specify every test.

### 7. Anti-Escape Policy Must Be Agent-Facing

JuMP's AI policy is human-review oriented, but the harness lesson is broader:
AI-assisted changes need responsibility, explanation, and evidence. In this
repo, the first consumer is the agent itself. A config escape that suppresses
policy without a concrete reason is not a responsible interface.

Agent implication:

- When policy is wrong, explain the project-specific reason and provide a
  verification receipt.
- Prefer improving code, tests, docs, or parser facts over adding a loose
  disable.
- Treat harness advice as a repair queue, not as user-facing nag text.

Harness implication:

- Escape hatches must require structured explanations.
- Self-apply should remain active so the harness cannot normalize weak policy
  for downstream packages.
- Renderers should keep advice compact enough that an agent can consume it
  during tests without drowning in JSON.

## Mapping Into The Current Harness

Already implemented or designed:

- Project discovery uses `Project.toml` as the package authority.
- The parser layer is `JuliaSyntax.jl`-native.
- Policy consumes parser facts instead of raw source rescans.
- The reasoning tree exposes package owners, include edges, public surface, and
  test/source shape.
- Search is parser-backed and includes owner entries, public/API entries,
  docstrings, calls, identifiers, arguments, fields, tests, and algorithm-shape
  tags.
- Advisory rules cover public docs, bool/stringly arguments, exported-name
  conflicts, large owner fanout, public algorithm shape, scattered method
  families, macro-heavy APIs, public return contracts, public failure
  contracts, public return `@inferred` coverage, public failure contracts,
  public failure `@test_throws` coverage, mutable global state, public abstract
  field types, struct field contracts, mutable-struct mutation contracts,
  mutating-method mutation contracts, mutating-method test coverage,
  parser-visible testset scenario-shape advice, unsafe construct evidence
  contracts, unsafe evidence test coverage, public generic API type coverage,
  Documenter public API doctest examples, Moshi-optional typed domain modeling
  advice, external-method type-piracy risk, in-test verification hooks, and
  internal nested traversal shape.
- Verification profile and receipt surfaces let `Pkg.test` show agents what to
  verify next.
- Agent snapshots include compact verification tasks so a single context packet
  can show package ownership, syntax facts, findings, and the next runnable
  gates an agent should use.
- Search index entries include verification tasks in Project.toml-rooted mode,
  allowing agents to retrieve examples, benchmark, docs, extension, and
  receipt-required gates with the same search API used for syntax facts.
- Config escape surfaces require explanations.
- Documenter docs projects with `docs/Project.toml` and `docs/make.jl` produce
  a `docs_build` verification task so agents can run docs and doctest checks as
  part of project verification.
- Package-owned examples projects with `examples/Project.toml` and
  `examples/runexamples.jl`, `examples/runtests.jl`, or `examples/examples.jl`
  produce an `example_run` verification task. This keeps user-facing examples
  executable without treating every loose script under `examples/` as a package
  scope.
- Conventional Julia benchmark and strict performance entries under
  `benchmark/`, `benchmarks/`, `perf/`, and `test/perf/` produce explicit
  `performance` tasks. If a local benchmark `Project.toml` exists, the command
  activates that environment; otherwise it runs from the package root project.
  These runnable tasks suppress duplicate inferred performance advice while
  still requiring receipts for benchmark command, baseline, threshold, runtime
  or allocation metric, and artifact.
- Package extensions produce `extension_boundary` verification advice with
  parser/Pkg evidence about whether weakdeps are activated by the package test
  target or still need an Agent-added activation path.
- Moshi is treated as an optional expression layer for ADTs and pattern
  matching. The harness parses `@data`, `@match`, and `@derive` as JuliaSyntax
  facts, keeps Moshi behind `[weakdeps]` and `[extensions]`, and self-applies
  that policy through `AspJuliaMoshiExt` instead of adding
  Moshi to the core runtime dependencies. Agent snapshots and search entries
  expose the configured Moshi extension, activation state, and compact
  capability labels without requiring the core process to load Moshi first.
  Verification tasks and profiles carry the same capability evidence, so an
  agent can see typed-domain repair affordances directly in the test log.
  Stringly-domain findings also carry project-local labels for the Moshi
  extension state and likely `ext/<PackageName>MoshiExt.jl` repair target.
  A configured extension is not enough to satisfy the policy: the parser must
  see Moshi modeling facts that cover the extracted branch literals before
  R020 is suppressed when those literals are available.
  A covered `@data` surface is still only the first step. The harness also
  advises agents to add parser-visible `@match` cases or typed methods that
  use the model, so real project logic moves away from repeated string
  comparisons instead of merely parking an unused ADT in an extension.

Useful next policy slices:

- Workspace-level verification receipts should distinguish root package tasks
  from member package tasks so agents can close multi-package evidence without
  confusing owners.

## Agent Operating Checklist

For an agent changing a Julia project under this harness:

1. Start from the `Project.toml` root, not a random working directory.
2. Read the compact agent snapshot before editing.
3. Use owner search to find the relevant project branch.
4. Use tag search for risky repair zones: `nested-loop`, `branchy`,
   `broad-body`, `macro`, `stringly`, `bool`, and `public`.
5. Make the smallest owner-scoped change that preserves package API intent.
6. Add or update tests, docs, doctests, or verification receipts based on the
   changed owner.
7. Run `Pkg.test()` or the project-native test command.
8. Run the harness test profile and treat advice as a repair queue.
9. Add policy exceptions only with a concrete explanation and evidence.

## Design Rule

The harness should not try to make every Julia project look the same. It should
make the important project facts legible enough that an agent can write Julia
that is idiomatic, performant where it matters, documented where it is public,
tested where it changes behavior, and structured so the next agent can safely
continue the work.
