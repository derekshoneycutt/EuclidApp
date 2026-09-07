package dynview_core

import "core:mem"
import app_core "../../core"
import dynparse "../parse"

DYNVIEW_DOCUMENT_GRAMMAR_REVISION :: u32(29)
DYNVIEW_DOCUMENT_SEMANTIC_PROFILE_DEFAULT :: u32(1)
DYNVIEW_DOCUMENT_HASH_OFFSET :: u64(14695981039346656037)
DYNVIEW_DOCUMENT_HASH_PRIME :: u64(1099511628211)

// Report document interning and generation-safe resolution outcomes.
Dynview_Document_Status :: enum {
    Ok,
    Rejected,
    Invalid_Argument,
    Illegal_State,
    Not_Found,
    Out_Of_Capacity,
    Allocation_Failed,
}

// Expose immutable semantic views owned by one document-store generation.
Dynview_Document :: struct {
    source: string,
    text: []u8,
    ops: []dynparse.Tex_Math_Op,
    programs: []dynparse.Tex_Math_Program,
    table_descriptors: []dynparse.Tex_Table_Descriptor,
    document_blocks: []dynparse.Tex_Document_Block,
    document_inlines: []dynparse.Tex_Document_Inline,
    document_display_rows: []dynparse.Tex_Document_Display_Row,
    root_program: int,
    plain_text: dynparse.Tex_Text_Span,
    parse_status: dynparse.Tex_Parse_Status,
    error_offset: int,
    recoverable: bool,
}

// Identify one exact source interpretation within a parser revision and profile.
Dynview_Document_Key :: struct {
    source_hash: u64,
    source_length: u32,
    grammar_revision: u32,
    semantic_profile: u32,
    parse_mode: dynparse.Tex_Source_Mode,
    root_style: dynparse.Tex_Math_Root_Style,
}

// Describe checked offsets for one immutable aligned document blob.
Dynview_Document_Blob_Layout :: struct {
    text_offset: int,
    ops_offset: int,
    programs_offset: int,
    tables_offset: int,
    blocks_offset: int,
    inlines_offset: int,
    display_rows_offset: int,
    byte_count: int,
}

// Describe one bounded open-addressed probe result.
Dynview_Document_Probe :: struct {
    index: int,
    found: bool,
}

// Retain validated inputs while one unpublished document is constructed.
Dynview_Document_Build :: struct {
    source: string,
    key: Dynview_Document_Key,
    parse_status: dynparse.Tex_Parse_Status,
    output: ^dynparse.Tex_Semantic_Output,
    layout: Dynview_Document_Blob_Layout,
}

//   Intern one source under the production grammar and semantic profile.
document_store_intern :: proc(
    store: ^app_core.Dynview_Document_Store,
    source: string,
    parse_mode: dynparse.Tex_Source_Mode,
    root_style: dynparse.Tex_Math_Root_Style) -> (
        app_core.Dynview_Document_Handle, Dynview_Document_Status) {
    key := document_store_key(source, DYNVIEW_DOCUMENT_SEMANTIC_PROFILE_DEFAULT,
        parse_mode, root_style, document_store_source_hash(source))
    return document_store_intern_keyed(store, source, key)
}

//   Intern one complete key, permitting deterministic collision and revision tests.
document_store_intern_keyed :: proc(
    store: ^app_core.Dynview_Document_Store,
    source: string,
    key: Dynview_Document_Key) -> (
        app_core.Dynview_Document_Handle, Dynview_Document_Status) {
    if store == nil || !store.initialized || store.memory == nil ||
        store.generation == 0 || store.memory.generation != store.generation {
        return {}, .Illegal_State
    }
    if key.source_length != u32(len(source)) || key.grammar_revision == 0 ||
        key.semantic_profile == 0 {
        return {}, .Invalid_Argument
    }
    probe := document_store_probe(store, source, key)
    if probe.found {
        return document_store_hit(store, probe.index)
    }
    if probe.index < 0 {
        store.quota_rejections += 1
        return {}, .Out_Of_Capacity
    }
    output := new(dynparse.Tex_Semantic_Output, context.temp_allocator)
    if output == nil {
        store.allocation_failures += 1
        return {}, .Allocation_Failed
    }
    defer free(output, context.temp_allocator)
    parse_status := document_store_parse(
        source, key.parse_mode, key.root_style, output)
    build := Dynview_Document_Build{
        source = source,
        key = key,
        parse_status = parse_status,
        output = output,
    }
    return document_store_insert(store, probe.index, &build)
}

