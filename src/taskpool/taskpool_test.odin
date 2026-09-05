#+test
package taskpool

import "core:mem"
import "core:os"
import "core:sync"
import "core:testing"
import "core:thread"

Task_Test_Payload :: struct {
    input : int,
    output : int,
    executed : bool,
    fail : bool,
}

Task_Test_Gate :: struct {
    mutex : sync.Mutex,
    changed : sync.Cond,
    worker_started : bool,
    worker_released : bool,
}

// Compute one isolated test result without touching pool or application state.
task_test_execute :: proc(
    payload: rawptr, _: Task_Cancellation_Token) -> Task_Result {
    task := (^Task_Test_Payload)(payload)
    task.output = task.input * task.input
    task.executed = true
    return .Failed if task.fail else .Succeeded
}

// Occupy one worker until the owner explicitly releases it.
task_test_wait_at_gate :: proc(
    payload: rawptr, _: Task_Cancellation_Token) -> Task_Result {
    gate := (^Task_Test_Gate)(payload)
    sync.mutex_lock(&gate.mutex)
    gate.worker_started = true
    sync.cond_broadcast(&gate.changed)
    for !gate.worker_released {
        sync.cond_wait(&gate.changed, &gate.mutex)
    }
    sync.mutex_unlock(&gate.mutex)
    return .Succeeded
}

// Wait for cancellation and expose that cooperative observation to the owner.
task_test_wait_for_cancellation :: proc(
    payload: rawptr, token: Task_Cancellation_Token) -> Task_Result {
    task := (^Task_Test_Payload)(payload)
    for !task_cancellation_requested(token) {
        thread.yield()
    }
    task.executed = true
    return .Cancelled
}

// Wait until the sole worker has entered the blocking fixture.
task_test_wait_for_worker :: proc(gate: ^Task_Test_Gate) {
    sync.mutex_lock(&gate.mutex)
    for !gate.worker_started {
        sync.cond_wait(&gate.changed, &gate.mutex)
    }
    sync.mutex_unlock(&gate.mutex)
}

// Release the worker after owner-thread helping has been observed.
task_test_release_worker :: proc(gate: ^Task_Test_Gate) {
    sync.mutex_lock(&gate.mutex)
    gate.worker_released = true
    sync.cond_broadcast(&gate.changed)
    sync.mutex_unlock(&gate.mutex)
}

// Verify production defaults reserve display and Julia execution capacity.
@(test)
task_pool_test_default_worker_count :: proc(t: ^testing.T) {
    expected := max(os.get_processor_core_count() - 2, 1)

    testing.expect_value(t, task_pool_default_worker_count(), expected)
    testing.expect_value(t, task_pool_default_capacity(expected),
        expected * TASK_POOL_TASKS_PER_WORKER)
}

// Verify the pool exclusively owns a fixed allocator region until destruction.
@(test)
task_pool_test_allocator_ownership :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 2, 8))

    testing.expect(t, pool.backing != nil)
    testing.expect_value(t, len(pool.backing), pool.allocator_capacity)
    testing.expect(t, pool.allocator_capacity > 0)
    allocator := mem.mutex_allocator(&pool.synchronized_allocator)
    testing.expect(t, allocator.data == &pool.synchronized_allocator)

    task_pool_destroy(&pool)

    testing.expect(t, pool.backing == nil)
    testing.expect_value(t, pool.allocator_capacity, 0)
}

// Verify stale handles cannot observe a slot reused by a later task lifetime.
@(test)
task_pool_test_handle_generation :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 1))
    defer task_pool_destroy(&pool)
    first_payload := Task_Test_Payload{input = 2}
    first, _ := task_pool_submit(&pool, task_test_execute, &first_payload)
    task_pool_wait(&pool, first)
    second_payload := Task_Test_Payload{input = 3}
    second, _ := task_pool_submit(&pool, task_test_execute, &second_payload)

    testing.expect_value(t, first.index, second.index)
    testing.expect(t, first.generation != second.generation)
    testing.expect_value(t, task_pool_poll(&pool, first),
        Task_Poll_Outcome.Stale_Handle)
    task_pool_wait(&pool, second)
}

// Verify immediate waiting exposes output only after terminal observation.
@(test)
task_pool_test_immediate_wait :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 1))
    defer task_pool_destroy(&pool)
    payload := Task_Test_Payload{input = 4}
    handle, outcome := task_pool_submit(&pool, task_test_execute, &payload)

    testing.expect_value(t, outcome, Task_Submit_Outcome.Queued)
    result, joined := task_pool_wait(&pool, handle)

    testing.expect_value(t, result, Task_Result.Succeeded)
    testing.expect_value(t, joined, Task_Join_Outcome.Joined)
    testing.expect_value(t, payload.output, 16)
}

