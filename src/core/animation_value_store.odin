package core

import "base:runtime"
import "core:mem"

ANIMATION_VALUE_ENTRY_CAPACITY :: 256
ANIMATION_VALUE_MAX_PAYLOAD_BYTES :: 16*int(mem.Kilobyte)
ANIMATION_VALUE_TOTAL_PAYLOAD_BYTES :: 64*int(mem.Kilobyte)
ANIMATION_VALUE_PENDING_WRITE_CAPACITY :: SCENE_COMMAND_BATCH_CAPACITY
ANIMATION_VALUE_RESERVED_KEY :: u64(0)

// Report canonical animation-value operation outcomes without bridge coupling.
Animation_Value_Status :: enum {
    Ok,
    Invalid_Argument,
    Illegal_State,
    Not_Found,
    Schema_Mismatch,
    Out_Of_Capacity,
    Allocation_Failed,
}

// Identify one schema-bound key in one authoritative animation generation.
Animation_Value_Identity :: struct {
    generation : u64,
    key : u64,
    schema_low : u64,
    schema_high : u64,
}

// Locate one opaque value inside slot-owned packed byte storage.
Animation_Value_Packed_Entry :: struct {
    key : u64,
    schema_low : u64,
    schema_high : u64,
    payload_offset : i32,
    payload_size : i32,
}

// Own one immutable pointer-free canonical value snapshot for a worker tick.
Animation_Value_Snapshot :: struct {
    entry_count : int,
    payload_size : int,
    entries : [ANIMATION_VALUE_ENTRY_CAPACITY]Animation_Value_Packed_Entry,
    payload : [ANIMATION_VALUE_TOTAL_PAYLOAD_BYTES]u8,
}

// Own ordered pointer-free writes staged by one worker tick.
Animation_Value_Pending_Writes :: struct {
    write_count : int,
    payload_size : int,
    invalid : bool,
    entries : [ANIMATION_VALUE_PENDING_WRITE_CAPACITY]Animation_Value_Packed_Entry,
    payload : [ANIMATION_VALUE_TOTAL_PAYLOAD_BYTES]u8,
}

// Bind one nonzero key to an opaque schema and arena-owned payload.
Animation_Value_Entry :: struct {
    // Stable identity for one animation generation.
    key : u64,
    schema_low : u64,
    schema_high : u64,

    // Arena-owned payload storage, allocated exactly once per key.
    payload : []u8,
    occupied : bool,
}

// Report logical quotas and backing arena pressure for one store lifetime.
Animation_Value_Store_Diagnostics :: struct {
    // Availability and current animation generation identity.
    initialized : bool,
    generation : u64,

    // Current and lifetime-high FFI-controlled logical usage.
    entry_count : int,
    payload_bytes : int,
    peak_entry_count : int,
    peak_payload_bytes : int,

    // Rejections and bulk lifecycle transitions.
    quota_rejections : u64,
    schema_rejections : u64,
    allocation_failures : u64,
    generation_resets : u64,

    // Current and lifetime backing-arena usage.
    arena : Arena_Owner_Diagnostics,
}

// Index canonical opaque values allocated from shared animation memory.
Animation_Value_Store :: struct {
    // Borrowed storage and fixed deterministic key index.
    memory : ^Animation_Memory,
    allocator : runtime.Allocator,
    entries : [ANIMATION_VALUE_ENTRY_CAPACITY]Animation_Value_Entry,

    // Current generation identity and logical FFI quota usage.
    generation : u64,
    entry_count : int,
    payload_bytes : int,

    // Lifetime diagnostics retained across generation resets.
    peak_entry_count : int,
    peak_payload_bytes : int,
    quota_rejections : u64,
    schema_rejections : u64,
    allocation_failures : u64,
    generation_resets : u64,
    initialized : bool,
}