//   Resolve one current-generation handle without following stale storage.
document_store_resolve :: proc(
    store: ^app_core.Dynview_Document_Store,
    handle: app_core.Dynview_Document_Handle) -> (
        Dynview_Document, Dynview_Document_Status) {
    if store == nil || !store.initialized || store.generation == 0 ||
        handle.generation != store.generation {
        return {}, .Illegal_State
    }
    index := int(handle.index)
    if index < 0 || index >= len(store.entries) ||
        !store.entries[index].occupied {
        return {}, .Not_Found
    }
    entry := &store.entries[index]
    bytes := document_store_blob_bytes(entry)
    document := Dynview_Document{
        source = string(bytes[:int(entry.source_length)]),
        root_program = entry.root_program,
        plain_text = {entry.plain_text_offset, entry.plain_text_length},
        parse_status = dynparse.Tex_Parse_Status(entry.parse_status),
        error_offset = entry.error_offset,
        recoverable = entry.recoverable,
    }
    document_store_resolve_semantics(&document, entry, bytes)
    status: Dynview_Document_Status =
        .Ok if document.parse_status == .Ok else .Rejected
    return document, status
}

//   Snapshot logical store use and backing animation-memory pressure.
document_store_diagnostics :: proc(
    store: ^app_core.Dynview_Document_Store) ->
        app_core.Dynview_Document_Store_Diagnostics {
    if store == nil {
        return {}
    }
    arena := app_core.Arena_Owner_Diagnostics{}
    if store.memory != nil {
        arena = app_core.animation_memory_diagnostics(store.memory)
    }
    return {
        initialized = store.initialized,
        generation = store.generation,
        entry_count = store.entry_count,
        blob_bytes = store.blob_bytes,
        peak_entry_count = store.peak_entry_count,
        peak_blob_bytes = store.peak_blob_bytes,
        intern_hits = store.intern_hits,
        negative_cache_hits = store.negative_cache_hits,
        collision_count = store.collision_count,
        quota_rejections = store.quota_rejections,
        allocation_failures = store.allocation_failures,
        generation_resets = store.generation_resets,
        arena = arena,
    }
}

//   Return checked text from one resolved immutable semantic span.
document_store_text :: proc(
    document: ^Dynview_Document,
    span: dynparse.Tex_Text_Span) -> string {
    if document == nil || span.offset < 0 || span.length < 0 ||
        span.offset > len(document.text)-span.length {
        return ""
    }
    return string(document.text[span.offset:span.offset + span.length])
}

//   Hash exact source bytes deterministically with FNV-1a.
document_store_source_hash :: proc(source: string) -> u64 {
    hash := DYNVIEW_DOCUMENT_HASH_OFFSET
    for value in transmute([]u8)source {
        hash = (hash ~ u64(value))*DYNVIEW_DOCUMENT_HASH_PRIME
    }
    return hash
}

//   Build one complete immutable parse key from caller-owned identity fields.
document_store_key :: proc(
    source: string,
    semantic_profile: u32,
    parse_mode: dynparse.Tex_Source_Mode,
    root_style: dynparse.Tex_Math_Root_Style,
    source_hash: u64) -> Dynview_Document_Key {
    return {
        source_hash = source_hash,
        source_length = u32(len(source)),
        grammar_revision = DYNVIEW_DOCUMENT_GRAMMAR_REVISION,
        semantic_profile = semantic_profile,
        parse_mode = parse_mode,
        root_style = root_style,
    }
}

