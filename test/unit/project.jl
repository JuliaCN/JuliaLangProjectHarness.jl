function write_project(root::AbstractString, name::AbstractString)
    write(
        joinpath(root, "Project.toml"),
        """
        name = "$(name)"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"

        [extras]
        Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

        [targets]
        test = ["Test"]
        """,
    )
end

include("project/core.jl")
include("project/project_toml_facts.jl")
include("project/policy.jl")
include("project/agent_api.jl")
include("project/unsafe_contracts.jl")
include("project/return_contracts.jl")
include("project/global_state.jl")
include("project/field_types.jl")
include("project/error_contracts.jl")
include("project/mutation_contracts.jl")
include("project/test_shape.jl")
include("project/agent_verification.jl")
include("project/moshi_policy.jl")
include("project/moshi.jl")
include("project/ownership_api.jl")
include("project/ownership_algorithms.jl")
include("project/modularity.jl")
