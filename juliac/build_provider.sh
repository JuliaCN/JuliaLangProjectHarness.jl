#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${ASP_JULIA_BUILD_DIR:-"${root}/build/juliac"}"
output_exe="${ASP_JULIA_OUTPUT_EXE:-asp-julia-harness}"
output_path="${build_dir}/${output_exe}"
julia_cmd="${JULIA:-julia}"

mkdir -p "${build_dir}"

if "${julia_cmd}" --project="${root}/juliac" -e 'using Pkg; Pkg.instantiate()' \
  && ASP_JULIA_BUILD_DIR="${build_dir}" ASP_JULIA_OUTPUT_EXE="${output_exe}" \
    "${julia_cmd}" --project="${root}/juliac" "${root}/juliac/compile.jl"; then
  test -x "${output_path}"
  printf '%s\n' "${output_path}"
  exit 0
fi

if [ "${ASP_JULIA_ALLOW_WRAPPER_FALLBACK:-1}" = "0" ]; then
  echo "[build-provider] JuliaC build failed and wrapper fallback is disabled" >&2
  exit 1
fi

cat >"${output_path}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "\${JULIA:-julia}" --project="${root}" "${root}/bin/julia-project-harness.jl" "\$@"
EOF

chmod 755 "${output_path}"
echo "[build-provider] JuliaC build failed; wrote Julia runtime wrapper ${output_path}" >&2
printf '%s\n' "${output_path}"
