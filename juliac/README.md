# JuliaC ASLP provider app

This directory builds a JuliaC executable for the workspace-managed Julia
provider. The executable keeps JuliaSyntax as the fact authority while giving
the Rust ASLP client a stable provider command for cache refresh.

Build:

```sh
julia --project=juliac -e 'using Pkg; Pkg.instantiate()'
ASLP_JULIA_BUILD_DIR=build/juliac julia --project=juliac juliac/compile.jl
```

Smoke:

```sh
build/juliac/aslp-julia-harness agent guide .
build/juliac/aslp-julia-harness search fzf parser owner tests --view seeds .
build/juliac/aslp-julia-harness export index .
```

Rust/aslp should call `aslp-julia-harness export index <project-root>` on cache
miss or stale cache generations. The command emits the main-repository
`semantic-native-syntax-fact-index.v1` schema shape, then Rust can query and
render from its cache. It should not run nested commands such as
`<rust-bin> <julia-bin> search`.