//   Probe the bounded index, comparing complete keys and exact source bytes.
document_store_probe :: proc(
    store: ^app_core.Dynview_Document_Store,
    source: string,
    key: Dynview_Document_Key) -> Dynview_Document_Probe {
    start := int(key.source_hash % u64(len(store.entries)))
    for attempt in 0..<len(store.entries) {
        index := (start + attempt)%len(store.entries)
        entry := &store.entries[index]
        if !entry.occupied {
            return {index = index}
        }
        if document_store_entry_matches(entry, source, key) {
            return {index = index, found = true}
        }
        store.collision_count += 1
    }
    return {index = -1}
}

//   Compare one complete parse key, including exact retained source bytes.
document_store_entry_matches :: proc(
    entry: ^app_core.Dynview_Document_Entry,
    source: string,
    key: Dynview_Document_Key) -> bool {
    if entry.source_hash != key.source_hash ||
        entry.source_length != key.source_length ||
        entry.grammar_revision != key.grammar_revision ||
        entry.semantic_profile != key.semantic_profile ||
        entry.parse_mode != u8(key.parse_mode) ||
        entry.root_style != u8(key.root_style) {
        return false
    }
    bytes := document_store_blob_bytes(entry)
    return mem.compare(bytes[:len(source)], transmute([]u8)source) == 0
}

//   Return a stable handle and cached outcome for one exact intern hit.
document_store_hit :: proc(
    store: ^app_core.Dynview_Document_Store,
    index: int) -> (app_core.Dynview_Document_Handle, Dynview_Document_Status) {
    store.intern_hits += 1
    entry := &store.entries[index]
    status := Dynview_Document_Status.Ok
    if dynparse.Tex_Parse_Status(entry.parse_status) != .Ok {
        store.negative_cache_hits += 1
        status = .Rejected
    }
    return {generation = store.generation, index = u32(index)}, status
}

//   Dispatch one source through the selected bounded native grammar.
document_store_parse :: proc(
    source: string,
    parse_mode: dynparse.Tex_Source_Mode,
    root_style: dynparse.Tex_Math_Root_Style,
    output: ^dynparse.Tex_Semantic_Output) -> dynparse.Tex_Parse_Status {
    switch parse_mode {
    case .Math:
        return dynparse.tex_parse_math(source, root_style, output)
    case .Document:
        return dynparse.tex_parse_document(source, output)
    }
    return .Unexpected_Token
}

//   Build checked aligned offsets for the exact successful semantic prefixes.
document_store_blob_layout :: proc(
    source_length: int,
    output: ^dynparse.Tex_Semantic_Output) -> Dynview_Document_Blob_Layout {
    layout: Dynview_Document_Blob_Layout
    offset := source_length
    layout.text_offset = offset
    offset += output.text_count
    offset = document_store_align(offset, align_of(dynparse.Tex_Math_Op))
    layout.ops_offset = offset
    offset += output.op_count*size_of(dynparse.Tex_Math_Op)
    offset = document_store_align(offset, align_of(dynparse.Tex_Math_Program))
    layout.programs_offset = offset
    offset += output.program_count*size_of(dynparse.Tex_Math_Program)
    offset = document_store_align(offset, align_of(dynparse.Tex_Table_Descriptor))
    layout.tables_offset = offset
    offset += output.table_descriptor_count*size_of(dynparse.Tex_Table_Descriptor)
    offset = document_store_align(offset, align_of(dynparse.Tex_Document_Block))
    layout.blocks_offset = offset
    offset += output.document_block_count*size_of(dynparse.Tex_Document_Block)
    offset = document_store_align(offset, align_of(dynparse.Tex_Document_Inline))
    layout.inlines_offset = offset
    offset += output.document_inline_count*size_of(dynparse.Tex_Document_Inline)
    offset = document_store_align(
        offset, align_of(dynparse.Tex_Document_Display_Row))
    layout.display_rows_offset = offset
    layout.byte_count = offset + output.document_display_row_count*
        size_of(dynparse.Tex_Document_Display_Row)
    return layout
}

