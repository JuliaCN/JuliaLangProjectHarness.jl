# JuliaC ASP provider app

This directory builds the JuliaC executable for the Julia provider. The
executable keeps JuliaSyntax as the fact authority while giving the Rust ASP
client a stable provider command for facade routing and cache refresh.

Build:

```sh
julia --project=juliac -e 'using Pkg; Pkg.instantiate()'
ASP_JULIA_BUILD_DIR=build/juliac julia --project=juliac juliac/compile.jl
```

Smoke:

```sh
build/juliac/asp-julia-harness guide .
build/juliac/asp-julia-harness agent doctor --json .
build/juliac/asp-julia-harness search fzf parser owner tests --view seeds .
build/juliac/asp-julia-harness export index .
```

Rust/asp should call `asp-julia-harness export index <project-root>` on cache
miss or stale cache generations. The command emits the main-repository
`semantic-native-syntax-fact-index.v1` schema shape, then Rust can query and
render from its cache. It should not run nested commands such as
`<rust-bin> <julia-bin> search`.
