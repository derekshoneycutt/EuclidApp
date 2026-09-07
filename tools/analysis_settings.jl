using OdinJuliaAnalysis

Base.include(@__MODULE__, joinpath(@__DIR__, "build_config.jl"))
using .EuclidBuildConfiguration: native_linker_flags

const RepositoryRoot = normpath(joinpath(@__DIR__, ".."))
const JuliaProject = joinpath(RepositoryRoot, "src", "julia")
const AnalyzerRoot = dirname(dirname(pathof(OdinJuliaAnalysis)))
const BaseSettings = Base.include(
    @__MODULE__, joinpath(AnalyzerRoot, "settings.jl"))

JuliaProject in LOAD_PATH || pushfirst!(LOAD_PATH, JuliaProject)

module EuclidAnalysisRoots

const JuliaRoot = normpath(joinpath(@__DIR__, "..", "src", "julia"))

Base.include(@__MODULE__, joinpath(JuliaRoot, "odin-julia-bridge.jl"))
Base.include(@__MODULE__, joinpath(JuliaRoot, "latex.jl"))

end

const DefaultExcludes = [
    "tools/analysis",
    "src/julialib",
]
const AllExcludes = [
    "tools/analysis",
]

const RuleResponses = Dict(
    "DUPLICATE-CODE-POLICY-DRIFT" => Fail,
    "FUNCTION-METRIC-POLICY-DRIFT" => Fail,
    "NAMING-POLICY-DRIFT" => Fail,
    "CALL-ROOT-POLICY-DRIFT" => Fail,
    "IMPORT-POLICY-DRIFT" => Fail,
    "COMMON-LINE-90" => Warn,
    "COMMON-LINE-100" => Warn,
    "COMMON-LINE-120" => Fail,
    "COMMON-NO-TABS" => Fail,
    "JULIA-BROAD-CATCH" => Warn,
    "JULIA-SYNTAX" => Fail,
    "JULIA-CLOSING-PAREN-PLACEMENT" => Fail,
    "JULIA-JET-POSSIBLE-ERROR" => Fail,
    "JULIA-NAMING" => Warn,
    "JULIA-NONCONST-GLOBAL" => Warn,
    "JULIA-DECLARATION-ORDER" => Warn,
    "JULIA-RETURN-TUPLE" => Fail,
    "JULIA-PARAMETERS-FAIL" => Fail,
    "JULIA-FUNCTION-LINES-REPORT" => Warn,
    "JULIA-FUNCTION-LINES-WARN" => Fail,
    "JULIA-FUNCTION-LINES-FAIL" => Fail,
    "JULIA-CYCLOMATIC-REPORT" => Warn,
    "JULIA-CYCLOMATIC-WARN" => Fail,
    "JULIA-CYCLOMATIC-FAIL" => Fail,
    "ODIN-SYNTAX" => Fail,
    "ODIN-BUILD-FAILED" => Fail,
    "ODIN-CLOSING-PAREN-PLACEMENT" => Fail,
    "ODIN-NAMING" => Warn,
    "ODIN-NONCONST-GLOBAL" => Warn,
    "ODIN-DECLARATION-ORDER" => Fail,
    "ODIN-RETURN-TUPLE" => Fail,
    "ODIN-PARAMETERS-WARN" => Warn,
    "ODIN-PARAMETERS-FAIL" => Fail,
    "ODIN-FUNCTION-LINES-REPORT" => Warn,
    "ODIN-FUNCTION-LINES-WARN" => Fail,
    "ODIN-FUNCTION-LINES-FAIL" => Fail,
    "ODIN-CYCLOMATIC-REPORT" => Warn,
    "ODIN-CYCLOMATIC-WARN" => Fail,
    "ODIN-CYCLOMATIC-FAIL" => Fail,
    "ODIN-ALLOCATION-IMPLICIT" => Fail,
    "ODIN-ALLOCATION-UNKNOWN" => Fail,
    "ODIN-ALLOCATION-CONTEXT" => Warn,
    "ODIN-ALLOCATION-HEAP" => Warn,
    "ODIN-ALLOCATION-ARENA" => Warn,
    "ODIN-ALLOCATION-HIDDEN" => Warn,
    "ODIN-ALLOCATION-POLICY-DRIFT" => Fail,
    "REVIEWED-DIAGNOSTIC-POLICY-DRIFT" => Fail,
    "JULIA-DOC-MISSING" => Fail,
    "ODIN-DOC-MISSING" => Fail)

const AnimationLoopReason =
    "Animation state-machine loops enumerate every construction step in play order."

const ArenaTestFixtureReason =
    "Arena-backed test fixture storage is released when its explicit owner is destroyed."

# Columns: id, path, procedure, operation, target, minimum, maximum, reason.
const CustomTestAllocationReviews = [
    ("test-core-arena-owner-growth-buffer", "src/core/arena_owner_test.odin",
        "core_test_arena_owner_reset_releases_growth_blocks", "make", "[]u8", 1, 1,
        "Arena-backed test payload is invalidated by reset and released by destroy."),
    ("test-core-arena-owner-destroy-buffer", "src/core/arena_owner_test.odin",
        "core_test_arena_owner_destroy_preserves_diagnostics", "make", "[]u8", 1, 1,
        "Arena-backed test payload is released by the owner destruction under test."),
    ("test-evidence-allocation-baseline-buffer",
        "src/evidence/allocation/allocation_test.odin",
        "allocation_test_baseline_restoration", "make", "[]byte", 1, 1,
        "Bounded test allocation is deleted before the tracked domain is destroyed."),
    ("test-view-font-preparation-arena-pages", "src/view/font/font_test.odin",
        "view_test_preparation_arena_reuses_committed_pages", "make", "[]u8", 2, 2,
        "Bounded buffers verify preparation-arena reuse before explicit destruction."),
    ("test-compiled-bytes-publish-payloads", "src/dynview/compile/compiled_bytes_test.odin",
        "compiled_bytes_publish_sealed_plain_and_copy_payloads", "new",
        "app_core.Dynview_System", 1, 1, ArenaTestFixtureReason),
    ("test-compiled-bytes-reject-incomplete", "src/dynview/compile/compiled_bytes_test.odin",
        "compiled_bytes_reject_incomplete_stream_without_publication", "new",
        "app_core.Dynview_System", 1, 1, ArenaTestFixtureReason),
    ("test-compiled-bytes-consume-published", "src/dynview/compile/compiled_bytes_test.odin",
        "compiled_bytes_consume_published_content_views", "new",
        "app_core.Dynview_System", 1, 1, ArenaTestFixtureReason),
    ("test-compiled-bytes-plain-overflow", "src/dynview/compile/compiled_bytes_test.odin",
        "compiled_bytes_reject_plain_text_overflow_without_publication", "new",
        "app_core.Dynview_Compile_Cache", 1, 1, ArenaTestFixtureReason),
    ("test-compiled-copy-block-order", "src/dynview/compile/compiled_bytes_test.odin",
        "compiled_copy_blocks_publish_ordered_payload_spans", "new",
        "app_core.Dynview_System", 1, 1, ArenaTestFixtureReason),
    ("test-compiled-copy-block-overflow", "src/dynview/compile/compiled_bytes_test.odin",
        "compiled_copy_blocks_reject_exact_limit_overflow", "new",
        "app_core.Dynview_Compile_Cache", 1, 1, ArenaTestFixtureReason),
    ("test-copy-hit-target-capacity-reuse", "src/dynview/compile/compiled_bytes_test.odin",
        "copy_hit_targets_reuse_capacity_across_frames", "new",
        "app_core.Dynview_System", 1, 1, ArenaTestFixtureReason),
    ("test-copy-hit-target-overflow", "src/dynview/compile/compiled_bytes_test.odin",
        "copy_hit_targets_reject_exact_limit_overflow", "new",
        "app_core.Dynview_Compile_Cache", 1, 1, ArenaTestFixtureReason),
    ("test-math-binary-cancellation-cache", "src/dynview/math/programs_test.odin",
        "math_binary_atom_cancellation_matches_tex_neighbors", "new",
        "app_core.Dynview_Compile_Cache", 1, 1, ArenaTestFixtureReason),
    ("test-math-explicit-glue-cache", "src/dynview/math/programs_test.odin",
        "math_explicit_glue_uses_semantic_width", "new",
        "app_core.Dynview_Compile_Cache", 1, 1, ArenaTestFixtureReason),
    ("test-layout-storage-publish", "src/dynview/layout/storage_test.odin",
        "layout_storage_publishes_ordered_records", "new",
        "app_core.Dynview_Compile_Cache", 1, 1, ArenaTestFixtureReason),
    ("test-layout-storage-overflow", "src/dynview/layout/storage_test.odin",
        "layout_storage_rejects_exact_limit_overflow", "new",
        "app_core.Dynview_Compile_Cache", 1, 1, ArenaTestFixtureReason),
    ("test-layout-storage-reset", "src/dynview/layout/storage_test.odin",
        "layout_storage_reset_clears_partial_aliases", "new",
        "app_core.Dynview_Compile_Cache", 1, 1, ArenaTestFixtureReason),
    ("test-copy-interaction-target", "src/view/core/copy_interaction_test.odin",
        "copy_interaction_tracks_hovered_and_pressed_target", "new",
        "core.Dynview_System", 1, 1, ArenaTestFixtureReason),
    ("test-copy-interaction-payload", "src/view/core/copy_interaction_test.odin",
        "copy_interaction_resolves_target_payload_span", "new",
        "core.Dynview_System", 1, 1, ArenaTestFixtureReason)]