//   Round one byte offset up to a power-of-two type alignment.
document_store_align :: #force_inline proc(offset, alignment: int) -> int {
    return (offset + alignment - 1) & ~(alignment - 1)
}

//   Allocate, populate, and then publish one immutable index entry.
document_store_insert :: proc(
    store: ^app_core.Dynview_Document_Store,
    index: int,
    build: ^Dynview_Document_Build) -> (
        app_core.Dynview_Document_Handle, Dynview_Document_Status) {
    build.layout = {byte_count = len(build.source)}
    if build.parse_status == .Ok {
        build.layout = document_store_blob_layout(len(build.source), build.output)
    }
    blob, allocation_status := document_store_allocate_blob(
        store, build.layout.byte_count)
    if allocation_status != .Ok {
        return {}, allocation_status
    }
    entry := document_store_build_entry(build, blob)
    store.entries[index] = entry
    store.entry_count += 1
    store.blob_bytes += build.layout.byte_count
    store.peak_entry_count = max(store.peak_entry_count, store.entry_count)
    store.peak_blob_bytes = max(store.peak_blob_bytes, store.blob_bytes)
    handle := app_core.Dynview_Document_Handle{
        generation = store.generation,
        index = u32(index),
    }
    status: Dynview_Document_Status =
        .Ok if build.parse_status == .Ok else .Rejected
    return handle, status
}

//   Allocate one aligned arena blob after enforcing the independent byte quota.
document_store_allocate_blob :: proc(
    store: ^app_core.Dynview_Document_Store,
    byte_count: int) -> ([]u64, Dynview_Document_Status) {
    if byte_count > store.byte_quota-store.blob_bytes {
        store.quota_rejections += 1
        return nil, .Out_Of_Capacity
    }
    word_count := max(1, (byte_count + size_of(u64) - 1)/size_of(u64))
    blob, allocation_error := make([]u64, word_count, store.allocator)
    if allocation_error != nil {
        store.allocation_failures += 1
        return nil, .Allocation_Failed
    }
    return blob, .Ok
}

//   Populate one unpublished entry and its single arena-owned blob.
document_store_build_entry :: proc(
    build: ^Dynview_Document_Build,
    blob: []u64) -> app_core.Dynview_Document_Entry {
    entry := app_core.Dynview_Document_Entry{
        source_hash = build.key.source_hash,
        source_length = build.key.source_length,
        grammar_revision = build.key.grammar_revision,
        semantic_profile = build.key.semantic_profile,
        parse_mode = u8(build.key.parse_mode),
        root_style = u8(build.key.root_style),
        parse_status = i32(build.parse_status),
        blob = blob,
        blob_byte_count = build.layout.byte_count,
        occupied = true,
    }
    bytes := document_store_blob_bytes(&entry)
    copy(bytes[:len(build.source)], transmute([]u8)build.source)
    if build.parse_status == .Ok {
        document_store_copy_semantics(
            &entry, bytes, build.output, build.layout)
    } else {
        entry.error_offset = build.output.error_offset
    }
    return entry
}

