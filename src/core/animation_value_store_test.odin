package core

import "core:mem"
import "core:testing"

//   Initialize one value store and its shared-memory owner for focused tests.
animation_value_store_test_init :: proc(
    memory: ^Animation_Memory,
    store: ^Animation_Value_Store,
    generation: u64) -> bool {
    return animation_memory_init(memory) &&
        animation_value_store_init(store, memory) &&
        animation_memory_begin_generation(memory, generation) == .Ok &&
        animation_value_store_begin_generation(store, generation) == .Ok
}

//   Destroy one focused value-store fixture in borrower-before-owner order.
animation_value_store_test_destroy :: proc(
    memory: ^Animation_Memory,
    store: ^Animation_Value_Store) {
    animation_value_store_destroy(store)
    animation_memory_destroy(memory)
}

//   Verify duplicate sets overwrite one bound entry without additional allocation.
@(test)
core_test_animation_value_store_overwrites_bound_key :: proc(t: ^testing.T) {
    memory: Animation_Memory
    store: Animation_Value_Store
    testing.expect(t, animation_value_store_test_init(&memory, &store, 1))
    defer animation_value_store_test_destroy(&memory, &store)
    testing.expect_value(t, animation_value_store_set(
        &store, {1, 7, 11, 12}, []u8{1, 2}), Animation_Value_Status.Ok)
    before := animation_value_store_diagnostics(&store)

    testing.expect_value(t, animation_value_store_set(
        &store, {1, 7, 11, 12}, []u8{3, 4}), Animation_Value_Status.Ok)
    after := animation_value_store_diagnostics(&store)
    testing.expect_value(t, after.entry_count, 1)
    testing.expect_value(t, after.arena.current_used, before.arena.current_used)
    destination: [2]u8
    testing.expect_value(t, animation_value_store_copy(
        &store, {1, 7, 11, 12}, destination[:]), Animation_Value_Status.Ok)
    testing.expect(t, mem.compare(destination[:], []u8{3, 4}) == 0)
}

//   Verify schema and size drift reject mutation of an existing binding.
@(test)
core_test_animation_value_store_rejects_schema_drift :: proc(t: ^testing.T) {
    memory: Animation_Memory
    store: Animation_Value_Store
    testing.expect(t, animation_value_store_test_init(&memory, &store, 3))
    defer animation_value_store_test_destroy(&memory, &store)
    _ = animation_value_store_set(&store, {3, 1, 5, 6}, []u8{9, 8})

    testing.expect_value(t, animation_value_store_set(
        &store, {3, 1, 5, 7}, []u8{1, 2}), Animation_Value_Status.Schema_Mismatch)
    testing.expect_value(t, animation_value_store_set(
        &store, {3, 1, 5, 6}, []u8{1}), Animation_Value_Status.Schema_Mismatch)
    destination: [2]u8
    testing.expect_value(t, animation_value_store_copy(
        &store, {3, 1, 5, 6}, destination[:]), Animation_Value_Status.Ok)
    testing.expect(t, mem.compare(destination[:], []u8{9, 8}) == 0)
}

//   Verify per-value and aggregate FFI quotas reject before canonical mutation.
@(test)
core_test_animation_value_store_rejects_quota_overflow :: proc(t: ^testing.T) {
    memory: Animation_Memory
    store: Animation_Value_Store
    testing.expect(t, animation_value_store_test_init(&memory, &store, 4))
    defer animation_value_store_test_destroy(&memory, &store)
    oversized: [ANIMATION_VALUE_MAX_PAYLOAD_BYTES + 1]u8
    testing.expect_value(t, animation_value_store_set(
        &store, {4, 1, 1, 1}, oversized[:]), Animation_Value_Status.Invalid_Argument)

    payload: [ANIMATION_VALUE_MAX_PAYLOAD_BYTES]u8
    for key in u64(1)..=u64(4) {
        testing.expect_value(t, animation_value_store_set(
            &store, {4, key, 1, key}, payload[:]), Animation_Value_Status.Ok)
    }
    testing.expect_value(t, animation_value_store_set(
        &store, {4, 5, 1, 5}, []u8{1}), Animation_Value_Status.Out_Of_Capacity)
    diagnostics := animation_value_store_diagnostics(&store)
    testing.expect_value(t, diagnostics.entry_count, 4)
    testing.expect_value(
        t, diagnostics.payload_bytes, ANIMATION_VALUE_TOTAL_PAYLOAD_BYTES)
}

