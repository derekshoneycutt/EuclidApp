package dynview_parse

// Preserve one fixed TeX command and its Unicode semantic output.
Tex_Math_Fixed_Symbol :: struct {
    command: string,
    text: string,
}

// Preserve one large operator's renderer family and limit policy.
Tex_Math_Large_Operator :: struct {
    command: string,
    text: string,
    family: i32,
    growth: i32,
    limits: i32,
}

// Preserve one accent command, semantic mode, and canonical spelling.
Tex_Math_Accent :: struct {
    command: string,
    mode: Tex_Accent_Mode,
    canonical: string,
}

// Return one fixed symbol together with its semantic classification.
Tex_Math_Symbol_Result :: struct {
    text: string,
    properties: Tex_Math_Glyph_Properties,
}

TEX_MATH_ACCENTS :: [?]Tex_Math_Accent{
    {"\\overline", .Overline, "\\overline"},
    {"\\underline", .Underline, "\\underline"},
    {"\\hat", .Hat, "\\hat"}, {"\\widehat", .Hat, "\\hat"},
    {"\\tilde", .Tilde, "\\tilde"}, {"\\widetilde", .Tilde, "\\tilde"},
    {"\\vec", .Vec, "\\vec"}, {"\\dot", .Dot, "\\dot"},
    {"\\ddot", .Ddot, "\\ddot"}, {"\\bar", .Bar, "\\bar"},
    {"\\check", .Check, "\\check"}, {"\\breve", .Breve, "\\breve"},
    {"\\acute", .Acute, "\\acute"}, {"\\grave", .Grave, "\\grave"},
    {"\\mathring", .Ring, "\\mathring"},
    {"\\overbrace", .Overbrace, "\\overbrace"},
    {"\\underbrace", .Underbrace, "\\underbrace"},
}

TEX_MATH_FIXED_DELIMITER_COMMANDS :: [?]string{
    "\\big", "\\bigl", "\\bigr", "\\bigm", "\\Big", "\\Bigl",
    "\\Bigr", "\\Bigm", "\\bigg", "\\biggl", "\\biggr", "\\biggm",
    "\\Bigg", "\\Biggl", "\\Biggr", "\\Biggm",
}

TEX_MATH_GREEK_SYMBOLS :: [?]Tex_Math_Fixed_Symbol{
    {"\\alpha", "α"}, {"\\beta", "β"}, {"\\gamma", "γ"},
    {"\\delta", "δ"}, {"\\epsilon", "ϵ"}, {"\\varepsilon", "ε"},
    {"\\zeta", "ζ"}, {"\\eta", "η"}, {"\\theta", "θ"},
    {"\\vartheta", "ϑ"}, {"\\iota", "ι"}, {"\\kappa", "κ"},
    {"\\varkappa", "ϰ"}, {"\\lambda", "λ"}, {"\\mu", "μ"},
    {"\\nu", "ν"}, {"\\xi", "ξ"}, {"\\pi", "π"},
    {"\\rho", "ρ"}, {"\\varrho", "ϱ"}, {"\\sigma", "σ"},
    {"\\varsigma", "ς"}, {"\\tau", "τ"}, {"\\upsilon", "υ"},
    {"\\phi", "φ"}, {"\\varphi", "ϕ"}, {"\\chi", "χ"},
    {"\\psi", "ψ"}, {"\\omega", "ω"}, {"\\varpi", "ϖ"},
    {"\\digamma", "ϝ"},
}

