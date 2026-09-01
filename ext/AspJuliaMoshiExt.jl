module AspJuliaMoshiExt

using AspJulia
using Moshi.Data: @data
using Moshi.Match: @match

@data MoshiHarnessCapability begin
    SyntaxFacts(String)
    DomainModelAdvice(String)
    SearchSurface(String)
end

function moshi_extension_capability_lines()
    capabilities = MoshiHarnessCapability.Type[
        MoshiHarnessCapability.SyntaxFacts(
            "native JuliaSyntax facts for Moshi @data/@match/@derive",
        ),
        MoshiHarnessCapability.DomainModelAdvice(
            "typed domain carriers for stringly branch dispatch in source deps or optional extensions",
        ),
        MoshiHarnessCapability.SearchSurface(
            "agent search and snapshots for Moshi modeling forms",
        ),
    ]
    render_moshi_harness_capability.(capabilities)
end

function render_moshi_harness_capability(capability::MoshiHarnessCapability.Type)
    @match capability begin
        MoshiHarnessCapability.SyntaxFacts(detail) => "syntax: $(detail)"
        MoshiHarnessCapability.DomainModelAdvice(detail) => "domain-model: $(detail)"
        MoshiHarnessCapability.SearchSurface(detail) => "search: $(detail)"
    end
end

end
