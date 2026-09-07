package core

import "core:mem"
import "base:runtime"

ANIMATION_MEMORY_ARENA_RESERVATION :: uint(mem.Megabyte)
DYNVIEW_DOCUMENT_ENTRY_CAPACITY :: 256
DYNVIEW_DOCUMENT_TOTAL_BLOB_BYTES :: 16*int(mem.Megabyte)

// Report shared animation-memory lifecycle outcomes.
Animation_Memory_Status :: enum {
    Ok,
    Invalid_Argument,
    Illegal_State,
    Allocation_Failed,
}

// Own generation-scoped storage shared by native animation subsystems.
Animation_Memory :: struct {
    arena_owner: Arena_Owner,
    generation: u64,
    initialized: bool,
}

// Identify one owner-local immutable document within an animation generation.
Dynview_Document_Handle :: struct {
    generation: u64,
    index: u32,
}

// Retain one type-neutral immutable document index entry in shared core state.
Dynview_Document_Entry :: struct {
    source_hash: u64,
    source_length: u32,
    grammar_revision: u32,
    semantic_profile: u32,
    parse_mode: u8,
    root_style: u8,
    parse_status: i32,
    blob: []u64,
    blob_byte_count: int,
    text_offset: int,
    text_count: int,
    ops_offset: int,
    op_count: int,
    programs_offset: int,
    program_count: int,
    tables_offset: int,
    table_count: int,
    blocks_offset: int,
    block_count: int,
    inlines_offset: int,
    inline_count: int,
    display_rows_offset: int,
    display_row_count: int,
    root_program: int,
    plain_text_offset: int,
    plain_text_length: int,
    error_offset: int,
    recoverable: bool,
    occupied: bool,
}

// Report bounded document-store use and generation-local cache behavior.
Dynview_Document_Store_Diagnostics :: struct {
    initialized: bool,
    generation: u64,
    entry_count: int,
    blob_bytes: int,
    peak_entry_count: int,
    peak_blob_bytes: int,
    intern_hits: u64,
    negative_cache_hits: u64,
    collision_count: u64,
    quota_rejections: u64,
    allocation_failures: u64,
    generation_resets: u64,
    arena: Arena_Owner_Diagnostics,
}

// Retain POD lifecycle and index state for the native document store.
Dynview_Document_Store :: struct {
    memory: ^Animation_Memory,
    allocator: runtime.Allocator,
    entries: [DYNVIEW_DOCUMENT_ENTRY_CAPACITY]Dynview_Document_Entry,
    generation: u64,
    entry_count: int,
    blob_bytes: int,
    byte_quota: int,
    peak_entry_count: int,
    peak_blob_bytes: int,
    intern_hits: u64,
    negative_cache_hits: u64,
    collision_count: u64,
    quota_rejections: u64,
    allocation_failures: u64,
    generation_resets: u64,
    initialized: bool,
}

//   Initialize shared animation storage without publishing partial state.
animation_memory_init :: proc(memory: ^Animation_Memory) -> bool {
    if memory == nil || memory.initialized {
        return false
    }
    memory^ = {}
    if !arena_owner_init(
        &memory.arena_owner, ANIMATION_MEMORY_ARENA_RESERVATION) {
        return false
    }
    memory.initialized = true
    return true
}

//   Publish the allocator borrowed by generation-scoped animation stores.
animation_memory_allocator :: proc(
    memory: ^Animation_Memory) -> runtime.Allocator {
    if memory == nil || !memory.initialized {
        return {}
    }
    return arena_owner_allocator(&memory.arena_owner)
}

//   Retire shared allocations and publish one nonzero animation generation.
animation_memory_begin_generation :: proc(
    memory: ^Animation_Memory,
    generation: u64) -> Animation_Memory_Status {
    if memory == nil || !memory.initialized {
        return .Illegal_State
    }
    if generation == 0 {
        return .Invalid_Argument
    }
    arena_owner_reset(&memory.arena_owner)
    memory.generation = generation
    return .Ok
}

