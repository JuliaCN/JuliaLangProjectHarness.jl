const JULIA_VERIFICATION_RECEIPT_ESCAPE_STATES = Set(["skip", "skipped", "waive", "waived"])
const JULIA_VERIFICATION_RECEIPT_CLEAN_STATUSES = Set([:accepted, :waived, :not_required])
const JULIA_VERIFICATION_RECEIPT_RELATIVE_PATHS = [
    joinpath(".asp-julia", "verification-receipts.json"),
]

"""Read agent verification receipts from a compact JSON file."""
function read_julia_verification_receipts_json(path::AbstractString)
    payload = JSON.parse(read(path, String))
    raw_receipts = json_payload_receipts(payload)
    [verification_receipt_dict(receipt) for receipt in raw_receipts]
end

function review_julia_project_verification_receipts(index::JuliaVerificationTaskIndex)
    reviews = JuliaVerificationReceiptReview[]
    for path in existing_julia_verification_receipt_paths(index.project_root)
        append!(
            reviews,
            review_julia_verification_receipts(
                index,
                read_julia_verification_receipts_json(path),
            ),
        )
    end
    reviews
end

function existing_julia_verification_receipt_paths(project_root::AbstractString)
    root = abspath(String(project_root))
    [
        joinpath(root, relative_path) for relative_path in
        JULIA_VERIFICATION_RECEIPT_RELATIVE_PATHS if isfile(joinpath(root, relative_path))
    ]
end

function json_payload_receipts(payload)
    payload isa AbstractVector && return payload
    if haskey(payload, :receipts)
        return payload[:receipts]
    end
    payload
end

function verification_receipt_dict(receipt)
    Dict(String(key) => verification_receipt_value(value) for (key, value) in pairs(receipt))
end

function verification_receipt_value(value)
    isnothing(value) && return ""
    value isa AbstractVector && return join(string.(value), ",")
    string(value)
end

"""Review agent-submitted receipts against the required evidence contracts."""
function review_julia_verification_receipts(
    index::JuliaVerificationTaskIndex,
    receipts::Vector{<:AbstractDict},
)
    required_records = [
        record for record in index.records if !isempty(verification_task_required_evidence(record))
    ]
    by_fingerprint = Dict{String,AbstractDict}()
    duplicate_fingerprints = Set{String}()
    for receipt in receipts
        fingerprint = receipt_value(receipt, "fingerprint")
        isempty(fingerprint) && continue
        if haskey(by_fingerprint, fingerprint)
            push!(duplicate_fingerprints, fingerprint)
        else
            by_fingerprint[fingerprint] = receipt
        end
    end

    reviews = JuliaVerificationReceiptReview[]
    for record in required_records
        receipt = get(by_fingerprint, record.fingerprint, nothing)
        review = review_julia_verification_receipt(record, receipt)
        if record.fingerprint in duplicate_fingerprints
            review = append_receipt_review_problem(review, "duplicate receipt fingerprint")
        end
        push!(reviews, review)
    end

    required_fingerprints = Set(record.fingerprint for record in required_records)
    for receipt in receipts
        fingerprint = receipt_value(receipt, "fingerprint")
        isempty(fingerprint) && continue
        fingerprint in required_fingerprints && continue
        push!(reviews, orphan_verification_receipt_review(index, receipt, fingerprint))
    end
    reviews
end

function review_julia_verification_receipt(
    record::JuliaVerificationTaskRecord,
    receipt::Union{Nothing,AbstractDict},
)
    required = verification_task_required_evidence(record)
    isempty(required) && return verification_receipt_review(record, "not_required")
    isnothing(receipt) && return verification_receipt_review(
        record,
        "missing",
        required,
        String[],
        ["no receipt matched this task fingerprint"],
    )

    receipt_state = lowercase(strip(receipt_value(receipt, "state"; default="reported")))
    if receipt_state in JULIA_VERIFICATION_RECEIPT_ESCAPE_STATES
        explanation = receipt_value(receipt, "explanation"; default="")
        has_concrete_explanation(explanation) && return verification_receipt_review(record, "waived")
        return verification_receipt_review(
            record,
            "incomplete",
            String[],
            String[],
            ["waived or skipped receipt requires a concrete explanation"],
        )
    end

    missing = [key for key in required if !has_receipt_key(receipt, key)]
    weak = [
        key for key in required if has_receipt_key(receipt, key) &&
        !has_concrete_receipt_value(receipt_value(receipt, key))
    ]
    problems = String[]
    receipt_fingerprint = receipt_value(receipt, "fingerprint"; default=record.fingerprint)
    receipt_fingerprint == record.fingerprint ||
        push!(problems, "receipt fingerprint does not match task fingerprint")
    append!(problems, receipt_binding_problems(record, receipt))
    status = isempty(missing) && isempty(weak) && isempty(problems) ? "accepted" : "incomplete"
    verification_receipt_review(record, status, missing, weak, problems)
end

function receipt_binding_problems(
    record::JuliaVerificationTaskRecord,
    receipt::AbstractDict,
)
    problems = String[]
    if has_receipt_key(receipt, "kind")
        kind = receipt_value(receipt, "kind")
        !isempty(kind) && kind != record.kind &&
            push!(problems, "receipt kind does not match task kind")
    end
    if has_receipt_key(receipt, "owner_path")
        owner_path = receipt_value(receipt, "owner_path")
        !isempty(owner_path) && !receipt_owner_path_matches(record, owner_path) &&
            push!(problems, "receipt owner_path does not match task owner")
    end
    problems
