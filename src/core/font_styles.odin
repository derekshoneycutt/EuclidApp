package core

//   Canonical weight ordering ranks for heaviest-flag resolution.
FONT_WEIGHT_RANKS :: [Font_Weight]int{
    .Light = 1, .Regular = 2, .Medium = 3, .Semibold = 4,
    .Bold = 5, .Extrabold = 6, .Black = 7,
}

//   Weight bits in canonical order; used to pick the heaviest requested weight.
FONT_WEIGHT_FLAG_ORDER :: []Font_Variant_Flags{
    .Light, .Regular, .Medium, .Semibold, .Bold, .Extrabold, .Black,
}

//   Weight value matched one-to-one with FONT_WEIGHT_FLAG_ORDER entries.
FONT_WEIGHT_ORDER :: []Font_Weight{
    .Light, .Regular, .Medium, .Semibold, .Bold, .Extrabold, .Black,
}

//   Return canonical weight ordering rank for heaviest-flag resolution.
font_weight_rank :: #force_inline proc(weight: Font_Weight) -> int {
    ranks := FONT_WEIGHT_RANKS
    return ranks[weight]
}

//   Return true when one requested variant-flag bit is present.
font_has_flag :: #force_inline proc(flags, flag: Font_Variant_Flags) -> bool {
    return (u32(flags) & u32(flag)) != 0
}

//   Resolve one weight from possibly multiple weight bits by choosing the heaviest bit set.
font_resolve_weight_from_flags :: #force_inline proc(
    flags: Font_Variant_Flags) -> Font_Weight {
    resolved := Font_Weight.Regular
    resolved_rank := 0
    flag_order := FONT_WEIGHT_FLAG_ORDER
    weight_order := FONT_WEIGHT_ORDER

    for index in 0..<len(flag_order) {
        if !font_has_flag(flags, flag_order[index]) {
            continue
        }
        rank := font_weight_rank(weight_order[index])
        if rank > resolved_rank {
            resolved = weight_order[index]
            resolved_rank = rank
        }
    }

    return resolved
}

// Convert canonical weight and italic flags to one indexed JuliaMono cache key.
font_key_from_flags :: proc(flags: Font_Variant_Flags) -> Font_Key {
    italic := font_has_flag(flags, .Italic)
    switch font_resolve_weight_from_flags(flags) {
    case .Light:
        return italic ? .Light_Italic : .Light
    case .Medium:
        return italic ? .Medium_Italic : .Medium
    case .Semibold:
        return italic ? .Semi_Bold_Italic : .Semi_Bold
    case .Bold:
        return italic ? .Bold_Italic : .Bold
    case .Extrabold:
        return italic ? .Extra_Bold_Italic : .Extra_Bold
    case .Black:
        return italic ? .Black_Italic : .Black
    case .Regular:
        return italic ? .Regular_Italic : .Regular
    }
    return .Regular
}
