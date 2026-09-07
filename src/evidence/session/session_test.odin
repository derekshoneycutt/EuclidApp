#+test
package session

import "../trace"

import "core:testing"

// Verify canonical lane names and retained category aliases resolve to typed policy.
@(test)
session_test_lane_selection_parses_canonical_and_legacy_names :: proc(t: ^testing.T) {
    lanes, valid := parse_lane_selection("lifecycle,transport,view")
    testing.expect(t, valid)
    testing.expect(t, .Lifecycle in lanes)
    testing.expect(t, .Transport in lanes)
    testing.expect(t, .Presentation in lanes)
    testing.expect(t, .Domain not_in lanes)

    lanes, valid = parse_lane_selection("")
    testing.expect(t, valid)
    testing.expect_value(t, lanes, ALL_LANES)

    _, valid = parse_lane_selection("domain,unknown")
    testing.expect(t, !valid)
}

// Verify disabled sessions remain inert regardless of configured output.
@(test)
session_test_disabled_policy_is_inert :: proc(t: ^testing.T) {
    session := new(Session)
    testing.expect(t, session != nil)
    defer free(session)
    testing.expect(t, session_init(session, Config{
        enabled = false,
        strict = true,
        output_mode = .File,
        output_path = "unused.jsonl",
    }))
    testing.expect_value(t, session.output_mode, Output_Mode.Disabled)
    testing.expect(t, !session_lane_enabled(session, .Domain))
    testing.expect(t, !session_should_fail_process(session))
}

// Verify policy, fixed identity, and lane filtering are initialized together.
@(test)
session_test_enabled_policy_copies_configuration :: proc(t: ^testing.T) {
    session := new(Session)
    testing.expect(t, session != nil)
    defer free(session)
    testing.expect(t, session_init(session, Config{
        enabled = true,
        strict = true,
        output_mode = .Sink,
        lanes = {.Lifecycle, .Domain},
    }))
    testing.expect(t, session.run_id_count > 0)
    testing.expect(t, session_lane_enabled(session, .Lifecycle))
    testing.expect(t, !session_lane_enabled(session, .Presentation))
    testing.expect(t, !session_should_fail_process(session))
}

// Verify required loss remains sticky across later healthy producer snapshots.
@(test)
session_test_required_loss_is_sticky :: proc(t: ^testing.T) {
    session := new(Session)
    testing.expect(t, session != nil)
    defer free(session)
    testing.expect(t, session_init(session, Config{
        enabled = true,
        strict = true,
        output_mode = .Sink,
        lanes = {.Diagnostic},
    }))
    display, julia_host: trace.Ring
    trace.ring_init(&display, .Display)
    trace.ring_init(&julia_host, .Julia_Host)
    rings := [2]^trace.Ring{&display, &julia_host}

    julia_host.required_evidence_lost = true
    session_merge_ring_completeness(session, rings[:])
    testing.expect(t, !session.required_evidence_complete)

    julia_host.required_evidence_lost = false
    session_merge_ring_completeness(session, rings[:])
    session_finish(session, true)
    testing.expect(t, session_should_fail_process(session))
}

// Verify optional pressure leaves bounded capacity for later required evidence.
@(test)
session_test_optional_pressure_preserves_required_reserve :: proc(t: ^testing.T) {
    session := new(Session)
    testing.expect(t, session != nil)
    defer free(session)
    testing.expect(t, session_init(session, Config{
        enabled = true,
        output_mode = .Sink,
        lanes = ALL_LANES,
    }))
    for _ in 0..<SESSION_EVENT_CAPACITY {
        testing.expect(t, session_accept_event(session, trace.Event{}))
    }
    testing.expect_value(t, session.event_count, SESSION_OPTIONAL_EVENT_CAPACITY)

    required := trace.Event{flags = {.Required}}
    for _ in 0..<SESSION_EVENT_CAPACITY - SESSION_OPTIONAL_EVENT_CAPACITY {
        testing.expect(t, session_accept_event(session, required))
    }
    testing.expect(t, session.required_evidence_complete)
    testing.expect(t, !session_accept_event(session, required))
    testing.expect(t, !session.required_evidence_complete)
}
