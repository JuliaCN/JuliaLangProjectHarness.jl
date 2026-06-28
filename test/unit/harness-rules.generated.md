# JuliaLangProjectHarness.jl

## Harness Rules

Generated from embedded `src/harness-rules.md`.

- **AGENT-JL-R001**: Requires exported or public Julia APIs to carry intent docstrings for native syntax reasoning.
- **AGENT-JL-R002**: Replaces broad public Julia positional argument surfaces with keyword options or named config objects.
- **AGENT-JL-R003**: Replaces multiple public Julia positional Bool flags with keyword options or named config objects.
- **AGENT-JL-R004**: Replaces stringly public Julia domain arguments with named domain carriers.
- **AGENT-JL-R005**: Keeps public Julia API names owned by one file or documented as extension patterns.
- **AGENT-JL-R006**: Requires module owner fan-out files to document aggregation intent.
- **AGENT-JL-R007**: Requires public Julia methods to expose algorithm shape through named pipeline steps.
- **AGENT-JL-R008**: Splits broad public Julia method bodies into named pipeline steps.
- **AGENT-JL-R009**: Requires public method families scattered across owners to document dispatch or extension patterns.
- **AGENT-JL-R010**: Requires macro-heavy public Julia APIs to document syntax or generated-code contracts.
- **AGENT-JL-R011**: Requires exported Julia struct fields to carry explicit type annotations.
- **AGENT-JL-R012**: Replaces stringly exported Julia struct fields with symbols, enums, or named value carriers.
- **AGENT-JL-R013**: Requires exported mutable Julia types to document mutation ownership, lifecycle, or invariants.
- **AGENT-JL-R014**: Requires Julia packages depending on the harness to mount the harness verification profile in package tests.
- **AGENT-JL-R015**: Extracts internal nested traversal scaffolding into named iterators, predicates, or data helpers.
- **AGENT-JL-R016**: Requires exported mutating Julia methods to document mutated state or arguments.
- **AGENT-JL-R017**: Requires unsafe Julia constructs to document safety or performance evidence.
- **AGENT-JL-R018**: Requires generic public Julia APIs to exercise more than one relevant input type.
- **AGENT-JL-R019**: Requires Documenter-backed public Julia API docs to include executable examples.
- **AGENT-JL-R020**: Replaces stringly branch dispatch with typed domain models or explicit Moshi dependency boundaries.
- **AGENT-JL-R021**: Requires external Julia method extensions to dispatch on package-owned types or document interop contracts.
- **AGENT-JL-R022**: Requires Moshi domain models to expose parser-visible match bridges.
- **AGENT-JL-R023**: Requires public return annotations to document API contracts.
- **AGENT-JL-R024**: Replaces non-const mutable package globals with explicit state objects or resettable handles.
- **AGENT-JL-R025**: Replaces broad exported Julia struct field annotations with concrete fields or type parameters.
- **AGENT-JL-R026**: Requires exported Julia failure paths to document exception, assertion, or precondition behavior.
- **AGENT-JL-R027**: Requires documented exported Julia failure contracts to have parser-visible tests.
- **AGENT-JL-R028**: Requires documented exported mutating Julia contracts to have parser-visible tests.
- **AGENT-JL-R029**: Splits nested Julia testset scenario scaffolding into named testsets or helpers.
- **AGENT-JL-R030**: Requires public unsafe evidence contracts to have parser-visible tests.
- **AGENT-JL-R031**: Requires public return or type-stability contracts to have inferred tests.
- **JULIA-MOD-R001**: Keeps Julia package entry files as compact facades.
- **JULIA-MOD-R002**: Keeps Julia owner files within a bounded responsibility budget.
- **JULIA-MOD-R003**: Keeps Julia source graphs parser-stable with literal include targets.
- **JULIA-MOD-R004**: Requires literal Julia include targets to resolve to existing source files.
- **JULIA-MOD-R005**: Keeps Julia literal include graphs acyclic.
- **JULIA-MOD-R006**: Requires Julia source files to be reachable from the package entry include graph.
- **JULIA-MOD-R007**: Replaces generic Julia source path buckets with domain ownership names.
- **JULIA-AGENT-PROJECT-001**: Requires Project.toml to define a concrete package name.
- **JULIA-AGENT-PROJECT-002**: Requires Julia packages to expose a parser-stable entry file.
- **JULIA-AGENT-PROJECT-003**: Requires Julia package tests to mount the Pkg test entrypoint.
- **JULIA-AGENT-PROJECT-004**: Keeps test runtests files as compact Pkg test aggregates.
- **JULIA-AGENT-PROJECT-005**: Requires custom Julia source or test scopes to carry project-local explanations.
- **JULIA-AGENT-PROJECT-006**: Requires conventional Julia source or test scope exclusions to carry project-local explanations.
- **JULIA-AGENT-PROJECT-007**: Requires package entry files to declare a top-level module matching the package name.
- **JULIA-AGENT-PROJECT-008**: Requires external Julia imports to be declared in project dependency metadata.
- **JULIA-AGENT-PROJECT-009**: Requires registry dependencies to carry compat bounds or source-tracked dependency records.
- **JULIA-AGENT-PROJECT-010**: Requires URL-based source dependencies to lock rev to commit SHAs.
- **JULIA-AGENT-PROJECT-011**: Requires Julia extension entries to resolve to extension entry files.
- **JULIA-AGENT-PROJECT-012**: Requires Julia extension trigger dependencies to be declared.
- **JULIA-AGENT-PROJECT-013**: Requires Project.toml to be readable by Pkg.
- **JULIA-AGENT-PROJECT-014**: Requires harness config escapes to carry concrete explanations.