"""Build reviewed records for custom-allocator test fixtures."""
function custom_test_allocation_reviews()
    return [ReviewedAllocationPolicy(
        id, path, procedure, :custom, reason;
        operation=operation,
        target=target,
        allocator_source="allocator",
        certainty=:definite,
        response=Ignore,
        minimum_matches=minimum,
        maximum_matches=maximum)
        for (id, path, procedure, operation, target, minimum, maximum, reason) in
            CustomTestAllocationReviews]
end

# Modules whose exported `loop` drives one animation as a flat step sequence.
const AnimationLoopFiles = [
    "src/julia/algebra/groups/C_n.jl",
    "src/julia/algebra/groups/C_n_abelian.jl",
    "src/julia/algebra/groups/C_n_associative.jl",
    "src/julia/algebra/groups/z_2.jl",
    "src/julia/algebra/groups/z_2_closure.jl",
    "src/julia/algebra/groups/z_2_identity.jl",
    "src/julia/algebra/groups/z_2_inverse.jl",
    "src/julia/elements/book1/commonnotions.jl",
    "src/julia/elements/book1/def_001_point.jl",
    "src/julia/elements/book1/def_002_line.jl",
    "src/julia/elements/book1/def_003_linextrem.jl",
    "src/julia/elements/book1/def_004_straightline.jl",
    "src/julia/elements/book1/def_005_surface.jl",
    "src/julia/elements/book1/def_006_surfextrem.jl",
    "src/julia/elements/book1/def_007_planesurface.jl",
    "src/julia/elements/book1/def_008_angle.jl",
    "src/julia/elements/book1/def_010_perpendicular.jl",
    "src/julia/elements/book1/def_011_obtuseangle.jl",
    "src/julia/elements/book1/def_012_acuteangle.jl",
    "src/julia/elements/book1/def_013_boundary.jl",
    "src/julia/elements/book1/def_014_figure.jl",
    "src/julia/elements/book1/def_015_circle.jl",
    "src/julia/elements/book1/def_017_diameter.jl",
    "src/julia/elements/book1/def_018_semicircle.jl",
    "src/julia/elements/book1/def_019a_trilateral.jl",
    "src/julia/elements/book1/def_019b_quadrilateral.jl",
    "src/julia/elements/book1/def_019c_multilateral.jl",
    "src/julia/elements/book1/def_020a_equilateral.jl",
    "src/julia/elements/book1/def_020b_isosceles.jl",
    "src/julia/elements/book1/def_020c_scalene.jl",
    "src/julia/elements/book1/def_021a_righttriangle.jl",
    "src/julia/elements/book1/def_021b_obtusetriangle.jl",
    "src/julia/elements/book1/def_021c_acutetriangle.jl",
    "src/julia/elements/book1/def_022a_square.jl",
    "src/julia/elements/book1/def_022b_oblong.jl",
    "src/julia/elements/book1/def_022c_rhombus.jl",
    "src/julia/elements/book1/def_022d_rhomboid.jl",
    "src/julia/elements/book1/def_022d_trapezia.jl",
    "src/julia/elements/book1/def_023_parallel.jl",
    "src/julia/elements/book1/post_01_drawline.jl",
    "src/julia/elements/book1/post_02_finiteline.jl",
    "src/julia/elements/book1/post_03_drawcircle.jl",
    "src/julia/elements/book1/post_04_equalright.jl",
    "src/julia/elements/book1/post_05_nonparallel.jl",
    "src/julia/elements/book1/prop_01.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_I1.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_I2.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_I3.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_I4.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_I5.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_I6.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_I7.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_II1.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_II2.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_II3.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_II4.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_II5.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_III1.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_IV1.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_IV2.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_IV3.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_IV4.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_IV5.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_IV6.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_V.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_completeness.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/def_angle.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/def_circle.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/def_congruent_angles.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/def_congruent_triangles.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/def_figure.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/def_halfrays.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/def_polygon.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/def_segments.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/def_sideofline.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/def_supplementary_angles.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/def_triangle_angle.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_1.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_10.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_11.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_12.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_13.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_14.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_15.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_16.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_17.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_18.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_19.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_2.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_20.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_3.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_4.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_5.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_6.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_7.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_8.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_9.jl",
    "src/julia/proclus/proclus_01_isosceles.jl",
    "src/julia/proclus/proclus_02_scalene.jl",
]

"""Construct the rule settings to utilize for the analysis and report"""
function euclid_rule_settings()
    return [
        RuleSetting(
            setting.rule_id,
            setting.enabled,
            get(RuleResponses, setting.rule_id, Report))
        for setting in BaseSettings.rules
    ]
end

"""Return naming settings that permit Julia constructors to match their type names."""
function euclid_naming_settings()
    conventions = [
        convention.language == :julia && convention.kind == :function ?
            NamingConvention(
                :julia, :function, convention.casing;
                allow_leading_underscore=convention.allow_leading_underscore,
                allow_trailing_bang=convention.allow_trailing_bang,
                allow_constructor_names=true) :
            convention
        for convention in default_naming_settings().conventions
    ]
    return NamingSettings(conventions)
end

"""Add reviewed animation complexity exceptions to the reviews list."""
function add_animation_reviews!(reviews)
    path = "src/julia/nullanimation.jl"
    push!(reviews, ReviewedComplexity(
        "nullanimation-initialize-lines:$path", path, :julia,
        "initialize", :executable_lines, AnimationLoopReason;
        response=Ignore, minimum_matches=0))
    push!(reviews, ReviewedComplexity(
        "nullanimation-draw-line-lines:$path", path, :julia,
        "draw_line", :executable_lines, AnimationLoopReason;
        response=Ignore, minimum_matches=0))
    reviews
end