//   Initialize one canonical animation store over shared animation memory.
//
// Parameters:
//   - store: Zero or destroyed store state to initialize.
//   - memory: Initialized owner that outlives the store.
//
// Returns:
//   - True after binding borrowed storage; false without live publication.
animation_value_store_init :: proc(
    store: ^Animation_Value_Store,
    memory: ^Animation_Memory) -> bool {
    if store == nil || store.initialized || memory == nil || !memory.initialized {
        return false
    }
    store^ = {}
    allocator := animation_memory_allocator(memory)
    if allocator == (runtime.Allocator{}) {
        return false
    }
    store.memory = memory
    store.allocator = allocator
    store.initialized = true
    return true
}

//   Retire all values and begin one new animation generation.
//
// Parameters:
//   - store: Initialized canonical store to clear.
//   - generation: Nonzero identity of the generation about to initiate.
//
// Returns:
//   - `Ok` after bulk retirement, or a rejection without mutation.
//
// Notes:
//   - The owner must reset shared memory before publishing this generation.
animation_value_store_begin_generation :: proc(
    store: ^Animation_Value_Store,
    generation: u64) -> Animation_Value_Status {
    if store == nil || !store.initialized || store.memory == nil ||
        store.memory.generation != generation {
        return .Illegal_State
    }
    if generation == 0 {
        return .Invalid_Argument
    }
    animation_value_store_clear_generation(store)
    animation_value_store_publish_generation(store, generation)
    return .Ok
}

//   Clear the fixed value index before shared animation memory is reset.
animation_value_store_clear_generation :: proc(store: ^Animation_Value_Store) {
    if store == nil || !store.initialized {
        return
    }
    for index in 0..<store.entry_count {
        store.entries[index] = {}
    }
    store.generation = 0
    store.entry_count = 0
    store.payload_bytes = 0
}

//   Publish one generation already established by the shared memory owner.
animation_value_store_publish_generation :: proc(
    store: ^Animation_Value_Store,
    generation: u64) {
    if store == nil || !store.initialized || store.memory == nil ||
        store.memory.generation != generation {
        return
    }
    store.generation = generation
    store.generation_resets += 1
}

//   Set one schema-bound opaque value in the current generation.
//
// Parameters:
//   - store: Initialized canonical destination.
//   - identity: Generation, nonzero key, and deterministic schema identity.
//   - payload: Nonempty copied bytes within the per-value quota.
//
// Returns:
//   - Explicit status; every rejection leaves canonical state unchanged.
animation_value_store_set :: proc(
    store: ^Animation_Value_Store,
    identity: Animation_Value_Identity,
    payload: []u8) -> Animation_Value_Status {
    status := animation_value_store_validate_request(
        store, identity, len(payload))
    if status != .Ok {
        return status
    }
    entry := animation_value_store_find(store, identity.key)
    if entry != nil {
        if !animation_value_entry_schema_matches(
            entry, identity.schema_low, identity.schema_high, len(payload)) {
            store.schema_rejections += 1
            return .Schema_Mismatch
        }
        copy(entry.payload, payload)
        return .Ok
    }
    return animation_value_store_insert(
        store, identity.key, identity.schema_low, identity.schema_high, payload)
}

//   Copy one canonical value into caller-owned storage.
//
// Parameters:
//   - store: Initialized canonical source.
//   - identity: Exact generation, key, and schema identity.
//   - destination: Caller-owned storage with the exact bound byte count.
//
// Returns:
//   - Explicit status; destination changes only on success.
animation_value_store_copy :: proc(
    store: ^Animation_Value_Store,
    identity: Animation_Value_Identity,
    destination: []u8) -> Animation_Value_Status {
    status := animation_value_store_validate_request(
        store, identity, len(destination))
    if status != .Ok {
        return status
    }
    entry := animation_value_store_find(store, identity.key)
    if entry == nil {
        return .Not_Found
    }
    if !animation_value_entry_schema_matches(
        entry, identity.schema_low, identity.schema_high, len(destination)) {
        store.schema_rejections += 1
        return .Schema_Mismatch
    }
    copy(destination, entry.payload)
    return .Ok
}

