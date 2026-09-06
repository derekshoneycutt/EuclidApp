package core

import "base:runtime"
import "core:testing"

//   Verify initialization publishes one usable shared allocator.
@(test)
core_test_animation_memory_initializes :: proc(t: ^testing.T) {
    memory: Animation_Memory
    testing.expect(t, animation_memory_init(&memory))
    defer animation_memory_destroy(&memory)

    testing.expect(t, memory.initialized)
    testing.expect_value(t, memory.generation, u64(0))
    testing.expect(t, animation_memory_allocator(&memory) != runtime.Allocator{})
}

//   Verify valid generation transitions reset shared storage exactly once.
@(test)
core_test_animation_memory_advances_generation :: proc(t: ^testing.T) {
    memory: Animation_Memory
    testing.expect(t, animation_memory_init(&memory))
    defer animation_memory_destroy(&memory)
    allocator := animation_memory_allocator(&memory)
    bytes := make([]u8, 64, allocator)
    bytes[0] = 1

    testing.expect_value(t, animation_memory_begin_generation(
        &memory, 7), Animation_Memory_Status.Ok)
    diagnostics := animation_memory_diagnostics(&memory)
    testing.expect_value(t, memory.generation, u64(7))
    testing.expect_value(t, diagnostics.current_used, uint(0))
    testing.expect_value(t, diagnostics.reset_count, u64(1))
}

//   Verify an invalid generation cannot mutate memory or reset diagnostics.
@(test)
core_test_animation_memory_rejects_invalid_generation :: proc(t: ^testing.T) {
    memory: Animation_Memory
    testing.expect(t, animation_memory_init(&memory))
    defer animation_memory_destroy(&memory)
    before := animation_memory_diagnostics(&memory)

    testing.expect_value(t, animation_memory_begin_generation(
        &memory, 0), Animation_Memory_Status.Invalid_Argument)
    after := animation_memory_diagnostics(&memory)
    testing.expect_value(t, memory.generation, u64(0))
    testing.expect_value(t, after.reset_count, before.reset_count)
}

//   Verify destruction releases storage while retaining terminal diagnostics.
@(test)
core_test_animation_memory_destroy_preserves_diagnostics :: proc(t: ^testing.T) {
    memory: Animation_Memory
    testing.expect(t, animation_memory_init(&memory))
    allocator := animation_memory_allocator(&memory)
    bytes := make([]u8, 64, allocator)
    bytes[0] = 1
    before := animation_memory_diagnostics(&memory)

    animation_memory_destroy(&memory)
    after := animation_memory_diagnostics(&memory)
    testing.expect(t, !memory.initialized)
    testing.expect_value(t, memory.generation, u64(0))
    testing.expect_value(t, after.current_reserved, uint(0))
    testing.expect_value(t, after.peak_used, before.peak_used)
    testing.expect_value(t, after.destroy_count, u64(1))
}

//   Verify one owner transition resets all borrowers and the arena exactly once.
@(test)
core_test_animation_storage_advances_all_borrowers :: proc(t: ^testing.T) {
    memory: Animation_Memory
    values: Animation_Value_Store
    documents: Dynview_Document_Store
    testing.expect(t, animation_storage_init(&memory, &values, &documents))
    defer animation_storage_destroy(&memory, &values, &documents)
    testing.expect_value(t, animation_storage_begin_generation(
        &memory, &values, &documents, 3), Animation_Memory_Status.Ok)
    testing.expect_value(t, animation_value_store_set(
        &values, {3, 1, 1, 2}, []u8{4}), Animation_Value_Status.Ok)
    before := animation_memory_diagnostics(&memory)

    testing.expect_value(t, animation_storage_begin_generation(
        &memory, &values, &documents, 4), Animation_Memory_Status.Ok)
    after := animation_memory_diagnostics(&memory)
    value_diagnostics := animation_value_store_diagnostics(&values)
    testing.expect_value(t, memory.generation, u64(4))
    testing.expect_value(t, values.generation, u64(4))
    testing.expect_value(t, documents.generation, u64(4))
    testing.expect_value(t, value_diagnostics.entry_count, 0)
    testing.expect_value(t, after.reset_count, before.reset_count + 1)
}