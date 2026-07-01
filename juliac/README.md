# JuliaC ASP provider app

This directory builds the JuliaC executable for the Julia provider. The
executable keeps JuliaSyntax as the fact authority while giving the Rust ASP
client a stable provider command for facade routing and cache refresh.

Build:

```sh
julia --project=juliac -e 'using Pkg; Pkg.instantiate()'
ASP_JULIA_BUILD_DIR=build/juliac julia --project=juliac juliac/compile.jl
```

The install path should call the provider-owned build wrapper instead of
depending on an untracked local executable:

```sh
ASP_JULIA_BUILD_DIR=build/juliac-asp-local juliac/build_provider.sh
```

`build_provider.sh` first attempts the JuliaC build. If JuliaC fails and
`ASP_JULIA_ALLOW_WRAPPER_FALLBACK` is not `0`, it writes an executable wrapper
with the same `asp-julia-harness` command surface that dispatches through the
Julia project runtime. This keeps activation reproducible on machines where
the JuliaC compile is too expensive or unavailable. Set `JULIA` to override
the Julia command used by the build attempt and by the generated wrapper.

Smoke:

```sh
build/juliac/asp-julia-harness guide .
build/juliac/asp-julia-harness agent doctor --json .
build/juliac/asp-julia-harness search lexical parser owner tests --workspace . --view seeds
build/juliac/asp-julia-harness export index .
```

Rust/asp should call `asp-julia-harness export index <project-root>` on cache
miss or stale cache generations. The command emits the main-repository
`semantic-native-syntax-fact-index.v1` schema shape, then Rust can query and
render from its cache. It should not run nested commands such as
`<rust-bin> <julia-bin> search`.