"""Add the reviewed metric policy for the failure-test allocators."""
function add_builder_test_allocation_procs!(reviews)
    push!(reviews, ReviewedComplexity(
        "test-bounded-builder-allocator-parameters",
        "src/core/bounded_builder_test.odin",
        :odin,
        "bounded_builder_test_allocator_proc",
        :parameters,
        "The test allocator implements the required seven-parameter allocator ABI.";
        response=Ignore))
    push!(reviews, ReviewedComplexity(
        "test-shaped-builder-allocator-parameters",
        "src/dynview/math/storage_test.odin",
        :odin,
        "shaped_builder_test_allocator_proc",
        :parameters,
        "The test allocator implements the required seven-parameter allocator ABI.";
        response=Ignore))
    push!(reviews, ReviewedComplexity(
        "test-document-store-allocator-parameters",
        "src/dynview/core/document_store_test.odin",
        :odin,
        "document_store_test_allocator_proc",
        :parameters,
        "The test allocator implements the required seven-parameter allocator ABI.";
        response=Ignore))
end

"""Add reviewed metric policies for one animation state-machine module."""
function add_animation_loop_reviews!(reviews, path)
    functions = (
        ("loop", "animation-loop"),
        ("get_view_text", "animation-get-view-text"),
        ("initialize", "animation-initialize"),
        ("reset_cycle_state", "animation-reset-cycle-state"))
    for (function_name, policy_name) in functions
        push!(reviews, ReviewedComplexity(
            "$policy_name-lines:$path", path, :julia, function_name,
            :executable_lines, AnimationLoopReason;
            response=Ignore, minimum_matches=0))
        push!(reviews, ReviewedComplexity(
            "$policy_name-branching:$path", path, :julia, function_name,
            :cyclomatic_complexity, AnimationLoopReason;
            response=Ignore, minimum_matches=0))
    end
end

"""Return reviewed function metric policies for animation state-machine loops."""
function animation_loop_reviews()
    reviews = ReviewedComplexity[]
    foreach(path -> add_animation_loop_reviews!(reviews, path), AnimationLoopFiles)
    add_animation_reviews!(reviews)
    add_builder_test_allocation_procs!(reviews)
end