//   Verify generation reset retires keys, reuses the first block, and keeps peaks.
@(test)
core_test_animation_value_store_resets_generation :: proc(t: ^testing.T) {
    memory: Animation_Memory
    store: Animation_Value_Store
    testing.expect(t, animation_value_store_test_init(&memory, &store, 8))
    defer animation_value_store_test_destroy(&memory, &store)
    _ = animation_value_store_set(&store, {8, 9, 2, 3}, []u8{4, 5, 6})
    before := animation_value_store_diagnostics(&store)

    testing.expect_value(t, animation_memory_begin_generation(
        &memory, 9), Animation_Memory_Status.Ok)
    testing.expect_value(t, animation_value_store_begin_generation(
        &store, 9), Animation_Value_Status.Ok)
    after := animation_value_store_diagnostics(&store)
    testing.expect_value(t, after.generation, u64(9))
    testing.expect_value(t, after.entry_count, 0)
    testing.expect_value(t, after.payload_bytes, 0)
    testing.expect_value(t, after.peak_entry_count, 1)
    testing.expect_value(t, after.arena.current_used, uint(0))
    testing.expect_value(
        t, after.arena.current_reserved, before.arena.current_reserved)
    destination: [3]u8
    testing.expect_value(t, animation_value_store_copy(
        &store, {9, 9, 2, 3}, destination[:]), Animation_Value_Status.Not_Found)
    testing.expect_value(t, animation_value_store_copy(
        &store, {8, 9, 2, 3}, destination[:]), Animation_Value_Status.Illegal_State)
}

//   Verify destruction releases backing storage and retains terminal high waters.
@(test)
core_test_animation_value_store_destroy_preserves_diagnostics :: proc(t: ^testing.T) {
    memory: Animation_Memory
    store: Animation_Value_Store
    testing.expect(t, animation_value_store_test_init(&memory, &store, 12))
    _ = animation_value_store_set(&store, {12, 1, 1, 2}, []u8{3})
    before := animation_value_store_diagnostics(&store)

    animation_value_store_destroy(&store)
    animation_memory_destroy(&memory)
    after := animation_value_store_diagnostics(&store)
    testing.expect(t, !after.initialized)
    testing.expect_value(t, after.entry_count, 0)
    testing.expect_value(t, after.arena.current_reserved, uint(0))
    owner_after := animation_memory_diagnostics(&memory)
    testing.expect_value(t, owner_after.peak_used, before.arena.peak_used)
    testing.expect_value(t, owner_after.destroy_count, u64(1))
}

//   Verify packed snapshots remain immutable after canonical overwrite.
@(test)
core_test_animation_value_snapshot_is_immutable :: proc(t: ^testing.T) {
    memory: Animation_Memory
    store: Animation_Value_Store
    testing.expect(t, animation_value_store_test_init(&memory, &store, 4))
    defer animation_value_store_test_destroy(&memory, &store)
    identity := Animation_Value_Identity{4, 2, 7, 8}
    _ = animation_value_store_set(&store, identity, []u8{1, 2})
    snapshot: Animation_Value_Snapshot
    testing.expect_value(t, animation_value_store_pack(
        &store, 4, &snapshot), Animation_Value_Status.Ok)
    _ = animation_value_store_set(&store, identity, []u8{3, 4})

    destination: [2]u8
    testing.expect_value(t, animation_value_snapshot_copy(
        &snapshot, identity, destination[:]), Animation_Value_Status.Ok)
    testing.expect(t, mem.compare(destination[:], []u8{1, 2}) == 0)
}

//   Verify pending reads choose the newest duplicate before snapshot state.
@(test)
core_test_animation_value_pending_reads_newest_write :: proc(t: ^testing.T) {
    pending: Animation_Value_Pending_Writes
    identity := Animation_Value_Identity{5, 3, 9, 10}
    testing.expect_value(t, animation_value_pending_append(
        &pending, identity, []u8{1, 2}), Animation_Value_Status.Ok)
    testing.expect_value(t, animation_value_pending_append(
        &pending, identity, []u8{7, 8}), Animation_Value_Status.Ok)

    destination: [2]u8
    testing.expect_value(t, animation_value_pending_copy(
        &pending, identity, destination[:]), Animation_Value_Status.Ok)
    testing.expect(t, mem.compare(destination[:], []u8{7, 8}) == 0)
}

//   Verify conflicting duplicates and capacity exhaustion poison pending state.
@(test)
core_test_animation_value_pending_rejection_is_terminal :: proc(t: ^testing.T) {
    pending: Animation_Value_Pending_Writes
    identity := Animation_Value_Identity{6, 1, 2, 3}
    _ = animation_value_pending_append(&pending, identity, []u8{1})
    testing.expect_value(t, animation_value_pending_append(
        &pending, {6, 1, 2, 4}, []u8{2}), Animation_Value_Status.Schema_Mismatch)
    testing.expect(t, pending.invalid)
    testing.expect_value(t, animation_value_pending_append(
        &pending, identity, []u8{3}), Animation_Value_Status.Illegal_State)
}

//   Verify malformed packed spans reject without changing destination bytes.
@(test)
core_test_animation_value_snapshot_rejects_malformed_span :: proc(t: ^testing.T) {
    snapshot: Animation_Value_Snapshot
    snapshot.entry_count = 1
    snapshot.entries[0] = {key = 1, schema_low = 2, schema_high = 3,
        payload_offset = i32(ANIMATION_VALUE_TOTAL_PAYLOAD_BYTES), payload_size = 2}
    destination := [2]u8{8, 9}
    testing.expect_value(t, animation_value_snapshot_copy(
        &snapshot, {1, 1, 2, 3}, destination[:]), Animation_Value_Status.Illegal_State)
    testing.expect(t, mem.compare(destination[:], []u8{8, 9}) == 0)
}