TEX_MATH_BINARY_SYMBOLS :: [?]Tex_Math_Fixed_Symbol{
    {"\\pm", "±"}, {"\\mp", "∓"}, {"\\times", "×"},
    {"\\div", "÷"}, {"\\cdot", "·"}, {"\\ast", "∗"},
    {"\\star", "⋆"}, {"\\bullet", "∙"}, {"\\diamond", "⋄"},
    {"\\bigtriangleup", "△"}, {"\\bigtriangledown", "▽"},
    {"\\triangleleft", "◁"}, {"\\triangleright", "▷"},
    {"\\lhd", "⊲"}, {"\\rhd", "⊳"}, {"\\unlhd", "⊴"},
    {"\\unrhd", "⊵"}, {"\\oplus", "⊕"}, {"\\ominus", "⊖"},
    {"\\otimes", "⊗"}, {"\\oslash", "⊘"}, {"\\odot", "⊙"},
    {"\\bigcirc", "○"}, {"\\dagger", "†"}, {"\\ddagger", "‡"},
    {"\\amalg", "⨿"}, {"\\wr", "≀"}, {"\\setminus", "∖"},
    {"\\sqcap", "⊓"}, {"\\sqcup", "⊔"}, {"\\uplus", "⊎"},
    {"\\land", "∧"}, {"\\lor", "∨"}, {"\\wedge", "∧"},
    {"\\vee", "∨"}, {"\\cup", "∪"}, {"\\cap", "∩"},
    {"\\circ", "∘"}, {"\\rtimes", "⋊"},
}

TEX_MATH_RELATION_SYMBOLS :: [?]Tex_Math_Fixed_Symbol{
    {"\\in", "∈"}, {"\\notin", "∉"}, {"\\ni", "∋"},
    {"\\owns", "∋"}, {"\\notni", "∌"}, {"\\subset", "⊂"},
    {"\\subseteq", "⊆"}, {"\\subsetneq", "⊊"},
    {"\\nsubseteq", "⊈"}, {"\\supset", "⊃"},
    {"\\supseteq", "⊇"}, {"\\supsetneq", "⊋"},
    {"\\nsupseteq", "⊉"}, {"\\sqsubset", "⊏"},
    {"\\sqsubseteq", "⊑"}, {"\\sqsupset", "⊐"},
    {"\\sqsupseteq", "⊒"}, {"\\to", "→"},
    {"\\rightarrow", "→"}, {"\\leftarrow", "←"},
    {"\\leftrightarrow", "↔"}, {"\\uparrow", "↑"},
    {"\\downarrow", "↓"}, {"\\updownarrow", "↕"},
    {"\\Rightarrow", "⇒"}, {"\\Leftarrow", "⇐"},
    {"\\iff", "⇔"}, {"\\Leftrightarrow", "⇔"},
    {"\\Uparrow", "⇑"}, {"\\Downarrow", "⇓"},
    {"\\Updownarrow", "⇕"}, {"\\longleftarrow", "⟵"},
    {"\\longrightarrow", "⟶"}, {"\\longleftrightarrow", "⟷"},
    {"\\Longleftarrow", "⟸"}, {"\\Longrightarrow", "⟹"},
    {"\\Longleftrightarrow", "⟺"}, {"\\hookleftarrow", "↩"},
    {"\\hookrightarrow", "↪"}, {"\\nearrow", "↗"},
    {"\\searrow", "↘"}, {"\\swarrow", "↙"}, {"\\nwarrow", "↖"},
    {"\\leftharpoonup", "↼"}, {"\\leftharpoondown", "↽"},
    {"\\rightharpoonup", "⇀"}, {"\\rightharpoondown", "⇁"},
    {"\\rightleftharpoons", "⇌"}, {"\\leftrightharpoons", "⇋"},
    {"\\leadsto", "⇝"}, {"\\mapsto", "↦"}, {"\\leq", "≤"},
    {"\\le", "≤"}, {"\\ge", "≥"}, {"\\geq", "≥"},
    {"\\ll", "≪"}, {"\\gg", "≫"}, {"\\ne", "≠"},
    {"\\neq", "≠"}, {"\\approx", "≈"}, {"\\equiv", "≡"},
    {"\\propto", "∝"}, {"\\prec", "≺"}, {"\\succ", "≻"},
    {"\\preceq", "≼"}, {"\\succeq", "≽"}, {"\\sim", "∼"},
    {"\\simeq", "≃"}, {"\\cong", "≅"}, {"\\asymp", "≍"},
    {"\\doteq", "≐"}, {"\\parallel", "∥"},
    {"\\nparallel", "∦"}, {"\\mid", "∣"}, {"\\nmid", "∤"},
    {"\\perp", "⊥"}, {"\\models", "⊨"}, {"\\vdash", "⊢"},
    {"\\dashv", "⊣"}, {"\\bowtie", "⋈"}, {"\\smile", "⌣"},
    {"\\frown", "⌢"}, {"\\therefore", "∴"}, {"\\because", "∵"},
}