//   Release shared animation storage after all borrowers are quiescent.
animation_memory_destroy :: proc(memory: ^Animation_Memory) {
    if memory == nil || !memory.initialized {
        return
    }
    arena_owner_destroy(&memory.arena_owner)
    memory.generation = 0
    memory.initialized = false
}

//   Snapshot the production animation arena without exposing mutable storage.
animation_memory_diagnostics :: proc(
    memory: ^Animation_Memory) -> Arena_Owner_Diagnostics {
    if memory == nil {
        return {}
    }
    return arena_owner_diagnostics(&memory.arena_owner)
}

//   Bind the document-store state to initialized shared animation memory.
dynview_document_store_init :: proc(
    store: ^Dynview_Document_Store,
    memory: ^Animation_Memory) -> bool {
    if store == nil || store.initialized || memory == nil || !memory.initialized {
        return false
    }
    store^ = {
        memory = memory,
        allocator = animation_memory_allocator(memory),
        byte_quota = DYNVIEW_DOCUMENT_TOTAL_BLOB_BYTES,
        initialized = true,
    }
    return store.allocator != (runtime.Allocator{})
}

//   Clear generation identity before the owner retires shared allocations.
dynview_document_store_clear_generation :: proc(
    store: ^Dynview_Document_Store) {
    if store == nil || !store.initialized {
        return
    }
    for index in 0..<len(store.entries) {
        store.entries[index] = {}
    }
    store.generation = 0
    store.entry_count = 0
    store.blob_bytes = 0
}

//   Publish one owner-validated generation to the document-store state.
dynview_document_store_publish_generation :: proc(
    store: ^Dynview_Document_Store,
    memory: ^Animation_Memory,
    generation: u64) {
    if store == nil || memory == nil || !store.initialized ||
        store.memory != memory || memory.generation != generation {
        return
    }
    store.generation = generation
    store.generation_resets += 1
}

//   Detach document-store state without changing shared animation memory.
dynview_document_store_destroy :: proc(store: ^Dynview_Document_Store) {
    if store == nil || !store.initialized {
        return
    }
    dynview_document_store_clear_generation(store)
    store.memory = nil
    store.allocator = {}
    store.byte_quota = 0
    store.initialized = false
}

//   Initialize the shared owner and every generation-scoped borrower.
animation_storage_init :: proc(
    memory: ^Animation_Memory,
    values: ^Animation_Value_Store,
    documents: ^Dynview_Document_Store) -> bool {
    if !animation_memory_init(memory) {
        return false
    }
    if !animation_value_store_init(values, memory) {
        animation_memory_destroy(memory)
        return false
    }
    if !dynview_document_store_init(documents, memory) {
        animation_value_store_destroy(values)
        animation_memory_destroy(memory)
        return false
    }
    return true
}

//   Clear borrowers, reset shared memory once, then publish one generation.
animation_storage_begin_generation :: proc(
    memory: ^Animation_Memory,
    values: ^Animation_Value_Store,
    documents: ^Dynview_Document_Store,
    generation: u64) -> Animation_Memory_Status {
    if memory == nil || values == nil || documents == nil ||
        !memory.initialized || !values.initialized || !documents.initialized ||
        values.memory != memory {
        return .Illegal_State
    }
    if generation == 0 {
        return .Invalid_Argument
    }
    animation_value_store_clear_generation(values)
    dynview_document_store_clear_generation(documents)
    status := animation_memory_begin_generation(memory, generation)
    if status != .Ok {
        return status
    }
    animation_value_store_publish_generation(values, generation)
    dynview_document_store_publish_generation(documents, memory, generation)
    return .Ok
}

//   Detach all borrowers before destroying their shared animation memory.
animation_storage_destroy :: proc(
    memory: ^Animation_Memory,
    values: ^Animation_Value_Store,
    documents: ^Dynview_Document_Store) {
    animation_value_store_destroy(values)
    dynview_document_store_destroy(documents)
    animation_memory_destroy(memory)
}