mutable struct JuliaProjectJsonCursor
    bytes::Vector{UInt8}
    position::Int
end

JuliaProjectJsonCursor(text::String) =
    JuliaProjectJsonCursor(Vector{UInt8}(codeunits(text)), 1)

function julia_project_json_skip_whitespace!(cursor::JuliaProjectJsonCursor)
    while cursor.position <= length(cursor.bytes)
        byte = cursor.bytes[cursor.position]
        (byte == 0x20 || byte == 0x09 || byte == 0x0a || byte == 0x0d) || break
        cursor.position += 1
    end
    return nothing
end

function julia_project_json_take!(
    cursor::JuliaProjectJsonCursor,
    expected::UInt8,
)
    julia_project_json_skip_whitespace!(cursor)
    cursor.position <= length(cursor.bytes) ||
        throw(ArgumentError("unexpected end of project-resolution JSON"))
    cursor.bytes[cursor.position] == expected ||
        throw(ArgumentError("invalid project-resolution JSON token"))
    cursor.position += 1
    return nothing
end

function julia_project_json_hex(byte::UInt8)::UInt32
    0x30 <= byte <= 0x39 && return UInt32(byte - 0x30)
    0x41 <= byte <= 0x46 && return UInt32(byte - 0x41 + 10)
    0x61 <= byte <= 0x66 && return UInt32(byte - 0x61 + 10)
    throw(ArgumentError("invalid JSON unicode escape"))
end

function julia_project_json_push_codepoint!(bytes::Vector{UInt8}, codepoint::UInt32)
    if codepoint <= 0x7f
        push!(bytes, UInt8(codepoint))
    elseif codepoint <= 0x7ff
        push!(bytes, UInt8(0xc0 | (codepoint >> 6)))
        push!(bytes, UInt8(0x80 | (codepoint & 0x3f)))
    elseif codepoint <= 0xffff
        push!(bytes, UInt8(0xe0 | (codepoint >> 12)))
        push!(bytes, UInt8(0x80 | ((codepoint >> 6) & 0x3f)))
        push!(bytes, UInt8(0x80 | (codepoint & 0x3f)))
    else
        push!(bytes, UInt8(0xf0 | (codepoint >> 18)))
        push!(bytes, UInt8(0x80 | ((codepoint >> 12) & 0x3f)))
        push!(bytes, UInt8(0x80 | ((codepoint >> 6) & 0x3f)))
        push!(bytes, UInt8(0x80 | (codepoint & 0x3f)))
    end
    return nothing
end

function julia_project_json_string!(cursor::JuliaProjectJsonCursor)::String
    julia_project_json_take!(cursor, 0x22)
    result = UInt8[]
    while cursor.position <= length(cursor.bytes)
        byte = cursor.bytes[cursor.position]
        cursor.position += 1
        byte == 0x22 && return String(result)
        byte < 0x20 && throw(ArgumentError("control byte in JSON string"))
        if byte != 0x5c
            push!(result, byte)
            continue
        end
        cursor.position <= length(cursor.bytes) ||
            throw(ArgumentError("unterminated JSON escape"))
        escaped = cursor.bytes[cursor.position]
        cursor.position += 1
        if escaped == 0x22 || escaped == 0x5c || escaped == 0x2f
            push!(result, escaped)
        elseif escaped == 0x62
            push!(result, 0x08)
        elseif escaped == 0x66
            push!(result, 0x0c)
        elseif escaped == 0x6e
            push!(result, 0x0a)
        elseif escaped == 0x72
            push!(result, 0x0d)
        elseif escaped == 0x74
            push!(result, 0x09)
        elseif escaped == 0x75
            cursor.position + 3 <= length(cursor.bytes) ||
                throw(ArgumentError("truncated JSON unicode escape"))
            codepoint = UInt32(0)
            for _ in 1:4
                codepoint =
                    (codepoint << 4) | julia_project_json_hex(cursor.bytes[cursor.position])
                cursor.position += 1
            end
            julia_project_json_push_codepoint!(result, codepoint)
        else
            throw(ArgumentError("unsupported JSON escape"))
        end
    end
    throw(ArgumentError("unterminated JSON string"))
end

function julia_project_json_int!(cursor::JuliaProjectJsonCursor)::Int
    julia_project_json_skip_whitespace!(cursor)
    negative =
        cursor.position <= length(cursor.bytes) && cursor.bytes[cursor.position] == 0x2d
    negative && (cursor.position += 1)
    value = 0
    digits = 0
    while cursor.position <= length(cursor.bytes)
        byte = cursor.bytes[cursor.position]
        0x30 <= byte <= 0x39 || break
        value = value * 10 + Int(byte - 0x30)
        cursor.position += 1
        digits += 1
    end
    digits > 0 || throw(ArgumentError("invalid JSON integer"))
    return negative ? -value : value
end

function julia_project_json_literal!(
    cursor::JuliaProjectJsonCursor,
    literal::String,
)
    for byte in codeunits(literal)
        cursor.position <= length(cursor.bytes) &&
            cursor.bytes[cursor.position] == byte ||
            throw(ArgumentError("invalid JSON literal"))
        cursor.position += 1
    end
    return nothing
end

function julia_project_json_skip_value!(cursor::JuliaProjectJsonCursor)
    julia_project_json_skip_whitespace!(cursor)
    cursor.position <= length(cursor.bytes) ||
        throw(ArgumentError("missing JSON value"))
    byte = cursor.bytes[cursor.position]
    if byte == 0x22
        julia_project_json_string!(cursor)
    elseif byte == 0x7b
        julia_project_json_take!(cursor, 0x7b)
        julia_project_json_skip_whitespace!(cursor)
        if cursor.position <= length(cursor.bytes) && cursor.bytes[cursor.position] == 0x7d
            cursor.position += 1
            return nothing
        end
        while true
            julia_project_json_string!(cursor)
            julia_project_json_take!(cursor, 0x3a)
            julia_project_json_skip_value!(cursor)
            julia_project_json_skip_whitespace!(cursor)
            cursor.bytes[cursor.position] == 0x7d && (cursor.position += 1; break)
            julia_project_json_take!(cursor, 0x2c)
        end
    elseif byte == 0x5b
        julia_project_json_take!(cursor, 0x5b)
        julia_project_json_skip_whitespace!(cursor)
        if cursor.position <= length(cursor.bytes) && cursor.bytes[cursor.position] == 0x5d
            cursor.position += 1
            return nothing
        end
        while true
            julia_project_json_skip_value!(cursor)
            julia_project_json_skip_whitespace!(cursor)
            cursor.bytes[cursor.position] == 0x5d && (cursor.position += 1; break)
            julia_project_json_take!(cursor, 0x2c)
        end
    elseif byte == 0x74
        julia_project_json_literal!(cursor, "true")
    elseif byte == 0x66
        julia_project_json_literal!(cursor, "false")
    elseif byte == 0x6e
        julia_project_json_literal!(cursor, "null")
    else
        julia_project_json_int!(cursor)
    end
    return nothing
end

function julia_project_json_next_key!(
    cursor::JuliaProjectJsonCursor,
    first::Bool,
)::Union{Nothing,String}
    julia_project_json_skip_whitespace!(cursor)
    if cursor.position <= length(cursor.bytes) && cursor.bytes[cursor.position] == 0x7d
        cursor.position += 1
        return nothing
    end
    first || julia_project_json_take!(cursor, 0x2c)
    key = julia_project_json_string!(cursor)
    julia_project_json_take!(cursor, 0x3a)
    return key
end

include("project_resolution_codec/request.jl")