TEX_MATH_OPEN_SYMBOLS :: [?]Tex_Math_Fixed_Symbol{
    {"\\lceil", "⌈"}, {"\\lfloor", "⌊"}, {"\\lvert", "|"},
    {"\\lVert", "‖"}, {"\\{", "{"},
}

TEX_MATH_CLOSE_SYMBOLS :: [?]Tex_Math_Fixed_Symbol{
    {"\\rceil", "⌉"}, {"\\rfloor", "⌋"}, {"\\rvert", "|"},
    {"\\rVert", "‖"}, {"\\}", "}"},
}

TEX_MATH_ORDINARY_SYMBOLS :: [?]Tex_Math_Fixed_Symbol{
    {"\\Gamma", "Γ"}, {"\\Delta", "Δ"}, {"\\Theta", "Θ"},
    {"\\Lambda", "Λ"}, {"\\Xi", "Ξ"}, {"\\Pi", "Π"},
    {"\\Sigma", "Σ"}, {"\\Upsilon", "Υ"}, {"\\Phi", "Φ"},
    {"\\Psi", "Ψ"}, {"\\Omega", "Ω"}, {"\\aleph", "ℵ"},
    {"\\beth", "ℶ"}, {"\\gimel", "ℷ"}, {"\\daleth", "ℸ"},
    {"\\infty", "∞"}, {"\\partial", "∂"}, {"\\nabla", "∇"},
    {"\\forall", "∀"}, {"\\exists", "∃"}, {"\\nexists", "∄"},
    {"\\neg", "¬"}, {"\\emptyset", "∅"}, {"\\varnothing", "∅"},
    {"\\complement", "∁"}, {"\\top", "⊤"}, {"\\bot", "⊥"},
    {"\\dots", "…"}, {"\\ldots", "…"}, {"\\cdots", "⋯"},
    {"\\vdots", "⋮"}, {"\\ddots", "⋱"}, {"\\prime", "′"},
    {"\\hbar", "ℏ"}, {"\\ell", "ℓ"}, {"\\Re", "ℜ"},
    {"\\Im", "ℑ"}, {"\\wp", "℘"}, {"\\angle", "∠"},
    {"\\measuredangle", "∡"}, {"\\sphericalangle", "∢"},
    {"\\triangle", "△"}, {"\\Box", "□"}, {"\\square", "□"},
    {"\\Diamond", "◇"}, {"\\lozenge", "◊"}, {"\\clubsuit", "♣"},
    {"\\diamondsuit", "♢"}, {"\\heartsuit", "♡"},
    {"\\spadesuit", "♠"}, {"\\flat", "♭"}, {"\\natural", "♮"},
    {"\\sharp", "♯"}, {"\\checkmark", "✓"}, {"\\mho", "℧"},
    {"\\degree", "°"}, {"\\surd", "√"}, {"\\vert", "|"},
    {"\\|", "‖"}, {"\\Vert", "‖"}, {"\\backslash", "∖"},
}