end

function receipt_owner_path_matches(
    record::JuliaVerificationTaskRecord,
    receipt_owner_path::AbstractString,
)
    normalized = slash_path(normpath(String(receipt_owner_path)))
    absolute_owner = slash_path(normpath(record.owner_path))
    relative_owner = slash_path(normpath(relpath(record.owner_path, record.project_root)))
    normalized == absolute_owner || normalized == relative_owner
end

function verification_receipt_review(
    record::JuliaVerificationTaskRecord,
    status,
    missing::Vector{String}=String[],
    weak::Vector{String}=String[],
    problems::Vector{String}=String[],
)
    JuliaVerificationReceiptReview(
        record.fingerprint,
        record.kind,
        Symbol(status),
        record.project_root,
        record.owner_path,
        missing,
        weak,
        problems,
        verification_task_required_receipt(record),
    )
end

function append_receipt_review_problem(
    review::JuliaVerificationReceiptReview,
    problem::AbstractString,
)
    JuliaVerificationReceiptReview(
        review.fingerprint,
        review.kind,
        :incomplete,
        review.project_root,
        review.owner_path,
        copy(review.missing_evidence),
        copy(review.weak_evidence),
        vcat(review.problems, String(problem)),
        review.required_receipt,
    )
end

function orphan_verification_receipt_review(
    index::JuliaVerificationTaskIndex,
    receipt::AbstractDict,
    fingerprint::AbstractString,
)
    JuliaVerificationReceiptReview(
        String(fingerprint),
        receipt_value(receipt, "kind"; default="<unknown>"),
        :orphan,
        index.project_root,
        receipt_value(receipt, "owner_path"; default="<unknown>"),
        String[],
        String[],
        ["receipt fingerprint did not match any required external task"],
        "",
    )
end

function receipt_value(receipt::AbstractDict, key::AbstractString; default="")
    value =
        haskey(receipt, String(key)) ? receipt[String(key)] :
        get(receipt, Symbol(key), default)
    verification_receipt_value(value)
end

function has_receipt_key(receipt::AbstractDict, key::AbstractString)
    haskey(receipt, String(key)) || haskey(receipt, Symbol(key))
end

function has_concrete_receipt_value(value::AbstractString)
    normalized = lowercase(strip(value))
    isempty(normalized) && return false
    is_placeholder_explanation(normalized) && return false
    true
end

function is_julia_verification_receipt_review_clean(review::JuliaVerificationReceiptReview)
    review.status in JULIA_VERIFICATION_RECEIPT_CLEAN_STATUSES
end

"""Assert that submitted verification receipts satisfy or explain every required task."""
function assert_julia_verification_receipts_accepted(
    index::JuliaVerificationTaskIndex,
    receipts::Vector{<:AbstractDict},
)
    reviews = review_julia_verification_receipts(index, receipts)
    all(is_julia_verification_receipt_review_clean, reviews) ||
        error(render_julia_verification_receipt_reviews(reviews; project_root=index.project_root))
    reviews
end

"""Render receipt review results as compact text for agent repair."""
function render_julia_verification_receipt_reviews(
    reviews::Vector{JuliaVerificationReceiptReview};
    project_root::Union{Nothing,AbstractString}=nothing,
)
    isempty(reviews) && return "[ok] julia verification receipts no-required-external-tasks\n"
    accepted = count(is_julia_verification_receipt_review_clean, reviews)
    incomplete = length(reviews) - accepted
    lines = [
        "VerificationReceiptReview: count=$(length(reviews)) accepted=$(accepted) incomplete=$(incomplete)",
    ]
    for review in reviews
        owner = verification_receipt_owner_path(review, project_root)
        push!(lines, "- kind=$(review.kind) status=$(review.status) owner=$(owner)")
        push!(lines, "  fingerprint=$(review.fingerprint)")
        !isempty(review.missing_evidence) &&
            push!(lines, "  missing=$(join(review.missing_evidence, ","))")
        !isempty(review.weak_evidence) &&
            push!(lines, "  weak=$(join(review.weak_evidence, ","))")
        !isempty(review.problems) && push!(lines, "  problem=$(join(review.problems, ";"))")
        !isempty(review.required_receipt) && push!(lines, "  requires=$(review.required_receipt)")
    end
    join(lines, "\n") * "\n"
end

function verification_receipt_owner_path(
    review::JuliaVerificationReceiptReview,
    project_root::Union{Nothing,AbstractString},
)
    isnothing(project_root) && return slash_path(review.owner_path)
    relative_path = relpath(review.owner_path, String(project_root))
    parts = splitpath(relative_path)
    if !isabspath(relative_path) && (isempty(parts) || first(parts) != "..")
        return slash_path(relative_path)
    end
    slash_path(review.owner_path)
end

"""Render receipt review results as JSON for machines that need the full shape."""
function render_julia_verification_receipt_reviews_json(
    reviews::Vector{JuliaVerificationReceiptReview},
)
    JSON.json(Dict("reviews" => map(verification_receipt_review_dict, reviews)))
end

function verification_receipt_review_dict(review::JuliaVerificationReceiptReview)
    Dict(
        "fingerprint" => review.fingerprint,
        "kind" => review.kind,
        "status" => String(review.status),
        "project_root" => slash_path(review.project_root),
        "owner_path" => slash_path(review.owner_path),
        "missing_evidence" => review.missing_evidence,
        "weak_evidence" => review.weak_evidence,
        "problems" => review.problems,
        "required_receipt" => review.required_receipt,
    )
end