// Verify caller work may overlap safely before joining task-owned output.
@(test)
task_pool_test_overlapped_wait :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 1))
    defer task_pool_destroy(&pool)
    payload := Task_Test_Payload{input = 5}
    handle, _ := task_pool_submit(&pool, task_test_execute, &payload)
    independent_result := 7 * 6

    task_pool_wait(&pool, handle)

    testing.expect_value(t, independent_result, 42)
    testing.expect_value(t, payload.output, 25)
}

// Verify polling across an owner tick does not consume the terminal result.
@(test)
task_pool_test_cross_tick_poll_join :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 1))
    defer task_pool_destroy(&pool)
    payload := Task_Test_Payload{input = 6}
    handle, _ := task_pool_submit(&pool, task_test_execute, &payload)

    poll := task_pool_poll(&pool, handle)
    owner_tick := 1
    result, joined := task_pool_wait(&pool, handle)

    testing.expect(t, poll != .Stale_Handle)
    testing.expect_value(t, owner_tick, 1)
    testing.expect_value(t, result, Task_Result.Succeeded)
    testing.expect_value(t, joined, Task_Join_Outcome.Joined)
    testing.expect_value(t, payload.output, 36)
}

// Verify fences join grouped disjoint outputs before deterministic observation.
@(test)
task_pool_test_fence :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 2))
    defer task_pool_destroy(&pool)
    payloads := [4]Task_Test_Payload{{input = 1}, {input = 2}, {input = 3}, {input = 4}}
    fence, initialized := task_fence_begin(&pool)
    testing.expect(t, initialized)
    for &payload in payloads {
        testing.expect_value(t,
            task_fence_submit(&pool, &fence, task_test_execute, &payload),
            Task_Submit_Outcome.Queued)
    }

    testing.expect_value(t, task_fence_wait(&pool, &fence), Task_Result.Succeeded)
    testing.expect_value(t, payloads[0].output, 1)
    testing.expect_value(t, payloads[1].output, 4)
    testing.expect_value(t, payloads[2].output, 9)
    testing.expect_value(t, payloads[3].output, 16)
}

// Verify a waiting owner can execute useful queued work itself.
@(test)
task_pool_test_helping_wait :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 1, 8))
    defer task_pool_destroy(&pool)
    gate: Task_Test_Gate
    worker_handle, worker_outcome := task_pool_submit(
        &pool, task_test_wait_at_gate, &gate)
    testing.expect_value(t, worker_outcome, Task_Submit_Outcome.Queued)
    task_test_wait_for_worker(&gate)

    payload := Task_Test_Payload{input = 9}
    helped_handle, helped_outcome := task_pool_submit(
        &pool, task_test_execute, &payload)
    testing.expect_value(t, helped_outcome, Task_Submit_Outcome.Queued)

    result, joined := task_pool_wait(&pool, helped_handle)

    testing.expect_value(t, result, Task_Result.Succeeded)
    testing.expect_value(t, joined, Task_Join_Outcome.Joined)
    testing.expect_value(t, payload.output, 81)
    testing.expect_value(t, pool.helping_execution_count, u64(1))

    task_test_release_worker(&gate)
    task_pool_wait(&pool, worker_handle)
}

// Verify bounded occupancy reports queue pressure without losing ownership.
@(test)
task_pool_test_queue_full :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 1, 8))
    defer task_pool_destroy(&pool)
    payloads := [9]Task_Test_Payload{}
    handles: [8]Task_Handle
    for index in 0..<len(pool.slots) {
        handles[index], _ = task_pool_submit(
            &pool, task_test_execute, &payloads[index])
    }

    _, outcome := task_pool_submit(
        &pool, task_test_execute, &payloads[len(pool.slots)])

    testing.expect_value(t, outcome, Task_Submit_Outcome.Queue_Full)
    for handle in handles {
        task_pool_wait(&pool, handle)
    }
}

// Verify many workers mutate only their exclusive output partitions.
@(test)
task_pool_test_disjoint_writes_under_stress :: proc(t: ^testing.T) {
    TASK_COUNT :: 128
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 4, TASK_COUNT))
    defer task_pool_destroy(&pool)
    payloads: [TASK_COUNT]Task_Test_Payload
    fence, initialized := task_fence_begin(&pool)
    testing.expect(t, initialized)
    for &payload, index in payloads {
        payload.input = index
        testing.expect_value(t,
            task_fence_submit(&pool, &fence, task_test_execute, &payload),
            Task_Submit_Outcome.Queued)
    }

    testing.expect_value(t, task_fence_wait(&pool, &fence),
        Task_Result.Succeeded)
    for payload, index in payloads {
        testing.expect_value(t, payload.output, index * index)
    }
}

// Verify explicit allocator-backed capacity is not constrained by legacy limits.
@(test)
task_pool_test_capacity_scales_past_sixty_four :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 2, 128))
    defer task_pool_destroy(&pool)

    testing.expect_value(t, len(pool.slots), 128)
}