AnalysisSettings(
    BaseSettings.profile,
    BaseSettings.failure_threshold,
    BaseSettings.thresholds,
    [
        ScanProfile(:default, DefaultExcludes),
        ScanProfile(:all, AllExcludes),
        ScanProfile(:aspirational, DefaultExcludes),
    ],
    euclid_rule_settings(),
    euclid_naming_settings(),
    JetSettings([
        JetEntryPoint(
            "latex-raw-math-facade",
            "src/julia/latex.jl",
            EuclidAnalysisRoots.EuclidLatex.replay_emit_math_block!,
            (Ptr{Cvoid}, String)),
    ]),
    OdinBuildSettings([
        OdinBuildTarget(
            "application",
            "src",
            "euclid-analysis",
            [
                "-vet",
                "-strict-style",
                "-disallow-do",
                "-warnings-as-errors",
                "-extra-linker-flags:$(native_linker_flags())",
            ]),
    ]),
    ReturnTupleSettings(2, 2),
    ParameterCountSettings(8, 5, 8),
    FunctionMetricSettings(
        BaseSettings.function_metrics.julia_lines,
        BaseSettings.function_metrics.odin_lines,
        BaseSettings.function_metrics.julia_cyclomatic,
        BaseSettings.function_metrics.odin_cyclomatic,
        animation_loop_reviews()),
    default_architecture_settings(),
    AllocationSettings(
        BaseSettings.allocations.known_procedures,
        [
            BaseSettings.allocations.source_patterns...;
            AllocatorSourcePattern("builder.allocator", :custom);
            AllocatorSourcePattern("store.allocator", :custom)
        ],
        ReviewedAllocationPolicy[
            # Shared arena ownership reserves virtual storage with explicit lifecycle.
            ReviewedAllocationPolicy(
                "core-arena-owner-growing-reservation",
                "src/core/arena_owner.odin",
                "arena_owner_growing_init",
                :arena,
                "Owner-scoped growing storage is reset in bulk and explicitly destroyed.";
                operation="arena_init_growing",
                target="arena",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-core-arena-owner-partial-init",
                "src/core/arena_owner_test.odin",
                "arena_owner_test_init_failure",
                :arena,
                "Test reservation is deliberately followed by failure to verify cleanup.";
                operation="arena_init_growing",
                target="arena",
                certainty=:definite,
                response=Ignore),
            custom_test_allocation_reviews()...,
            ReviewedAllocationPolicy(
                "test-dynview-parse-semantic-output",
                "src/dynview/parse/math_grammar_test.odin",
                "tex_math_test_output",
                :implicit,
                "Bounded parser output fixture is released by each focused test.";
                operation="new",
                target="Tex_Semantic_Output",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-document-shape-geometry-cache",
                "src/dynview/layout/document_build_test.odin",
                "document_shape_geometry_preserves_authored_units",
                :context,
                "Large shape-geometry test fixture is released by defer in the test body.";
                operation="new",
                target="app_core.Dynview_Compile_Cache",
                allocator_source="context.allocator",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-core-buffer-views",
                "src/dynview/core/buffers_test.odin",
                "command_buffer_views_prefer_published_content",
                :implicit,
                "Bounded test fixture is released by the procedure's deferred free.";
                operation="new",
                target="app_core.Dynview_Command_Buffer",
                certainty=:definite,
                response=Ignore),
            # Shared bounded builders grow within an explicit bulk-lifetime owner.
            ReviewedAllocationPolicy(
                "core-bounded-byte-builder-growth",
                "src/core/bounded_builder.odin",
                "bounded_byte_builder_reserve",
                :custom,
                "Hard-limit-checked geometric byte storage is reclaimed by the allocator owner at reset or destruction.";
                operation="make",
                target="[]u8",
                allocator_source="builder.allocator",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "core-bounded-element-builder-growth",
                "src/core/bounded_builder.odin",
                "bounded_element_builder_reserve",
                :custom,
                "Hard-limit-checked geometric plain-element storage is reclaimed by the allocator owner at reset or destruction.";
                operation="make",
                target="[]Element",
                allocator_source="builder.allocator",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "core-animation-value-store-payload",
                "src/core/animation_value_store.odin",
                "animation_value_store_insert",
                :custom,
                "Quota-checked opaque payload is retired by shared animation-memory reset or destruction.";
                operation="make",
                target="[]u8",
                allocator_source="store.allocator",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "core-animation-value-pending-payload",
                "src/core/animation_value_store.odin",
                "animation_value_pending_allocate_storage",
                :custom,
                "Validated pending payload storage is retired by shared animation-memory reset or destruction.";
                operation="make",
                target="[]u8",
                allocator_source="store.allocator",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "dynview-math-kern-record-cache",
                "src/dynview/math/shaping_cache.odin",
                "cache_math_kern_records",
                :custom,
                "Exact-size immutable kern-table storage is reclaimed when the cache arena is reset or destroyed.";
                operation="make",
                target="[]app_core.Font_Math_Kern_Table",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "dynview-math-accent-source-cache",
                "src/dynview/math/shaping_cache.odin",
                "cache_math_accent_source_records",
                :custom,
                "Exact-size immutable accent-source storage is reclaimed when the cache arena is reset or destroyed.";
                operation="make",
                target="[][2]app_core.Font_Math_Stretch_Source",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "test-bridge-animation-value-state",
                "src/bridge/animation_values_test.odin",
                "animation_value_test_state_create",
                :implicit,
                "One test host state owns the canonical animation store and is destroyed by the paired test helper.";
                operation="new",
                target="core.Euclid_General_State",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-view-snapshot-arena-service",
                "src/bridge/view_snapshot_arena_test.odin",
                "view_snapshot_arena_test_service",
                :implicit,
                "Each test destroys the service and all slot arenas through the paired helper.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-view-snapshot-builder-saturation-bytes",
                "src/bridge/view_snapshot_arena_test.odin",
                "view_snapshot_builder_saturation_preserves_payload",
                :implicit,
                "The exact-capacity test buffer is released by its deferred delete.";
                operation="make",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-view-snapshot-record-limit-payloads",
                "src/bridge/view_snapshot_arena_test.odin",
                "view_snapshot_record_transfer_accepts_exact_limits",
                :implicit,
                "Four exact-limit record buffers are released by deferred deletes.";
                operation="make",
                certainty=:definite,
                response=Ignore,
                minimum_matches=4,
                maximum_matches=4),
            ReviewedAllocationPolicy(
                "test-view-snapshot-record-overflow-payloads",
                "src/bridge/view_snapshot_arena_test.odin",
                "view_snapshot_record_transfer_rejects_each_overflow",
                :implicit,
                "Four overflow record buffers are released by deferred deletes.";
                operation="make",
                certainty=:definite,
                response=Ignore,
                minimum_matches=4,
                maximum_matches=4),
            ReviewedAllocationPolicy(
                "test-view-snapshot-document-overflow-payloads",
                "src/bridge/view_snapshot_arena_test.odin",
                "view_snapshot_document_transfer_rejects_overflow",
                :implicit,
                "Five overflow document buffers are released by deferred deletes.";
                operation="make",
                certainty=:definite,
                response=Ignore,
                minimum_matches=5,
                maximum_matches=5),
            ReviewedAllocationPolicy(
                "test-session-disabled-policy-state",
                "src/evidence/session/session_test.odin",
                "session_test_disabled_policy_is_inert",
                :implicit,
                "The large test session is heap-backed and released by deferred free.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-session-enabled-policy-state",
                "src/evidence/session/session_test.odin",
                "session_test_enabled_policy_copies_configuration",
                :implicit,
                "The large test session is heap-backed and released by deferred free.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-session-required-loss-state",
                "src/evidence/session/session_test.odin",
                "session_test_required_loss_is_sticky",
                :implicit,
                "The large test session is heap-backed and released by deferred free.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-session-optional-pressure-state",
                "src/evidence/session/session_test.odin",
                "session_test_optional_pressure_preserves_required_reserve",
                :implicit,
                "The large test session is heap-backed and released by deferred free.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-view-snapshot-reload-state",
                "src/bridge/view_snapshot_arena_test.odin",
                "view_snapshot_reload_stale_completion_defers_arena_reset",
                :implicit,
                "The test host state is released by its deferred free.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-view-snapshot-stale-publication-state",
                "src/bridge/view_snapshot_arena_test.odin",
                "view_snapshot_stale_publication_defers_arena_reset",
                :implicit,
                "The test host state is released by its deferred free.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-view-snapshot-shutdown-state",
                "src/bridge/view_snapshot_arena_test.odin",
                "view_snapshot_shutdown_release_clears_published_views",
                :implicit,
                "The test host state is released by its deferred free.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "bridge-interface-registry-growing-arena",
                "src/bridge/bootstrap.odin",
                "ensure_julia_interface_registry_arena",
                :arena,
                "One interface-generation arena is bulk-reset on reuse or rollback and destroyed at service teardown.";
                operation="arena_init_growing",
                target="iface^.animation_registry_arena",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "files-gif-session-growing-arena",
                "src/files/gif_encode.odin",
                "gif_encode_ensure_arena",
                :arena,
                "One capture-session arena is bulk-reset between recordings and destroyed with encoder state.";
                operation="arena_init_growing",
                target="state.arena",
                certainty=:definite,
                response=Ignore),
            # Bridge Animations Allocations ; these use a dedicated arena
            ReviewedAllocationPolicy(
                "bridge-animation-lookup-arena",
                "src/bridge/animations.odin",
                "animation_lookup_allocate",
                :unknown,
                "A dedicated arena is used to allocate lookup information.";
                operation="make",
                target="[]core.Euclid_Julia_Animation_Lookup_Entry",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "bridge-animation-add-registered-arena",
                "src/bridge/animations.odin",
                "add_animation_to_registry",
                :unknown,
                "A dedicated arena is used to allocate new animation registries.";
                operation="new",
                target="core.Euclid_Julia_Animation_Interface",
                certainty=:definite,
                response=Ignore),
            # Bridge Runtime Service Allocations ; these allocate the main bridge runtime
            ReviewedAllocationPolicy(
                "bridge-runtime-create-services",
                "src/bridge/runtime_service.odin",
                "create_julia_runtime_service",
                :implicit,
                "Single one-time creation of the julia runtime service structure.";
                operation="new",
                target="Julia_Runtime_Service",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "bridge-runtime-create-dynview",
                "src/bridge/runtime_service.odin",
                "create_julia_runtime_service",
                :context,
                "Single one-time creation of the julia runtime service structure.";
                operation="new",
                target="core.Dynview_System",
                allocator_source="context.allocator",
                certainty=:definite,
                response=Ignore),
            # GIF Encoding Allocations ; There is a dedicated arena and some minor heap allocation
            ReviewedAllocationPolicy(
                "files-gif-encode-lzwmem",
                "src/files/gif_encode.odin",
                "gif_encode_allocate_buffers",
                :unknown,
                "Allocate GIF buffers on the dedicated GIF capture arena.";
                operation="make",
                target="[]i16",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "files-gif-encode-tlb-used-mem",
                "src/files/gif_encode.odin",
                "gif_encode_allocate_buffers",
                :unknown,
                "Allocate GIF buffers on the dedicated GIF capture arena.";
                operation="make",
                target="[]u8",
                certainty=:definite,
                response=Ignore,
                maximum_matches=2),
            ReviewedAllocationPolicy(
                "files-gif-encode-pixels",
                "src/files/gif_encode.odin",
                "gif_encode_allocate_buffers",
                :unknown,
                "Allocate GIF buffers on the dedicated GIF capture arena.";
                operation="make",
                target="[]u32",
                certainty=:definite,
                response=Ignore,
                maximum_matches=2),
            ReviewedAllocationPolicy(
                "files-gif-encode-end-file-data",
                "src/files/gif_encode.odin",
                "gif_encode_end",
                :implicit,
                "One time allocation with a known destruction.";
                operation="make",
                target="[]u8",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "files-gif-encode-new-buffer",
                "src/files/gif_encode.odin",
                "gif_encode_new_buffer",
                :unknown,
                "Allocates on a dedicated and well managed arena for GIF capture.";
                operation="new",
                target="Gif_Encode_Buffer",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "files-gif-encode-new-buffer-data",
                "src/files/gif_encode.odin",
                "gif_encode_new_buffer",
                :unknown,
                "Allocates on a dedicated and well managed arena for GIF capture.";
                operation="make",
                target="[]u8",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "files-gif-encode-begin-lzw-stream",
                "src/files/gif_encode.odin",
                "gif_encode_begin_lzw_bitstream",
                :unknown,
                "Allocates on a dedicated and well managed arena for GIF capture.";
                operation="make",
                target="[]u8",
                certainty=:definite,
                response=Ignore),
            # Primary Runtime Allocations -- These are all single allocations made once
            ReviewedAllocationPolicy(
                "view-runtime-session-iso-scale",
                "src/view/runtime_session.odin",
                "make_iso_scale",
                :implicit,
                "Created once at startup with a definitive destruction at application end.";
                operation="new",
                target="Iso_Scale",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "view-runtime-session-drawing-surface",
                "src/view/runtime_session.odin",
                "make_drawing_surface",
                :implicit,
                "Created once at startup with a definitive destruction at application end.";
                operation="new",
                target="Euclid_Drawing_Surface",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "view-runtime-session-shapes-system",
                "src/view/runtime_session.odin",
                "make_point_system",
                :implicit,
                "Created once at startup with a definitive destruction at application end.";
                operation="new",
                target="Shapes_Point_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "view-runtime-session-particle-system",
                "src/view/runtime_session.odin",
                "initiate_animations_state",
                :implicit,
                "Created once at startup with a definitive destruction at application end.";
                operation="new",
                target="Particle_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "view-runtime-session-general-state",
                "src/view/runtime_session.odin",
                "initiate_animations_state",
                :implicit,
                "Created once at startup with a definitive destruction at application end.";
                operation="new",
                target="Euclid_General_State",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "view-simulation-executor",
                "src/view/simulation_executor.odin",
                "create_simulation_executor",
                :implicit,
                "Created once at startup with a definitive destruction at application end.";
                operation="new",
                target="Simulation_Executor",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "view-prose-shaping-workspace",
                "src/view/simulation_executor.odin",
                "create_simulation_executor",
                :implicit,
                "Bounded workspace created with the executor and released after its worker pool joins.";
                operation="new",
                target="core.Document_Prose_Shaping_Workspace",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "view-font-preparation-arena",
                "src/view/font/async.odin",
                "cache_preparation_arena_init",
                :arena,
                "Reserved once on first optional-font demand, reused across preparations, and destroyed with the font cache.";
                operation="arena_init_static",
                target="cache.preparation_arena",
                certainty=:definite,
                response=Ignore),
            # TODO : This next is allocated on context.allocator i.e. the heap
            #        re-review if safer allocator can fill
            ReviewedAllocationPolicy(
                "view-font-generation-glyph-metadata",
                "src/view/font/font.odin",
                "font_generation_glyphs_init",
                :custom,
                "Exact-size glyph state allocated once per resident font generation " *
                    "and released during generation teardown.";
                operation="make",
                target="[]Font_Glyph_Record",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "view-font-harfbuzz-ownership-test-arena",
                "src/view/font/font_test.odin",
                "view_test_harfbuzz_owns_source_and_bounds_output",
                :arena,
                "Test-only arena is destroyed before shaping to verify HarfBuzz copied the source bytes.";
                operation="arena_init_static",
                target="arena",
                certainty=:definite,
                response=Ignore),
            # Font preparation buffers use the dedicated preparation allocator and are
            # released together when preparation is reset or destroyed.
            ReviewedAllocationPolicy(
                "view-font-prepare-glyph-metadata",
                "src/view/font/prepare.odin",
                "prepare_allocate_metadata",
                :custom,
                "Bounded glyph metadata owned by Prepared_Font and released by prepare_destroy or the preparation arena reset.";
                operation="make",
                target="[]Prepared_Glyph",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "view-font-prepare-rectangle-metadata",
                "src/view/font/prepare.odin",
                "prepare_allocate_metadata",
                :custom,
                "Bounded rectangle metadata owned by Prepared_Font and released by prepare_destroy or the preparation arena reset.";
                operation="make",
                target="[]Prepared_Rectangle",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "view-font-prepare-atlas-pixels",
                "src/view/font/prepare.odin",
                "prepare_allocate_atlas",
                :custom,
                "Sized font-atlas storage owned by Prepared_Font and released by prepare_destroy or the preparation arena reset.";
                operation="make",
                target="[]u8",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore),
            # Task-pool storage is capacity-bounded and released by pool or fence teardown.
            ReviewedAllocationPolicy(
                "taskpool-backend-slots",
                "src/taskpool/taskpool.odin",
                "task_pool_init_backend",
                :custom,
                "Fixed-capacity task slots allocated once during pool initialization and released during pool teardown.";
                operation="make",
                target="[]Task_Slot",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "taskpool-backend-completion-reserve",
                "src/taskpool/taskpool.odin",
                "task_pool_init_backend",
                :dynamic_growth,
                "Completion storage is fully reserved to the configured task capacity before workers start.";
                operation="reserve",
                target="pool.backend.tasks_done",
                certainty=:potential,
                response=Ignore),
            ReviewedAllocationPolicy(
                "taskpool-fence-handles",
                "src/taskpool/taskpool.odin",
                "task_fence_begin",
                :custom,
                "One handle per fixed task slot, released when the deterministic fence is completed.";
                operation="make",
                target="[]Task_Handle",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore),
            # Evidence export allocates only at an explicit durable-output boundary.
            ReviewedAllocationPolicy(
                "evidence-artifact-trace-buffer",
                "src/evidence/artifact/artifact.odin",
                "artifact_trace_bytes",
                :context,
                "Bounded serialized trace buffer deleted by standalone and bundle writers after the write completes.";
                operation="make",
                target="[]byte",
                allocator_source="context.allocator",
                certainty=:definite,
                response=Ignore),
            # Test Allocations -- every site is a test fixture destroyed by defer free
            ReviewedAllocationPolicy(
                "test-evidence-allocation-foreign-buffer",
                "src/evidence/allocation/allocation_test.odin",
                "allocation_test_bad_free_is_evidence",
                :context,
                "Bounded bad-free test fixture released by defer in the test body.";
                operation="make",
                target="[]byte",
                allocator_source="context.allocator",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-evidence-observe-display-state",
                "src/evidence/observe/observe_test.odin",
                "observe_test_display_scalars",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Euclid_General_State",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-evidence-observe-point-system",
                "src/evidence/observe/observe_test.odin",
                "observe_test_display_scalars",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Shapes_Point_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-evidence-observe-particle-system",
                "src/evidence/observe/observe_test.odin",
                "observe_test_display_scalars",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Particle_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-evidence-observe-display-julia-service",
                "src/evidence/observe/observe_test.odin",
                "observe_test_display_scalars",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Julia_Runtime_Service",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-evidence-observe-julia-host-service",
                "src/evidence/observe/observe_test.odin",
                "observe_test_julia_host_scalars",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Julia_Runtime_Service",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-gif-capture-transition-state",
                "src/view/gif_capture_test.odin",
                "gif_capture_transitions_record_required_evidence",
                :context,
                "Large test fixture is destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Euclid_General_State",
                allocator_source="context.allocator",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-view-scenario-actions-state",
                "src/view/scenario_runtime_test.odin",
                "scenario_runtime_actions_use_display_owned_state",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="Euclid_General_State",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-view-scenario-capture-state",
                "src/view/scenario_runtime_test.odin",
                "scenario_runtime_waits_for_post_present_capture",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="Euclid_General_State",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-bridge-programmatic-selection-state",
                "src/bridge/animations_test.odin",
                "programmatic_selection_synchronizes_tree_state",
                :implicit,
                "Large test fixture is destroyed by defer free in the test body.";
                operation="new",
                target="core.Euclid_General_State",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-bridge-programmatic-selection-rejection-state",
                "src/bridge/animations_test.odin",
                "programmatic_selection_rejects_unregistered_target",
                :implicit,
                "Large test fixture is destroyed by defer free in the test body.";
                operation="new",
                target="core.Euclid_General_State",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-bridge-explicit-reload-state",
                "src/bridge/animations_test.odin",
                "explicit_reload_requests_animation_lifecycle_update",
                :implicit,
                "Large test fixture is destroyed by defer free in the test body.";
                operation="new",
                target="core.Euclid_General_State",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-bridge-explicit-reload-service",
                "src/bridge/animations_test.odin",
                "explicit_reload_requests_animation_lifecycle_update",
                :implicit,
                "Test service fixture is destroyed by defer free in the test body.";
                operation="new",
                target="core.Julia_Runtime_Service",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-bridge-animation-value-stale-tick-service",
                "src/bridge/animation_values_test.odin",
                "animation_value_stale_tick_does_not_commit_typed_write",
                :implicit,
                "Large runtime publication fixture is destroyed by defer in the test body.";
                operation="new",
                target="Julia_Runtime_Service",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-view-scenario-selection-state",
                "src/view/scenario_runtime_test.odin",
                "scenario_animation_selection_requests_tree_reveal",
                :implicit,
                "Large test fixture is destroyed by defer free in the test body.";
                operation="new",
                target="core.Euclid_General_State",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-view-scenario-selection-service",
                "src/view/scenario_runtime_test.odin",
                "scenario_animation_selection_requests_tree_reveal",
                :implicit,
                "Large test fixture is destroyed by defer free in the test body.";
                operation="new",
                target="core.Julia_Runtime_Service",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-view-scenario-reload-state",
                "src/view/scenario_runtime_test.odin",
                "scenario_reload_action_targets_next_runtime_generation",
                :implicit,
                "Large test fixture is destroyed by defer free in the test body.";
                operation="new",
                target="core.Euclid_General_State",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-view-scenario-reload-service",
                "src/view/scenario_runtime_test.odin",
                "scenario_reload_action_targets_next_runtime_generation",
                :implicit,
                "Test service fixture is destroyed by defer free in the test body.";
                operation="new",
                target="core.Julia_Runtime_Service",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-view-scenario-rejected-scratchpad-state",
                "src/view/scenario_runtime_test.odin",
                "scenario_rejected_scratchpad_submission_preserves_scroll_state",
                :implicit,
                "Large test fixture is destroyed by defer free in the test body.";
                operation="new",
                target="core.Euclid_General_State",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-view-scratchpad-output-growth-state",
                "src/view/ui/ui_test.odin",
                "scratchpad_output_growth_repins_to_bottom",
                :implicit,
                "Large test fixture is destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Euclid_General_State",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-gif-encode-collect-gce-packed-bytes",
                "src/files/gif_encode_test.odin",
                "collect_gce_packed_bytes",
                :temporary,
                "Test helper buffer on the temporary allocator, freed by test teardown.";
                operation="make",
                target="[]u8",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-particles-reserve-dead-low-prefers-dead",
                "src/particles/particles_test.odin",
                "reserve_dead_low_particle_slot_prefers_dead_then_wraps",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Particle_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-particles-reserve-dead-ring-advances",
                "src/particles/particles_test.odin",
                "reserve_dead_particle_slot_ring_advances",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Particle_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-particles-resolve-pair-no-collision",
                "src/particles/particles_test.odin",
                "resolve_dust_pair_no_collision_keeps_state",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Particle_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-particles-resolve-pair-approach-impulse",
                "src/particles/particles_test.odin",
                "resolve_dust_pair_overlap_with_approach_applies_impulse",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Particle_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-particles-resolve-pair-separating-skips",
                "src/particles/particles_test.odin",
                "resolve_dust_pair_overlap_with_separating_velocity_skips_impulse",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Particle_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-particles-resolve-pair-exact-overlap",
                "src/particles/particles_test.odin",
                "resolve_dust_pair_exact_overlap_uses_deterministic_separation",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Particle_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-particles-random-ranges-independent",
                "src/particles/particles_test.odin",
                "particle_random_ranges_use_independent_seeded_generators",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Particle_System",
                certainty=:definite,
                response=Ignore,
                minimum_matches=2,
                maximum_matches=2),
            ReviewedAllocationPolicy(
                "test-particles-resolve-collisions-rotates-samples",
                "src/particles/particles_test.odin",
                "resolve_dust_collisions_rotates_dense_bucket_samples",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Particle_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-particles-reset-clears-runtime-state",
                "src/particles/particles_test.odin",
                "reset_particles_clears_runtime_state_and_marks_all_slots_dead",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Particle_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-particles-reserve-dead-low-wraps",
                "src/particles/particles_test.odin",
                "reserve_dead_low_particle_slot_wraps_when_all_slots_alive",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Particle_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-particles-emit-shapes-hide-burst",
                "src/particles/particles_test.odin",
                "emit_shapes_hide_burst_spawns_dust_for_supported_shapes",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Particle_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-particles-clamp-xy-bounds-bounces",
                "src/particles/particles_test.odin",
                "clamp_xy_bounds_index_bounces_particles_back_inside_bounds",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Particle_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-shapes-clear-animation-data",
                "src/shapes/system_test.odin",
                "clear_animation_data_clears_animation_owned_slots",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Particle_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-generation-slots-alternate",
                "src/view/dynview_test.odin",
                "julia_interface_generation_slots_are_stable_and_alternate",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-snapshot-rejects-recycled-interface",
                "src/view/dynview_test.odin",
                "view_snapshot_rejects_recycled_interface_pointer_from_old_generation",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=3,
                maximum_matches=3),
            ReviewedAllocationPolicy(
                "test-dynview-batch-commits-point-positions",
                "src/view/dynview_test.odin",
                "scene_command_batch_commits_point_positions_in_order",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=4,
                maximum_matches=4),
            ReviewedAllocationPolicy(
                "test-dynview-batch-rejects-invalid-tail",
                "src/view/dynview_test.odin",
                "scene_command_batch_rejects_invalid_tail_atomically",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=4,
                maximum_matches=4),
            ReviewedAllocationPolicy(
                "test-dynview-batch-rejects-overflow-stale",
                "src/view/dynview_test.odin",
                "scene_command_batch_rejects_overflow_and_stale_animation",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=5,
                maximum_matches=5),
            ReviewedAllocationPolicy(
                "test-dynview-tick-reject-reason-classifies",
                "src/view/dynview_test.odin",
                "animation_tick_reject_reason_classifies_stale_generation_and_sequence",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=4,
                maximum_matches=4),
            ReviewedAllocationPolicy(
                "test-dynview-batch-defers-point-properties",
                "src/view/dynview_test.odin",
                "scene_command_batch_defers_general_point_properties_until_commit",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=4,
                maximum_matches=4),
            ReviewedAllocationPolicy(
                "test-dynview-batch-rejects-implicit-compass",
                "src/view/dynview_test.odin",
                "scene_command_batch_rejects_invalid_implicit_compass_handle_atomically",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=4,
                maximum_matches=4),
            ReviewedAllocationPolicy(
                "test-dynview-query-snapshot-immutable",
                "src/view/dynview_test.odin",
                "animation_query_snapshot_is_immutable_during_worker_tick",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=2,
                maximum_matches=2),
            ReviewedAllocationPolicy(
                "test-dynview-tick-rejects-stale-generation",
                "src/view/dynview_test.odin",
                "animation_tick_rejects_stale_generation_and_sequence",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=4,
                maximum_matches=4),
            ReviewedAllocationPolicy(
                "test-dynview-tick-coalescing-caps-backlog",
                "src/view/dynview_test.odin",
                "animation_tick_coalescing_caps_backlog_without_queue_growth",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-runtime-failure-event-identity",
                "src/view/dynview_test.odin",
                "julia_runtime_failure_event_records_request_identity",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-runtime-terminal-failure",
                "src/view/dynview_test.odin",
                "julia_runtime_terminal_failure_does_not_report_stopped",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-runtime-diagnostics-failure",
                "src/view/dynview_test.odin",
                "julia_runtime_diagnostics_report_failure_and_saturation",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-reload-failure-records-revision",
                "src/view/dynview_test.odin",
                "julia_reload_failure_records_package_revision",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-snapshot-copy-preserves-spans",
                "src/view/dynview_test.odin",
                "view_snapshot_copy_preserves_recursive_math_spans",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=2,
                maximum_matches=2),
            ReviewedAllocationPolicy(
                "test-dynview-snapshot-validation-rejects",
                "src/view/dynview_test.odin",
                "view_snapshot_validation_rejects_incomplete_streams",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-completed-snapshot-found",
                "src/view/dynview_test.odin",
                "completed_view_snapshot_is_found_without_event_index",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-newest-snapshot-supersedes",
                "src/view/dynview_test.odin",
                "newest_completed_view_snapshot_supersedes_older_completion",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-stale-snapshot-clears-commands",
                "src/view/dynview_test.odin",
                "stale_view_snapshot_clears_previous_animation_commands",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=5,
                maximum_matches=5),
            ReviewedAllocationPolicy(
                "test-dynview-text-span-script-attach-bounds",
                "src/view/dynview_test.odin",
                "dynview_text_span_and_script_attach_helpers_respect_bounds",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-layout-prepare-style-placement",
                "src/view/dynview_test.odin",
                "dynview_layout_prepare_style_placement_forces_line_break_and_indent",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-layout-push-item-metadata",
                "src/view/dynview_test.odin",
                "dynview_layout_push_item_records_block_and_column_metadata",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-track-font-cell-metrics",
                "src/view/dynview_test.odin",
                "dynview_track_font_retains_canonical_cell_metrics",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-layout-context-grid-metrics",
                "src/view/dynview_test.odin",
                "dynview_layout_context_derives_canonical_grid_metrics",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=2,
                maximum_matches=2),
            ReviewedAllocationPolicy(
                "test-dynview-layout-canonical-columns",
                "src/view/dynview_test.odin",
                "dynview_layout_columns_use_canonical_cell_width",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-layout-mixed-grid-rows",
                "src/view/dynview_test.odin",
                "dynview_layout_mixed_line_aggregates_grid_rows",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-layout-paragraph-grid-rows",
                "src/view/dynview_test.odin",
                "dynview_layout_paragraph_spacing_rounds_to_rows",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=2,
                maximum_matches=2),
            ReviewedAllocationPolicy(
                "test-dynview-layout-metrics-grid-rows",
                "src/view/dynview_test.odin",
                "dynview_layout_metrics_derive_from_rows",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=2,
                maximum_matches=2),
            ReviewedAllocationPolicy(
                "test-dynview-math-block-text-baseline",
                "src/view/dynview_test.odin",
                "dynview_math_block_aligns_with_text_baseline",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-line-ink-overflow-allowance",
                "src/view/dynview_test.odin",
                "dynview_line_permits_ink_overflow_into_neighbor_leading",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-line-ink-overflow-reserves-row",
                "src/view/dynview_test.odin",
                "dynview_line_reserves_row_when_ink_exceeds_allowance",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-layout-consume-text-run-wraps",
                "src/view/dynview_test.odin",
                "dynview_layout_consume_text_run_wraps_and_places_segments",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=2,
                maximum_matches=2),
            ReviewedAllocationPolicy(
                "test-dynview-measure-math-aggregates-children",
                "src/view/dynview_test.odin",
                "dynview_measure_math_program_aggregates_child_metrics",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=2,
                maximum_matches=2),
            ReviewedAllocationPolicy(
                "test-dynview-measure-math-rejects-invalid",
                "src/view/dynview_test.odin",
                "dynview_measure_math_program_rejects_invalid_shapes",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=2,
                maximum_matches=2),
            ReviewedAllocationPolicy(
                "test-dynview-measure-math-sums-widths",
                "src/view/dynview_test.odin",
                "dynview_measure_math_program_sums_multiple_command_widths",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=2,
                maximum_matches=2),
            ReviewedAllocationPolicy(
                "test-dynview-reset-cache-clears-layout",
                "src/view/dynview_test.odin",
                "dynview_reset_cache_clears_layout_state",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-inline-line-grid-cache",
                "src/view/dynview_test.odin",
                "dynview_inline_line_uses_intrinsic_grid_embedding",
                :implicit,
                "Large test fixture is destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Dynview_Compile_Cache",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-scratchpad-grid-scroll-runtime",
                "src/view/dynview_test.odin",
                "dynview_scratchpad_scroll_metrics_use_grid_rows",
                :implicit,
                "Large test fixture is destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Dynview_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-copy-hit-grid-cache",
                "src/view/dynview_test.odin",
                "dynview_copy_hit_target_uses_grid_row_bounds",
                :implicit,
                "Large test fixture is destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Dynview_Compile_Cache",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-inline-shapes-grid-cache",
                "src/view/dynview_test.odin",
                "dynview_inline_shapes_use_centered_grid_placement",
                :implicit,
                "Large test fixture is destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Dynview_Compile_Cache",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-math-padding-placement-cache",
                "src/view/dynview_test.odin",
                "dynview_math_block_placement_includes_visual_padding",
                :implicit,
                "Large test fixture is destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Dynview_Compile_Cache",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "test-dynview-math-overflow-placement-cache",
                "src/view/dynview_test.odin",
                "dynview_math_block_overflow_is_symmetric_and_explicit",
                :implicit,
                "Large test fixture is destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Dynview_Compile_Cache",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "test-dynview-publication-state",
                "src/view/dynview_test.odin",
                "view_snapshot_publication_records_animation_generation",
                :implicit,
                "Large test fixture is destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Euclid_General_State",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-publication-service",
                "src/view/dynview_test.odin",
                "view_snapshot_publication_records_animation_generation",
                :implicit,
                "Large test fixture is destroyed by defer free in the test body.";
                operation="new",
                target="app_bridge.Julia_Runtime_Service",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-publication-animation",
                "src/view/dynview_test.odin",
                "view_snapshot_publication_records_animation_generation",
                :implicit,
                "Large test fixture is destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Euclid_Julia_Animation_Interface",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-invalid-publication-state",
                "src/view/dynview_test.odin",
                "scratchpad_completion_waits_for_valid_view_publication",
                :implicit,
                "The test host state is released by its deferred free.";
                operation="new",
                target="app_core.Euclid_General_State",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-invalid-publication-service",
                "src/view/dynview_test.odin",
                "scratchpad_completion_waits_for_valid_view_publication",
                :implicit,
                "The test service is released by its deferred free.";
                operation="new",
                target="app_bridge.Julia_Runtime_Service",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-semantic-rollback-state",
                "src/view/dynview_test.odin",
                "scratchpad_semantic_rollback_preserves_published_fallback",
                :implicit,
                "The test host state is released by its deferred free.";
                operation="new",
                target="app_core.Euclid_General_State",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-semantic-rollback-service",
                "src/view/dynview_test.odin",
                "scratchpad_semantic_rollback_preserves_published_fallback",
                :implicit,
                "The test service is released by its deferred free.";
                operation="new",
                target="app_bridge.Julia_Runtime_Service",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-semantic-rollback-animation",
                "src/view/dynview_test.odin",
                "scratchpad_semantic_rollback_preserves_published_fallback",
                :implicit,
                "The test animation is released by its deferred free.";
                operation="new",
                target="app_core.Euclid_Julia_Animation_Interface",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-evidence-pressure-state",
                "src/view/dynview_test.odin",
                "scratchpad_completion_requires_current_complete_evidence",
                :implicit,
                "The test host state is released by its deferred free.";
                operation="new",
                target="app_core.Euclid_General_State",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-watermark-service",
                "src/view/dynview_test.odin",
                "scratchpad_completion_watermark_clears_at_lifecycle_boundary",
                :implicit,
                "The test service is released by its deferred free.";
                operation="new",
                target="app_bridge.Julia_Runtime_Service",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-malformed-span-snapshot",
                "src/view/dynview_test.odin",
                "view_snapshot_validation_rejects_all_malformed_text_spans",
                :implicit,
                "The test snapshot and its arena are released by deferred cleanup.";
                operation="new",
                target="app_bridge.View_Snapshot",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-fallback-lifetime-state",
                "src/view/dynview_test.odin",
                "view_snapshot_fallback_lifetime_survives_stale_and_repeated_publication",
                :implicit,
                "The test host state is released by its deferred free.";
                operation="new",
                target="app_core.Euclid_General_State",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-fallback-lifetime-service",
                "src/view/dynview_test.odin",
                "view_snapshot_fallback_lifetime_survives_stale_and_repeated_publication",
                :implicit,
                "The test service is released by its deferred free.";
                operation="new",
                target="app_bridge.Julia_Runtime_Service",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-shaped-storage-exact-limit-cache",
                "src/dynview/math/storage_test.odin",
                "dynview_shaped_builder_enforces_exact_limits",
                :implicit,
                "Large test fixture is destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Dynview_Compile_Cache",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-shaped-storage-invalid-span-cache",
                "src/dynview/math/storage_test.odin",
                "dynview_shaped_builder_rejects_invalid_spans_and_generation",
                :implicit,
                "Large test fixture is destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Dynview_Compile_Cache",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-shaped-storage-layout-glyph-span-cache",
                "src/dynview/math/storage_test.odin",
                "dynview_shaped_builder_rejects_layout_and_glyph_spans",
                :implicit,
                "Large test fixture is destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Dynview_Compile_Cache",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-shaped-storage-allocation-failure-cache",
                "src/dynview/math/storage_test.odin",
                "dynview_shaped_builder_allocation_failure_preserves_fallback",
                :implicit,
                "Large test fixture is destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Dynview_Compile_Cache",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-math-shaping-intrinsic-runtime",
                "src/dynview/math/shaping_cache_test.odin",
                "dynview_math_shaping_measures_cached_intrinsic_metrics",
                :implicit,
                "Large test fixture is destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Dynview_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-math-shaping-recursive-runtime",
                "src/dynview/math/shaping_cache_test.odin",
                "dynview_math_shaping_propagates_recursive_metrics",
                :implicit,
                "Large test fixture is destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Dynview_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-math-shaping-matrix-runtime",
                "src/dynview/math/shaping_cache_test.odin",
                "dynview_math_shaping_measures_matrix_cells",
                :implicit,
                "Large test fixture is destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Dynview_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-math-shaping-fallback-runtime",
                "src/dynview/math/shaping_cache_test.odin",
                "dynview_math_shaping_missing_glyph_uses_whole_run_fallback",
                :implicit,
                "Large test fixture is destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Dynview_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-gif-capture-status-note-truncation",
                "src/view/gif_capture_test.odin",
                "clear_and_set_gif_status_note_handles_truncation",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Euclid_Ui_Runtime_State",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-gif-capture-last-path-truncation",
                "src/view/gif_capture_test.odin",
                "clear_and_set_last_gif_path_handles_truncation",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Euclid_Ui_Runtime_State",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-gif-capture-cycle-boundary-consumes-once",
                "src/view/gif_capture_test.odin",
                "gif_capture_consume_cycle_boundary_consumes_once_per_generation",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Euclid_General_State",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-gif-capture-batch-splits-hide-points",
                "src/view/gif_capture_test.odin",
                "scene_command_batch_splits_large_hide_point_batches",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=4,
                maximum_matches=4),
            ReviewedAllocationPolicy(
                "test-sim-executor-fixed-step-advances-identity",
                "src/view/simulation_executor_test.odin",
                "deterministic_fixed_step_advances_identity_after_worker_join",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=3,
                maximum_matches=3),
            ReviewedAllocationPolicy(
                "test-sim-executor-fixed-step-emits-snapshot",
                "src/view/simulation_executor_test.odin",
                "deterministic_fixed_step_emits_post_join_checkpoint_snapshot",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=4,
                maximum_matches=4),
            ReviewedAllocationPolicy(
                "test-sim-executor-parallel-step-joins-updates",
                "src/view/simulation_executor_test.odin",
                "parallel_simulation_step_joins_particle_and_constraint_updates",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=3,
                maximum_matches=3),
            ReviewedAllocationPolicy(
                "test-sim-executor-frame-prep-joins-caches",
                "src/view/simulation_executor_test.odin",
                "parallel_frame_preparation_joins_shape_and_dynview_cache_updates",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=2,
                maximum_matches=2),
            ReviewedAllocationPolicy(
                "test-sim-executor-dynview-failure-fallback",
                "src/view/simulation_executor_test.odin",
                "dynview_cache_arena_failed_rebuild_preserves_fallback",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=2,
                maximum_matches=2),
            ]),
    ReportSettings(
        BaseSettings.report.color,
        BaseSettings.report.warning_limit,
        BaseSettings.report.report_limit;
        staging_maximum_response=Ignore,
        reviewed_diagnostics=ReviewedDiagnosticPolicy[
            ReviewedDiagnosticPolicy(
                "bridge-standard-julia-callback-wrapper",
                "ODIN-UNREACHABLE-PROCEDURE",
                "src/bridge/animations.odin",
                "call_julia_callback1",
                "Intentional standard Julia-caller shape retained to clarify the typed callback convention."),
            ReviewedDiagnosticPolicy(
                "julia-platform-host-symbol-cache",
                "JULIA-NONCONST-GLOBAL",
                "src/julia/bridge/common.jl",
                "HOST_SYMBOL_CACHE",
                "Platform-dependent host symbol resolution is cached for the process lifetime in this unique bridge boundary."),
        ]),
    AnalysisExtension[],
    default_duplicate_code_settings(),
    default_resource_lifetime_settings(),
    default_security_settings(),
    default_coverage_settings(),
    default_documentation_settings(),
    CallRootSettings([
        CallRootEntryPoint(
            "odin-bridge:invoke_with_exception_diagnostics", :julia,
            "invoke_with_exception_diagnostics",
            "src/bridge/bootstrap.odin resolves this symbol through jl_get_function"),
        CallRootEntryPoint(
            "odin-bridge:init_euclid_scripts", :julia, "init_euclid_scripts",
            "src/bridge/bootstrap.odin resolves this symbol through jl_get_function"),
        CallRootEntryPoint(
            "odin-bridge:ensure_generation_animation_loaded", :julia,
            "ensure_generation_animation_loaded",
            "src/bridge/animations.odin resolves this symbol through jl_get_function"),
        CallRootEntryPoint(
            "odin-bridge:invoke_generation_harness_scenario", :julia,
            "invoke_generation_harness_scenario",
            "src/bridge/animations.odin resolves this symbol through jl_get_function"),
        CallRootEntryPoint(
            "odin-bridge:is_euclid_runtime_host", :julia,
            "is_euclid_runtime_host",
            "src/bridge/runtime_service.odin resolves this symbol through jl_get_function"),
        CallRootEntryPoint(
            "odin-bridge:global_euclid_loop", :julia, "global_euclid_loop",
            "src/bridge/bootstrap.odin resolves this symbol through jl_get_function"),
        CallRootEntryPoint(
            "odin-bridge:scratchpad_classify_input", :julia,
            "scratchpad_classify_input",
            "src/bridge/bootstrap.odin resolves this symbol through jl_get_function"),
        CallRootEntryPoint(
            "odin-bridge:scratchpad_complete_backslash", :julia,
            "scratchpad_complete_backslash",
            "src/bridge/bootstrap.odin resolves this symbol through jl_get_function"),
        CallRootEntryPoint(
            "odin-bridge:scratchpad_complete_input", :julia,
            "scratchpad_complete_input",
            "src/bridge/bootstrap.odin resolves this symbol through jl_get_function"),
        CallRootEntryPoint(
            "odin-bridge:scratchpad_queue_input", :julia, "scratchpad_queue_input",
            "src/bridge/bootstrap.odin resolves this symbol through jl_get_function"),
        CallRootEntryPoint(
            "odin-bridge:scratchpad_save_history_to_file", :julia,
            "scratchpad_save_history_to_file",
            "src/bridge/bootstrap.odin resolves this symbol through jl_get_function"),
        CallRootEntryPoint(
            "odin-bridge:scratchpad_history_previous", :julia,
            "scratchpad_history_previous",
            "src/bridge/bootstrap.odin resolves this symbol through jl_get_function"),
        CallRootEntryPoint(
            "odin-bridge:scratchpad_history_next", :julia, "scratchpad_history_next",
            "src/bridge/bootstrap.odin resolves this symbol through jl_get_function"),
        CallRootEntryPoint(
            "odin-bridge:scratchpad_history_reset_cursor", :julia,
            "scratchpad_history_reset_cursor",
            "src/bridge/bootstrap.odin resolves this symbol through jl_get_function"),
        CallRootEntryPoint(
            "scratchpad-repl:save_history", :julia, "install_hook_helpers!.save_history",
            "the scratchpad REPL evaluates this command from user input"),
        CallRootEntryPoint(
            "scratchpad-repl:quit", :julia, "install_hook_helpers!.quit",
            "the scratchpad REPL evaluates this command from user input")],
        ReviewedImportPolicy[]))