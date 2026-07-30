"""Build a JSON-ready verification receipt template from required external tasks."""
function julia_verification_receipt_template(index::JuliaVerificationTaskIndex)
    Dict(
        "project_root" => slash_path(index.project_root),
        "receipts" => [
            julia_verification_receipt_template_record(index, record) for record in
            index.records if !isempty(verification_task_required_evidence(record))
        ],
    )
end

function julia_verification_receipt_template_record(
    index::JuliaVerificationTaskIndex,
    record::JuliaVerificationTaskRecord,
)
    template = Dict{String,Any}(
        "fingerprint" => record.fingerprint,
        "kind" => record.kind,
        "owner_path" => verification_owner_path(index, record),
        "state" => "reported",
        "required_receipt" => verification_task_required_receipt(record),
        "task_evidence" => record.evidence,
    )
    for key in verification_task_required_evidence(record)
        template[key] = ""
    end
    template
end

"""Render a JSON receipt template that agents can fill and submit for review."""
function render_julia_verification_receipt_template(index::JuliaVerificationTaskIndex)
    JSON.json(julia_verification_receipt_template(index))
end