//   Pack canonical values into one immutable pointer-free tick snapshot.
//
// Parameters:
//   - store: Initialized canonical source.
//   - generation: Required current animation generation.
//   - snapshot: Slot-owned destination replaced only on success.
//
// Returns:
//   - Explicit status; canonical quotas guarantee destination capacity.
animation_value_store_pack :: proc(
    store: ^Animation_Value_Store,
    generation: u64,
    snapshot: ^Animation_Value_Snapshot) -> Animation_Value_Status {
    if store == nil || snapshot == nil || !store.initialized ||
        store.generation != generation {
        return .Illegal_State
    }
    packed: Animation_Value_Snapshot
    for index in 0..<store.entry_count {
        entry := &store.entries[index]
        payload_end := packed.payload_size + len(entry.payload)
        packed.entries[index] = {
            key = entry.key,
            schema_low = entry.schema_low,
            schema_high = entry.schema_high,
            payload_offset = i32(packed.payload_size),
            payload_size = i32(len(entry.payload)),
        }
        copy(packed.payload[packed.payload_size:payload_end], entry.payload)
        packed.payload_size = payload_end
        packed.entry_count += 1
    }
    snapshot^ = packed
    return .Ok
}

//   Append one complete copied write to a bounded tick-local pending buffer.
//
// Returns:
//   - Explicit status; capacity or malformed writes poison the complete batch.
animation_value_pending_append :: proc(
    pending: ^Animation_Value_Pending_Writes,
    identity: Animation_Value_Identity,
    payload: []u8) -> Animation_Value_Status {
    if pending == nil || pending.invalid {
        return .Illegal_State
    }
    if identity.key == ANIMATION_VALUE_RESERVED_KEY ||
        identity.schema_low == 0 && identity.schema_high == 0 ||
        len(payload) <= 0 || len(payload) > ANIMATION_VALUE_MAX_PAYLOAD_BYTES {
        pending.invalid = true
        return .Invalid_Argument
    }
    if pending.write_count >= len(pending.entries) ||
        len(payload) > len(pending.payload)-pending.payload_size {
        pending.invalid = true
        return .Out_Of_Capacity
    }
    if !animation_value_pending_schema_matches(pending, identity, len(payload)) {
        pending.invalid = true
        return .Schema_Mismatch
    }
    payload_end := pending.payload_size + len(payload)
    copy(pending.payload[pending.payload_size:payload_end], payload)
    pending.entries[pending.write_count] = {
        key = identity.key,
        schema_low = identity.schema_low,
        schema_high = identity.schema_high,
        payload_offset = i32(pending.payload_size),
        payload_size = i32(len(payload)),
    }
    pending.payload_size = payload_end
    pending.write_count += 1
    return .Ok
}

//   Report whether a pending write agrees with the newest matching schema.
animation_value_pending_schema_matches :: proc(
    pending: ^Animation_Value_Pending_Writes,
    identity: Animation_Value_Identity,
    payload_size: int) -> bool {
    prior := animation_value_packed_find_newest(
        pending.entries[:pending.write_count], identity.key)
    return prior == nil || animation_value_packed_schema_matches(
        prior, identity.schema_low, identity.schema_high, payload_size)
}

//   Copy the newest matching pending write into caller-owned storage.
animation_value_pending_copy :: proc(
    pending: ^Animation_Value_Pending_Writes,
    identity: Animation_Value_Identity,
    destination: []u8) -> Animation_Value_Status {
    if pending == nil || pending.invalid {
        return .Illegal_State
    }
    entry := animation_value_packed_find_newest(
        pending.entries[:pending.write_count], identity.key)
    return animation_value_packed_copy(
        entry, pending.payload[:], identity, destination)
}

