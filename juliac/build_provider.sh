#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${ASP_JULIA_BUILD_DIR:-"${root}/build/juliac"}"
output_exe="${ASP_JULIA_OUTPUT_EXE:-asp-julia-harness}"
output_path="${build_dir}/${output_exe}"
julia_cmd="${JULIA:-julia}"

mkdir -p "${build_dir}"

"${julia_cmd}" --project="${root}/juliac" -e 'using Pkg; Pkg.instantiate()'
ASP_JULIA_BUILD_DIR="${build_dir}" ASP_JULIA_OUTPUT_EXE="${output_exe}" \
  "${julia_cmd}" --project="${root}/juliac" "${root}/juliac/compile.jl"
test -x "${output_path}"
printf '%s\n' "${output_path}"
