# Testing Strategy

Euclid verifies behavior through Odin and Julia test suites. The standard
repository gate builds with validation enabled, runs both suites, and performs
repository analysis.

## Standard Verification

Run this before delivery:

```sh
cmake --preset default
cmake --build --preset default --target check
```

The CMake `check` target invokes the combined build, analysis, and test gate.
The `vet` target runs only the validated build and analysis, so it is not a
substitute for `check`.

The gate runs:

- Odin tests with `odin test src -all-packages`.
- Julia tests from `src/julia/test/runtests.jl` using the Julia project in
  `src/julia`.
- Repository analysis and its regression tests, with the report written to
  `.build/reports/analysis.md`.

## Test Placement

Keep tests with the code they exercise:

- Odin package tests are `*_test.odin` files under `src/` and run with the
  all-packages Odin test command.
- Julia tests live in `src/julia/test/` and are included by
  `src/julia/test/runtests.jl`.

Add focused tests for changed behavior. Use the smallest relevant test while
developing, then run the CMake `check` target before considering the work
complete.

Run one Odin test by its package-qualified procedure name:

```sh
julia tools/make.jl unit odin \
  --test=core.core_test_animation_value_store_overwrites_bound_key
```

Run one test-bearing package by its path relative to `src/`:

```sh
julia tools/make.jl unit odin --package=dynview/math
ctest --preset all -L odin-package
```

The `odin-package` CTest label is deliberately outside the default `unit`
preset. Each entry invokes a separate Odin compile and link, so running the
whole granular label costs substantially more than the single all-packages
suite. Use it for package-level selection and editor discovery, not as a second
default gate.

Machine-readable runs emit schema `2.0.0` with source-located records in the
top-level `tests` array and aggregate timing in `suites`:

```sh
julia tools/make.jl unit --format=json
```

Each test record carries `name`, `language`, `package`, `file`, `line`,
`status`, `elapsed_ns`, and `message`. Both native runners expose aggregate
rather than leaf timing, so per-test `elapsed_ns` is `null`; suite
`elapsed_ns` remains measured. Failure messages are populated only for failed
or errored records.

## Optional Harness

The CMake `harness` target builds and runs the headless harness. It is a separate,
optional deterministic runtime scenario, not part of `check`. It produces
a canonical binary trace at `bin/semantic-trace-harness.bin` and is useful when
changing the runtime path it exercises. `evidence query` accepts either that bare trace
or a complete scenario bundle directory and applies the same kind, producer, lane,
correlation, and generation filters:

```sh
julia tools/make.jl evidence query bin/semantic-trace-harness.bin \
  --kind=animation_tick_committed --producer=display --lane=transport
```

Application semantic tracing retains JSONL as an explicit human-readable export through
`--semantic-trace-output=PATH`.

## Runtime Scenario Corpora

Source-controlled JSONL scenarios live in `tools/scenarios/`. This includes focused
typed-state and recursive math-font corpora plus a combined bounded flow covering typed
selection and updates, Scratchpad failure fallback, runtime reload, post-reload math
publication, captures, shutdown, and allocation restoration.

Run one scenario by its filename stem, or explicitly run the complete corpus:

```sh
julia tools/make.jl scenario point-runtime-reload-preserves-state
julia tools/make.jl scenario --all
julia tools/make.jl scenario point-runtime-reload-preserves-state --format=json
```

The command builds the headed debug application once, gives every selected scenario a
fresh directory under `.build/scenarios/`, and derives its reported result, reason,
failed step, and trace completeness from the validated terminal manifest. A failed or
inconclusive manifest returns a nonzero command status; inconclusive is never reported
as passed. Scenarios remain intentionally absent from `check` and continuous
integration because they require a display.

Allocation commands accept only the stable domain names `animation`, `snapshot_slots`,
and `display_cache`. Each `allocation_checkpoint` must precede the corresponding
`assert_allocation_baseline`; `assert_no_bad_frees` remains aggregate. Successful and
failed baseline comparisons emit typed semantic events, and terminal bundles retain
the checkpoint and final assertion samples in `allocations.json`.

The session retains at most 4,096 semantic events. Required evidence loss makes a
scenario inconclusive, so combined corpora must remain below that fixed bound rather
than treating a partial trace as success. Run scenarios into fresh artifact directories
and require both `result: "passed"` and `trace_complete: true`.

Focused capability scenarios cover GIF recording and armed cancellation, simulation
pause and resume, constrained-figure checkpoint storage, and rapid animation selection
supersession. The GIF completion flow records required `gif_started` and `gif_completed`
events at display-owned phase transitions; its allocation baseline is taken only for the
animation arena because reset-driven snapshot and display-cache high-water growth belongs
to those subsystems. Armed cancellation checks all three arena domains and aggregate bad
frees without entering recording.

Three advertised observations remain deliberately absent from authored scenario waits.
`runtime_shutdown_complete` is emitted during teardown after the scenario runner has
already reached its terminal status. `runtime_idle` and `animation_idle` can become true
between frames but are not observable at the scenario update boundary while ordinary
animation requests continue. Required checkpoint eviction similarly makes the run
inconclusive by design, so the corpus verifies correlated `checkpoint_stored` evidence
without treating eviction as a passing scenario. Covering these cases would require a
scenario-engine contract change rather than another JSONL program.

Runtime-generation rollback coverage lives in
`point-reload-candidate-load-rollback.jsonl` and
`point-reload-animation-enter-rollback.jsonl`. Each scenario selects and lazily
loads an animation, arms one Odin-owned failure with `inject_reload_failure`, then
issues the ordinary `reload_runtime` action. Passing evidence requires correlated
rollback, a committed old-generation animation tick after rollback's forced GC,
retained dynview, zero bad frees, complete trace retention, and orderly shutdown.
The Enter case proves candidate binding reached lifecycle validation; neither hook
mutates packaged assets or introduces Julia global state.

## Current Limits

The automated suite does not establish visual correctness. Rendering, layout,
and animation presentation still need appropriate visual review when those
surfaces change.