//   Copy one matching immutable snapshot value into caller-owned storage.
animation_value_snapshot_copy :: proc(
    snapshot: ^Animation_Value_Snapshot,
    identity: Animation_Value_Identity,
    destination: []u8) -> Animation_Value_Status {
    if snapshot == nil || snapshot.entry_count < 0 ||
        snapshot.entry_count > len(snapshot.entries) {
        return .Illegal_State
    }
    entry := animation_value_packed_find_newest(
        snapshot.entries[:snapshot.entry_count], identity.key)
    return animation_value_packed_copy(
        entry, snapshot.payload[:], identity, destination)
}

//   Validate all pending spans, bindings, and projected canonical quotas.
animation_value_store_validate_pending :: proc(
    store: ^Animation_Value_Store,
    generation: u64,
    pending: ^Animation_Value_Pending_Writes) -> Animation_Value_Status {
    if pending == nil || pending.invalid || pending.write_count < 0 ||
        pending.write_count > len(pending.entries) || pending.payload_size < 0 ||
        pending.payload_size > len(pending.payload) {
        return .Illegal_State
    }
    if pending.write_count == 0 {
        return .Ok
    }
    if store == nil || !store.initialized || store.generation != generation {
        return .Illegal_State
    }
    return animation_value_store_validate_projected_capacity(store, pending)
}

//   Validate descriptors and canonical quotas for a nonempty pending batch.
animation_value_store_validate_projected_capacity :: proc(
    store: ^Animation_Value_Store,
    pending: ^Animation_Value_Pending_Writes) -> Animation_Value_Status {
    projected_entries := store.entry_count
    projected_bytes := store.payload_bytes
    for index in 0..<pending.write_count {
        entry := &pending.entries[index]
        status := animation_value_pending_entry_status(pending, index)
        if status != .Ok {
            return status
        }
        if animation_value_packed_find_newest(pending.entries[:index], entry.key) != nil {
            continue
        }
        canonical := animation_value_store_find(store, entry.key)
        if canonical != nil {
            if !animation_value_entry_schema_matches(canonical, entry.schema_low,
                entry.schema_high, int(entry.payload_size)) {
                return .Schema_Mismatch
            }
            continue
        }
        projected_entries += 1
        projected_bytes += int(entry.payload_size)
    }
    if projected_entries > ANIMATION_VALUE_ENTRY_CAPACITY ||
        projected_bytes > ANIMATION_VALUE_TOTAL_PAYLOAD_BYTES {
        return .Out_Of_Capacity
    }
    return .Ok
}

//   Allocate canonical payload storage for one fully validated pending batch.
animation_value_pending_allocate_storage :: proc(
    store: ^Animation_Value_Store,
    pending: ^Animation_Value_Pending_Writes) -> ([]u8, Animation_Value_Status) {
    new_payload_bytes := animation_value_pending_new_payload_bytes(store, pending)
    if new_payload_bytes == 0 {
        return nil, .Ok
    }
    storage, allocation_error := make(
        []u8, new_payload_bytes, store.allocator)
    if allocation_error != nil {
        store.allocation_failures += 1
        return nil, .Allocation_Failed
    }
    return storage, .Ok
}

//   Commit validated writes into canonical entries using preallocated storage.
animation_value_store_commit_pending :: proc(
    store: ^Animation_Value_Store,
    pending: ^Animation_Value_Pending_Writes,
    new_storage: []u8) {
    storage_offset := 0
    for index in 0..<pending.write_count {
        packed := &pending.entries[index]
        entry := animation_value_store_find(store, packed.key)
        if entry == nil {
            size := int(packed.payload_size)
            entry = &store.entries[store.entry_count]
            entry^ = {
                key = packed.key,
                schema_low = packed.schema_low,
                schema_high = packed.schema_high,
                payload = new_storage[storage_offset:storage_offset+size],
                occupied = true,
            }
            storage_offset += size
            store.entry_count += 1
            store.payload_bytes += size
        }
        source := animation_value_packed_payload(packed, pending.payload[:])
        copy(entry.payload, source)
    }
}