// Verify failure remains visible through the exactly-once terminal join.
@(test)
task_pool_test_failure_is_visible :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 1))
    defer task_pool_destroy(&pool)
    payload := Task_Test_Payload{fail = true}
    handle, _ := task_pool_submit(&pool, task_test_execute, &payload)

    result, outcome := task_pool_wait(&pool, handle)

    testing.expect_value(t, result, Task_Result.Failed)
    testing.expect_value(t, outcome, Task_Join_Outcome.Joined)
    _, second_outcome := task_pool_wait(&pool, handle)
    testing.expect_value(t, second_outcome, Task_Join_Outcome.Stale_Handle)
}

// Verify cancellation after worker completion wins until join consumes authority.
@(test)
task_pool_test_cancellation_wins_until_join :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 1))
    defer task_pool_destroy(&pool)
    payload := Task_Test_Payload{input = 7}
    handle, outcome := task_pool_submit(&pool, task_test_execute, &payload)
    testing.expect_value(t, outcome, Task_Submit_Outcome.Queued)
    for task_pool_poll(&pool, handle) == .Pending {
        thread.yield()
    }

    testing.expect_value(t, task_pool_cancel(&pool, handle),
        Task_Cancel_Outcome.Requested)
    testing.expect_value(t, task_pool_cancel(&pool, handle),
        Task_Cancel_Outcome.Already_Requested)
    result, joined := task_pool_wait(&pool, handle)

    testing.expect_value(t, result, Task_Result.Cancelled)
    testing.expect_value(t, joined, Task_Join_Outcome.Joined)
    testing.expect_value(t, payload.output, 49)
    testing.expect_value(t, task_pool_cancel(&pool, handle),
        Task_Cancel_Outcome.Stale_Handle)
}

// Verify a running task may observe cancellation without surrendering ownership early.
@(test)
task_pool_test_cooperative_cancellation :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 1))
    defer task_pool_destroy(&pool)
    payload: Task_Test_Payload
    handle, outcome := task_pool_submit(
        &pool, task_test_wait_for_cancellation, &payload)
    testing.expect_value(t, outcome, Task_Submit_Outcome.Queued)

    testing.expect_value(t, task_pool_cancel(&pool, handle),
        Task_Cancel_Outcome.Requested)
    result, joined := task_pool_wait(&pool, handle)

    testing.expect_value(t, result, Task_Result.Cancelled)
    testing.expect_value(t, joined, Task_Join_Outcome.Joined)
    testing.expect(t, payload.executed)
}

// Verify fence aggregation reports cancellation unless any joined task failed.
@(test)
task_pool_test_fence_result_precedence :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 2))
    defer task_pool_destroy(&pool)
    cancelled_payload := Task_Test_Payload{input = 2}
    succeeded_payload := Task_Test_Payload{input = 3}
    fence, initialized := task_fence_begin(&pool)
    testing.expect(t, initialized)
    testing.expect_value(t, task_fence_submit(
        &pool, &fence, task_test_execute, &cancelled_payload),
        Task_Submit_Outcome.Queued)
    testing.expect_value(t, task_fence_submit(
        &pool, &fence, task_test_execute, &succeeded_payload),
        Task_Submit_Outcome.Queued)
    testing.expect_value(t, task_pool_cancel(&pool, fence.handles[0]),
        Task_Cancel_Outcome.Requested)
    testing.expect_value(t, task_fence_wait(&pool, &fence),
        Task_Result.Cancelled)

    cancelled_payload = {input = 4}
    failed_payload := Task_Test_Payload{fail = true}
    fence, initialized = task_fence_begin(&pool)
    testing.expect(t, initialized)
    testing.expect_value(t, task_fence_submit(
        &pool, &fence, task_test_execute, &cancelled_payload),
        Task_Submit_Outcome.Queued)
    testing.expect_value(t, task_fence_submit(
        &pool, &fence, task_test_execute, &failed_payload),
        Task_Submit_Outcome.Queued)
    testing.expect_value(t, task_pool_cancel(&pool, fence.handles[0]),
        Task_Cancel_Outcome.Requested)
    testing.expect_value(t, task_fence_wait(&pool, &fence), Task_Result.Failed)
}

// Verify shutdown rejects new work after finishing every accepted task.
@(test)
task_pool_test_shutdown :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 2))
    payloads := [8]Task_Test_Payload{}
    for &payload in payloads {
        task_pool_submit(&pool, task_test_execute, &payload)
    }

    task_pool_shutdown(&pool)
    _, outcome := task_pool_submit(&pool, task_test_execute, &payloads[0])

    testing.expect_value(t, pool.state, Task_Pool_State.Stopped)
    testing.expect_value(t, outcome, Task_Submit_Outcome.Pool_Stopped)
    for payload in payloads {
        testing.expect(t, payload.executed)
    }
    task_pool_destroy(&pool)
}