//   Copy exact semantic prefixes into aligned regions of one unpublished blob.
document_store_copy_semantics :: proc(
    entry: ^app_core.Dynview_Document_Entry,
    bytes: []u8,
    output: ^dynparse.Tex_Semantic_Output,
    layout: Dynview_Document_Blob_Layout) {
    entry.text_offset, entry.text_count = layout.text_offset, output.text_count
    entry.ops_offset, entry.op_count = layout.ops_offset, output.op_count
    entry.programs_offset = layout.programs_offset
    entry.program_count = output.program_count
    entry.tables_offset = layout.tables_offset
    entry.table_count = output.table_descriptor_count
    entry.blocks_offset = layout.blocks_offset
    entry.block_count = output.document_block_count
    entry.inlines_offset = layout.inlines_offset
    entry.inline_count = output.document_inline_count
    entry.display_rows_offset = layout.display_rows_offset
    entry.display_row_count = output.document_display_row_count
    entry.root_program = output.root_program
    entry.plain_text_offset = output.plain_text.offset
    entry.plain_text_length = output.plain_text.length
    entry.error_offset, entry.recoverable = output.error_offset, output.recoverable
    copy(bytes[layout.text_offset:], output.text[:output.text_count])
    copy(document_store_typed_slice(
        dynparse.Tex_Math_Op, bytes, layout.ops_offset, output.op_count),
        output.ops[:output.op_count])
    copy(document_store_typed_slice(dynparse.Tex_Math_Program,
        bytes, layout.programs_offset, output.program_count),
        output.programs[:output.program_count])
    copy(document_store_typed_slice(dynparse.Tex_Table_Descriptor,
        bytes, layout.tables_offset, output.table_descriptor_count),
        output.table_descriptors[:output.table_descriptor_count])
    document_store_copy_document_semantics(entry, bytes, output, layout)
}

//   Copy structured document records into their aligned blob regions.
document_store_copy_document_semantics :: proc(
    entry: ^app_core.Dynview_Document_Entry,
    bytes: []u8,
    output: ^dynparse.Tex_Semantic_Output,
    layout: Dynview_Document_Blob_Layout) {
    copy(document_store_typed_slice(dynparse.Tex_Document_Block,
        bytes, layout.blocks_offset, output.document_block_count),
        output.document_blocks[:output.document_block_count])
    copy(document_store_typed_slice(dynparse.Tex_Document_Inline,
        bytes, layout.inlines_offset, output.document_inline_count),
        output.document_inlines[:output.document_inline_count])
    copy(document_store_typed_slice(dynparse.Tex_Document_Display_Row,
        bytes, layout.display_rows_offset, output.document_display_row_count),
        output.document_display_rows[:output.document_display_row_count])
}

//   Resolve aligned semantic prefixes from one validated immutable blob.
document_store_resolve_semantics :: proc(
    document: ^Dynview_Document,
    entry: ^app_core.Dynview_Document_Entry,
    bytes: []u8) {
    if document.parse_status != .Ok {
        return
    }
    document.text = bytes[entry.text_offset:entry.text_offset + entry.text_count]
    document.ops = document_store_typed_slice(
        dynparse.Tex_Math_Op, bytes, entry.ops_offset, entry.op_count)
    document.programs = document_store_typed_slice(dynparse.Tex_Math_Program,
        bytes, entry.programs_offset, entry.program_count)
    document.table_descriptors = document_store_typed_slice(
        dynparse.Tex_Table_Descriptor, bytes, entry.tables_offset, entry.table_count)
    document.document_blocks = document_store_typed_slice(
        dynparse.Tex_Document_Block, bytes, entry.blocks_offset, entry.block_count)
    document.document_inlines = document_store_typed_slice(
        dynparse.Tex_Document_Inline, bytes, entry.inlines_offset, entry.inline_count)
    document.document_display_rows = document_store_typed_slice(
        dynparse.Tex_Document_Display_Row, bytes,
        entry.display_rows_offset, entry.display_row_count)
}

//   View one typed aligned prefix inside immutable byte storage.
document_store_typed_slice :: proc($T: typeid, bytes: []u8,
    offset, count: int) -> []T {
    if count == 0 {
        return nil
    }
    return (cast([^]T)raw_data(bytes[offset:]))[:count]
}

//   View the logical byte prefix of one arena-owned aligned allocation.
document_store_blob_bytes :: proc(
    entry: ^app_core.Dynview_Document_Entry) -> []u8 {
    if entry == nil || len(entry.blob) == 0 {
        return nil
    }
    return (cast([^]u8)raw_data(entry.blob))[:entry.blob_byte_count]
}