//   Apply a fully validated pending batch without exposing partial allocation failure.
animation_value_store_apply_pending :: proc(
    store: ^Animation_Value_Store,
    generation: u64,
    pending: ^Animation_Value_Pending_Writes) -> Animation_Value_Status {
    status := animation_value_store_validate_pending(store, generation, pending)
    if status != .Ok || pending.write_count == 0 {
        return status
    }
    new_storage, allocation_status := animation_value_pending_allocate_storage(
        store, pending)
    if allocation_status != .Ok {
        return allocation_status
    }
    animation_value_store_commit_pending(store, pending, new_storage)
    store.peak_entry_count = max(store.peak_entry_count, store.entry_count)
    store.peak_payload_bytes = max(store.peak_payload_bytes, store.payload_bytes)
    return .Ok
}

//   Validate one pending descriptor and its agreement with earlier duplicate writes.
animation_value_pending_entry_status :: proc(
    pending: ^Animation_Value_Pending_Writes,
    index: int) -> Animation_Value_Status {
    entry := &pending.entries[index]
    if entry.key == ANIMATION_VALUE_RESERVED_KEY ||
        entry.schema_low == 0 && entry.schema_high == 0 ||
        int(entry.payload_size) <= 0 ||
        int(entry.payload_size) > ANIMATION_VALUE_MAX_PAYLOAD_BYTES ||
        !animation_value_packed_span_valid(
            entry, pending.payload_size) {
        return .Illegal_State
    }
    prior := animation_value_packed_find_newest(pending.entries[:index], entry.key)
    if prior != nil && !animation_value_packed_schema_matches(
        prior, entry.schema_low, entry.schema_high, int(entry.payload_size)) {
        return .Schema_Mismatch
    }
    return .Ok
}

//   Count storage required by keys absent from the canonical store.
animation_value_pending_new_payload_bytes :: proc(
    store: ^Animation_Value_Store,
    pending: ^Animation_Value_Pending_Writes) -> int {
    byte_count := 0
    for index in 0..<pending.write_count {
        entry := &pending.entries[index]
        if animation_value_store_find(store, entry.key) == nil &&
            animation_value_packed_find_newest(
                pending.entries[:index], entry.key) == nil {
            byte_count += int(entry.payload_size)
        }
    }
    return byte_count
}

//   Return one already-validated packed payload span.
animation_value_packed_payload :: proc(
    entry: ^Animation_Value_Packed_Entry,
    payload: []u8) -> []u8 {
    offset := int(entry.payload_offset)
    return payload[offset:offset+int(entry.payload_size)]
}

//   Return whether one descriptor span lies within the used payload prefix.
animation_value_packed_span_valid :: proc(
    entry: ^Animation_Value_Packed_Entry,
    payload_size: int) -> bool {
    offset := int(entry.payload_offset)
    size := int(entry.payload_size)
    return offset >= 0 && size > 0 && size <= payload_size &&
        offset <= payload_size-size
}

//   Return the newest descriptor for one key, or nil when absent.
animation_value_packed_find_newest :: proc(
    entries: []Animation_Value_Packed_Entry,
    key: u64) -> ^Animation_Value_Packed_Entry {
    index := len(entries)
    for index > 0 {
        index -= 1
        if entries[index].key == key {
            return &entries[index]
        }
    }
    return nil
}

//   Copy one validated packed span without exposing slot-owned pointers.
animation_value_packed_copy :: proc(
    entry: ^Animation_Value_Packed_Entry,
    payload: []u8,
    identity: Animation_Value_Identity,
    destination: []u8) -> Animation_Value_Status {
    if entry == nil {
        return .Not_Found
    }
    if !animation_value_packed_schema_matches(
        entry, identity.schema_low, identity.schema_high, len(destination)) {
        return .Schema_Mismatch
    }
    if !animation_value_packed_span_valid(entry, len(payload)) {
        return .Illegal_State
    }
    copy(destination, animation_value_packed_payload(entry, payload))
    return .Ok
}