TEX_MATH_TEXT_OPERATORS :: [?]string{
    "\\arccos", "\\arcsin", "\\arctan", "\\arg", "\\cos", "\\csc",
    "\\cot", "\\coth", "\\deg", "\\det", "\\dim", "\\exp",
    "\\gcd", "\\hom", "\\inf", "\\ker", "\\lg", "\\liminf",
    "\\limsup", "\\ln", "\\log", "\\max", "\\min", "\\Pr",
    "\\sec", "\\sin", "\\sinh", "\\sup", "\\tan", "\\tanh",
}

TEX_MATH_LARGE_OPERATORS :: [?]Tex_Math_Large_Operator{
    {"\\sum", "∑", 1, 1, 2}, {"\\prod", "∏", 2, 1, 2},
    {"\\coprod", "∐", 2, 1, 2}, {"\\int", "∫", 3, 1, 1},
    {"\\oint", "∮", 3, 1, 1}, {"\\iint", "∬", 3, 1, 1},
    {"\\iiint", "∭", 3, 1, 1}, {"\\bigcup", "⋃", 5, 1, 2},
    {"\\bigcap", "⋂", 5, 1, 2}, {"\\bigvee", "⋁", 5, 1, 2},
    {"\\bigwedge", "⋀", 5, 1, 2}, {"\\bigsqcup", "⨆", 5, 1, 2},
    {"\\biguplus", "⨄", 5, 1, 2}, {"\\bigoplus", "⨁", 5, 1, 2},
    {"\\bigotimes", "⨂", 5, 1, 2}, {"\\bigodot", "⨀", 5, 1, 2},
    {"\\lim", "lim", 4, 0, 2},
}

//   Resolve one historical accent command.
tex_math_registry_accent :: proc(command: string) -> (Tex_Math_Accent, bool) {
    for accent in TEX_MATH_ACCENTS {
        if accent.command == command { return accent, true }
    }
    return {}, false
}

//   Return whether one command selects a fixed-size delimiter.
tex_math_registry_is_fixed_delimiter :: proc(command: string) -> bool {
    for candidate in TEX_MATH_FIXED_DELIMITER_COMMANDS {
        if candidate == command { return true }
    }
    return false
}

//   Resolve the complete frozen fixed-command registry with exact semantics.
tex_math_registry_fixed_symbol :: proc(
    command: string) -> (Tex_Math_Symbol_Result, bool) {
    for entry in TEX_MATH_GREEK_SYMBOLS {
        if entry.command == command {
            return {entry.text, {role = .Math_Italic, atom_class = .Ord}}, true
        }
    }
    for entry in TEX_MATH_BINARY_SYMBOLS {
        if entry.command == command {
            return {entry.text, {role = .Math_Upright, atom_class = .Bin}}, true
        }
    }
    for entry in TEX_MATH_RELATION_SYMBOLS {
        if entry.command == command {
            return {entry.text, {role = .Math_Upright, atom_class = .Rel}}, true
        }
    }
    for entry in TEX_MATH_OPEN_SYMBOLS {
        if entry.command == command {
            return {entry.text, {role = .Math_Upright, atom_class = .Open}}, true
        }
    }
    for entry in TEX_MATH_CLOSE_SYMBOLS {
        if entry.command == command {
            return {entry.text, {role = .Math_Upright, atom_class = .Close}}, true
        }
    }
    for entry in TEX_MATH_ORDINARY_SYMBOLS {
        if entry.command == command {
            return {entry.text, {role = .Math_Upright, atom_class = .Ord}}, true
        }
    }
    return {}, false
}

//   Resolve one frozen text operator without retaining the source slash.
tex_math_registry_text_operator :: proc(command: string) -> (string, bool) {
    for candidate in TEX_MATH_TEXT_OPERATORS {
        if candidate == command {
            return command[1:], true
        }
    }
    return "", false
}

//   Resolve one frozen large operator and its display policy.
tex_math_registry_large_operator :: proc(
    command: string) -> (Tex_Math_Large_Operator, bool) {
    for operator in TEX_MATH_LARGE_OPERATORS {
        if operator.command == command {
            return operator, true
        }
    }
    return {}, false
}
