package dynview_parse

// Describe one verified mathematical alphanumeric command.
Tex_Math_Alphabet :: struct {
    command: string,
    role: Tex_Math_Style_Role,
    uppercase_start: u32,
    lowercase_start: u32,
    digit_start: u32,
}

TEX_MATH_ALPHABETS :: [?]Tex_Math_Alphabet{
    {"\\mathbb", .Mathbb, 0x1D538, 0x1D552, 0x1D7D8},
    {"\\mathbf", .Mathbf, 0x1D400, 0x1D41A, 0x1D7CE},
    {"\\mathit", .Mathit, 0x1D434, 0x1D44E, 0},
    {"\\mathcal", .Mathcal, 0x1D49C, 0, 0},
}

TEX_MATHBB_UPPERCASE_EXCEPTIONS :: [7]u32{
    0x2102, 0x210D, 0x2115, 0x2119, 0x211A, 0x211D, 0x2124}
TEX_MATHBB_UPPERCASE_INDICES :: [7]u8{'C', 'H', 'N', 'P', 'Q', 'R', 'Z'}
TEX_MATHCAL_UPPERCASE_EXCEPTIONS :: [8]u32{
    0x212C, 0x2130, 0x2131, 0x210B, 0x2110, 0x2112, 0x2133, 0x211B}
TEX_MATHCAL_UPPERCASE_INDICES :: [8]u8{'B', 'E', 'F', 'H', 'I', 'L', 'M', 'R'}

//   Resolve one mathematical alphabet command.
tex_math_alphabet_spec :: proc(command: string) -> (Tex_Math_Alphabet, bool) {
    for alphabet in TEX_MATH_ALPHABETS {
        if alphabet.command == command {
            return alphabet, true
        }
    }
    return {}, false
}

//   Map one ASCII alphanumeric scalar through a verified mathematical alphabet.
tex_math_alphabet_codepoint :: proc(
    alphabet: Tex_Math_Alphabet,
    value: u8) -> (u32, bool) {
    if value >= 'A' && value <= 'Z' && alphabet.uppercase_start != 0 {
        return tex_math_alphabet_uppercase(alphabet.role, value), true
    }
    if value >= 'a' && value <= 'z' && alphabet.lowercase_start != 0 {
        if alphabet.role == .Mathit && value == 'h' {
            return 0x210E, true
        }
        return alphabet.lowercase_start + u32(value-'a'), true
    }
    if value >= '0' && value <= '9' && alphabet.digit_start != 0 {
        return alphabet.digit_start + u32(value-'0'), true
    }
    return 0, false
}

//   Resolve Unicode's legacy exceptions in uppercase math alphabets.
tex_math_alphabet_uppercase :: proc(
    role: Tex_Math_Style_Role,
    value: u8) -> u32 {
    if role == .Mathbb {
        indices := TEX_MATHBB_UPPERCASE_INDICES
        exceptions := TEX_MATHBB_UPPERCASE_EXCEPTIONS
        for index in 0..<len(indices) {
            if indices[index] == value {
                return exceptions[index]
            }
        }
        return 0x1D538 + u32(value-'A')
    }
    if role == .Mathcal {
        indices := TEX_MATHCAL_UPPERCASE_INDICES
        exceptions := TEX_MATHCAL_UPPERCASE_EXCEPTIONS
        for index in 0..<len(indices) {
            if indices[index] == value {
                return exceptions[index]
            }
        }
        return 0x1D49C + u32(value-'A')
    }
    start := u32(0x1D400) if role == .Mathbf else u32(0x1D434)
    return start + u32(value-'A')
}

//   Encode one Unicode scalar into caller-owned UTF-8 bytes.
tex_math_encode_utf8 :: #force_inline proc(
    codepoint: u32,
    output: ^[4]u8) -> int {
    if codepoint <= 0x7F {
        output[0] = u8(codepoint)
        return 1
    }
    if codepoint <= 0x7FF {
        output[0] = u8(0xC0 | codepoint >> 6)
        output[1] = u8(0x80 | codepoint & 0x3F)
        return 2
    }
    if codepoint <= 0xFFFF {
        output[0] = u8(0xE0 | codepoint >> 12)
        output[1] = u8(0x80 | codepoint >> 6 & 0x3F)
        output[2] = u8(0x80 | codepoint & 0x3F)
        return 3
    }
    output[0] = u8(0xF0 | codepoint >> 18)
    output[1] = u8(0x80 | codepoint >> 12 & 0x3F)
    output[2] = u8(0x80 | codepoint >> 6 & 0x3F)
    output[3] = u8(0x80 | codepoint & 0x3F)
    return 4
}

//   Append one mapped alphabet source into bounded semantic text storage.
tex_math_append_alphabet_text :: proc(
    output: ^Tex_Semantic_Output,
    source: string,
    alphabet: Tex_Math_Alphabet) -> (Tex_Text_Span, bool) {
    start := output.text_count
    for value in transmute([]u8)source {
        codepoint, ok := tex_math_alphabet_codepoint(alphabet, value)
        if !ok {
            output.text_count = start
            return {}, false
        }
        encoded: [4]u8
        encoded_count := tex_math_encode_utf8(codepoint, &encoded)
        if encoded_count > len(output.text)-output.text_count {
            output.text_count = start
            return {}, false
        }
        copy(output.text[output.text_count:], encoded[:encoded_count])
        output.text_count += encoded_count
    }
    return {offset = start, length = output.text_count-start}, true
}