//   Return whether one packed descriptor agrees on schema and exact size.
animation_value_packed_schema_matches :: proc(
    entry: ^Animation_Value_Packed_Entry,
    schema_low, schema_high: u64,
    payload_size: int) -> bool {
    return entry.schema_low == schema_low &&
        entry.schema_high == schema_high &&
        int(entry.payload_size) == payload_size
}

//   Detach one store after all readers have stopped.
//
// Side effects:
//   - Clears canonical metadata without resetting or destroying shared memory.
animation_value_store_destroy :: proc(store: ^Animation_Value_Store) {
    if store == nil || !store.initialized {
        return
    }
    for index in 0..<store.entry_count {
        store.entries[index] = {}
    }
    store.memory = nil
    store.allocator = {}
    store.generation = 0
    store.entry_count = 0
    store.payload_bytes = 0
    store.initialized = false
}

//   Snapshot logical and arena diagnostics without exposing mutable entries.
animation_value_store_diagnostics :: proc(
    store: ^Animation_Value_Store) -> Animation_Value_Store_Diagnostics {
    if store == nil {
        return {}
    }
    return {
        initialized = store.initialized,
        generation = store.generation,
        entry_count = store.entry_count,
        payload_bytes = store.payload_bytes,
        peak_entry_count = store.peak_entry_count,
        peak_payload_bytes = store.peak_payload_bytes,
        quota_rejections = store.quota_rejections,
        schema_rejections = store.schema_rejections,
        allocation_failures = store.allocation_failures,
        generation_resets = store.generation_resets,
        arena = animation_memory_diagnostics(store.memory),
    }
}

//   Reject malformed, stale, or oversized requests before mutation or allocation.
animation_value_store_validate_request :: proc(
    store: ^Animation_Value_Store,
    identity: Animation_Value_Identity,
    payload_size: int) -> Animation_Value_Status {
    if store == nil || !store.initialized ||
        store.generation != identity.generation {
        return .Illegal_State
    }
    if identity.key == ANIMATION_VALUE_RESERVED_KEY ||
        identity.schema_low == 0 && identity.schema_high == 0 ||
        payload_size <= 0 || payload_size > ANIMATION_VALUE_MAX_PAYLOAD_BYTES {
        return .Invalid_Argument
    }
    return .Ok
}

//   Return the occupied entry for a key, or nil when absent.
animation_value_store_find :: proc(
    store: ^Animation_Value_Store,
    key: u64) -> ^Animation_Value_Entry {
    for index in 0..<store.entry_count {
        if store.entries[index].occupied && store.entries[index].key == key {
            return &store.entries[index]
        }
    }
    return nil
}

//   Allocate and publish one new entry after all logical quotas pass.
animation_value_store_insert :: proc(
    store: ^Animation_Value_Store,
    key, schema_low, schema_high: u64,
    payload: []u8) -> Animation_Value_Status {
    if store.entry_count >= ANIMATION_VALUE_ENTRY_CAPACITY ||
        len(payload) > ANIMATION_VALUE_TOTAL_PAYLOAD_BYTES-store.payload_bytes {
        store.quota_rejections += 1
        return .Out_Of_Capacity
    }
    storage, allocation_error := make(
        []u8, len(payload), store.allocator)
    if allocation_error != nil {
        store.allocation_failures += 1
        return .Allocation_Failed
    }
    copy(storage, payload)
    store.entries[store.entry_count] = {
        key = key,
        schema_low = schema_low,
        schema_high = schema_high,
        payload = storage,
        occupied = true,
    }
    store.entry_count += 1
    store.payload_bytes += len(payload)
    store.peak_entry_count = max(store.peak_entry_count, store.entry_count)
    store.peak_payload_bytes = max(store.peak_payload_bytes, store.payload_bytes)
    return .Ok
}

//   Return whether an existing key agrees on schema and exact payload size.
animation_value_entry_schema_matches :: proc(
    entry: ^Animation_Value_Entry,
    schema_low, schema_high: u64,
    payload_size: int) -> bool {
    return entry.schema_low == schema_low &&
        entry.schema_high == schema_high &&
        len(entry.payload) == payload_size
}