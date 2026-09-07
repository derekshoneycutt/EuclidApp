module EuclidAlgebraGroupsZ2Inverse

using UUIDs
using ..AnimationCatalog

const AnimationId = UUID("b8a7ebd1-d89b-597c-aa7a-761008dc0113")

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex
using ..EuclidGeometry

export get_view_text, initialize, clean, loop, animation_entry

const VertexA = Float32[0.32f0, 0.34f0, 0f0]
const VertexB = Float32[0.68f0, 0.34f0, 0f0]
const VertexC = Float32[0.50f0, 0.65176916f0, 0f0]

const SideStarts = (VertexA, VertexB, VertexC)
const SideEnds = (VertexB, VertexC, VertexA)
const SideColors = (:steelblue, :palevioletred1, :khaki3)

const ReflectionLinePointA = Float32[0.5f0, 0.18f0, 0f0]
const ReflectionLinePointB = Float32[0.5f0, 0.88f0, 0f0]

const PenTopZ = 1.4f0
const ToolResetOffscreenJoint1 = Float32[0.5f0, 0.5f0, PenTopZ]
const ToolResetOffscreenJoint2 = Float32[0.5f0, 0.5f0, PenTopZ + 0.14f0]

const TriangleBrush = 5f0
const PenDescendDuration = 1.6f0
const SideDrawDuration = 1.9f0
const PenRiseDuration = 1.6f0
const PauseBeforeFirstReflectionDuration = 0.8f0
const ReflectionDuration = 2.4f0
const PauseBetweenReflectionsDuration = 0.55f0
const PauseAfterSecondReflectionDuration = 0.8f0

"""Stable native handles for one line owned by the animation."""
struct LineIds
    host::Int64
    joint1::Int64
    joint2::Int64
end

"""Complete immutable state for one inverse animation generation."""
struct AnimationState
    lines::NTuple{3,LineIds}
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhasePenDescend = 0f0
const PhaseDrawAB = 1f0
const PhaseDrawBC = 2f0
const PhaseDrawCA = 3f0
const PhasePenRise = 4f0
const PhasePauseBeforeFirstReflection = 5f0
const PhaseReflectFirst = 6f0
const PhasePauseBetweenReflections = 7f0
const PhaseReflectSecond = 8f0
const PhasePauseAfterSecondReflection = 9f0

const InverseFallbackText = raw"""Inverse

An inverse is the motion that undoes a given motion. In Z_2, every element is its own inverse. That means each motion undoes itself when applied again. This is common for reflections across a stable line.

For an element a in a group, an inverse a^{-1} is an element such that a o a^{-1} = a^{-1} o a = e, where e is the identity.

1. e^{-1} = e: doing nothing undoes itself.
2. r^{-1} = r: one reflection undoes itself because reflecting twice gives back the original figure."""

const InverseLatexDocument = raw"""\textbf{Inverse}

An inverse is the motion that undoes a given motion. In $\mathbb{Z}_2$, every element is its own inverse. That means each motion undoes itself when applied again. This is common for reflections across a stable line.

For an element $a$ in a group, an inverse $a^{-1}$ is an element such that
$a \circ a^{-1} = a^{-1} \circ a = e$, where $e$ is the identity.

1. $e^{-1} = e$: doing nothing undoes itself.\\
2. $r^{-1} = r$: one reflection undoes itself because reflecting twice gives back the original figure."""

const RefVertexA = EuclidGeometry.reflect_about_axis_x_half(VertexA)
const RefVertexB = EuclidGeometry.reflect_about_axis_x_half(VertexB)
const RefVertexC = EuclidGeometry.reflect_about_axis_x_half(VertexC)

const ReflectLineStartBase = (
    VertexA,
    VertexB,
    VertexB,
    VertexC,
    VertexC,
    VertexA)

const ReflectLineStartMirrored = (
    RefVertexA,
    RefVertexB,
    RefVertexB,
    RefVertexC,
    RefVertexC,
    RefVertexA)

const ReflectLineEndBase = ReflectLineStartMirrored
const ReflectLineEndMirrored = ReflectLineStartBase

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(state.lines, phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    EuclidLatex.emit_latex_view_text!(state_ptr,
        InverseLatexDocument, InverseFallbackText)
end

"""Apply a set of reflection poses to the tracked points."""
function set_reflection_pose!(
    state_ptr::Ptr{Cvoid},
    point_ids::NTuple{6,Int64},
    poses::NTuple{6,Vector{Float32}})

    for i in 1:6
        OdinJuliaBridge.set_point_position(state_ptr, point_ids[i], poses[i])
    end
end

"""Animate one reflection step, interpolating points from their start poses."""
function animate_reflection_step!(
    state_ptr::Ptr{Cvoid},
    timer::Float32,
    duration::Float32,
    point_ids::NTuple{6,Int64},
    starts::NTuple{6,Vector{Float32}})

    axis_x = ReflectionLinePointA[1]

    for i in 1:6
        point_start = starts[i]
        if point_start[1] < axis_x
            EuclidAnimations.transform_reflect2d_point_negative(
                state_ptr,
                point_ids[i],
                point_start,
                ReflectionLinePointA,
                ReflectionLinePointB,
                timer,
                duration)
        else
            EuclidAnimations.transform_reflect2d_point(
                state_ptr,
                point_ids[i],
                point_start,
                ReflectionLinePointA,
                ReflectionLinePointB,
                timer,
                duration)
        end
    end
end

"""Reset the three reflection lines to their default colors."""
function reset_line_colors!(
    state_ptr::Ptr{Cvoid},
    line_host_id_1::Int,
    line_host_id_2::Int,
    line_host_id_3::Int)

    OdinJuliaBridge.set_point_color(state_ptr, line_host_id_1, SideColors[1])
    OdinJuliaBridge.set_point_color(state_ptr, line_host_id_2, SideColors[2])
    OdinJuliaBridge.set_point_color(state_ptr, line_host_id_3, SideColors[3])
end

"""Reset the animation cycle while preserving its native handles."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    line_host_id_1 = state.lines[1].host
    line_host_id_2 = state.lines[2].host
    line_host_id_3 = state.lines[3].host
    line_joint1_id_1 = state.lines[1].joint1
    line_joint1_id_2 = state.lines[2].joint1
    line_joint1_id_3 = state.lines[3].joint1
    line_joint2_id_1 = state.lines[1].joint2
    line_joint2_id_2 = state.lines[2].joint2
    line_joint2_id_3 = state.lines[3].joint2

    if line_host_id_1 < 0 || line_host_id_2 < 0 || line_host_id_3 < 0
        return
    end

    OdinJuliaBridge.hide_point_batch(
        state_ptr,
        [line_host_id_1, line_host_id_2, line_host_id_3])

    OdinJuliaBridge.set_point_position(state_ptr, line_joint1_id_1, SideStarts[1])
    OdinJuliaBridge.set_point_position(state_ptr, line_joint2_id_1, SideStarts[1])
    OdinJuliaBridge.set_point_position(state_ptr, line_joint1_id_2, SideStarts[2])
    OdinJuliaBridge.set_point_position(state_ptr, line_joint2_id_2, SideStarts[2])
    OdinJuliaBridge.set_point_position(state_ptr, line_joint1_id_3, SideStarts[3])
    OdinJuliaBridge.set_point_position(state_ptr, line_joint2_id_3, SideStarts[3])

    reset_line_colors!(
        state_ptr,
        line_host_id_1,
        line_host_id_2,
        line_host_id_3)

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhasePenDescend, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.hide_compass(state_ptr)
    OdinJuliaBridge.lock_pen_joint1(
        state_ptr,
        ToolResetOffscreenJoint1[1],
        ToolResetOffscreenJoint1[2],
        ToolResetOffscreenJoint1[3])
    OdinJuliaBridge.move_pen_joint2(
        state_ptr,
        ToolResetOffscreenJoint2[1],
        ToolResetOffscreenJoint2[2],
        ToolResetOffscreenJoint2[3])

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    lines = ntuple(3) do i
        line = OdinJuliaBridge.create_new_line(
            state_ptr, SideStarts[i], SideStarts[i], SideColors[i], 0f0)
        LineIds(line.host_id, line.joint1_id, line.joint2_id)
    end

    reset_cycle_state(
        state_ptr, AnimationState(lines, PhasePenDescend, 0f0))
    OdinJuliaBridge.publish_view_update(state_ptr, get_view_text)
end

"""Clean any extra animation data at the end of performance"""
function clean(state_ptr::Ptr{Cvoid})
end

"""Perform an iteration of the animation loop for this animation"""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    state, status = OdinJuliaBridge.get_animation_value(state_ptr, StateKey)
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
    line_host_id_1 = state.lines[1].host
    line_host_id_2 = state.lines[2].host
    line_host_id_3 = state.lines[3].host

    if line_host_id_1 < 0
        return
    end

    line_joint1_id_1 = state.lines[1].joint1
    line_joint1_id_2 = state.lines[2].joint1
    line_joint1_id_3 = state.lines[3].joint1
    line_joint2_id_1 = state.lines[1].joint2
    line_joint2_id_2 = state.lines[2].joint2
    line_joint2_id_3 = state.lines[3].joint2

    line_reflection_point_ids = (
        Int64(line_joint1_id_1),
        Int64(line_joint2_id_1),
        Int64(line_joint1_id_2),
        Int64(line_joint2_id_2),
        Int64(line_joint1_id_3),
        Int64(line_joint2_id_3))

    phase = state.phase
    timer = state.timer

    reset_line_colors!(
        state_ptr,
        line_host_id_1,
        line_host_id_2,
        line_host_id_3)

    if phase == PhasePenDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr,
            timer,
            PenDescendDuration,
            PenTopZ,
            VertexA[1],
            VertexA[2])

        timer += dt
        if timer >= PenDescendDuration
            phase = PhaseDrawAB
            timer = 0f0
        end
    elseif phase == PhaseDrawAB || phase == PhaseDrawBC || phase == PhaseDrawCA
        side_index = Int(phase)
        line_host_id = side_index == 1 ? line_host_id_1 :
            (side_index == 2 ? line_host_id_2 : line_host_id_3)
        line_joint1_id = side_index == 1 ? line_joint1_id_1 :
            (side_index == 2 ? line_joint1_id_2 : line_joint1_id_3)
        line_joint2_id = side_index == 1 ? line_joint2_id_1 :
            (side_index == 2 ? line_joint2_id_2 : line_joint2_id_3)

        EuclidAnimations.animate_draw_line(state_ptr,
            timer, SideDrawDuration,
            SideStarts[side_index], SideEnds[side_index];
            penbrush=TriangleBrush,
            pencolor=SideColors[side_index],
            line_host_id=line_host_id,
            line_joint1_id=line_joint1_id,
            line_joint2_id=line_joint2_id)

        timer += dt
        if timer >= SideDrawDuration
            if phase == PhaseDrawCA
                phase = PhasePenRise
            else
                phase += 1f0
            end
            timer = 0f0
        end
    elseif phase == PhasePenRise
        EuclidAnimations.animate_pen_rise(
            state_ptr,
            timer,
            PenRiseDuration,
            PenTopZ,
            VertexA[1],
            VertexA[2])

        timer += dt
        if timer >= PenRiseDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            set_reflection_pose!(state_ptr,
                line_reflection_point_ids, ReflectLineStartBase)
            phase = PhasePauseBeforeFirstReflection
            timer = 0f0
        end
    elseif phase == PhasePauseBeforeFirstReflection
        timer += dt
        if timer >= PauseBeforeFirstReflectionDuration
            phase = PhaseReflectFirst
            timer = 0f0
        end
    elseif phase == PhaseReflectFirst
        animate_reflection_step!(
            state_ptr,
            timer,
            ReflectionDuration,
            line_reflection_point_ids,
            ReflectLineStartBase)

        timer += dt
        if timer >= ReflectionDuration
            set_reflection_pose!(state_ptr,
                line_reflection_point_ids, ReflectLineEndBase)
            phase = PhasePauseBetweenReflections
            timer = 0f0
        end
    elseif phase == PhasePauseBetweenReflections
        timer += dt
        if timer >= PauseBetweenReflectionsDuration
            phase = PhaseReflectSecond
            timer = 0f0
        end
    elseif phase == PhaseReflectSecond
        animate_reflection_step!(
            state_ptr,
            timer,
            ReflectionDuration,
            line_reflection_point_ids,
            ReflectLineStartMirrored)

        timer += dt
        if timer >= ReflectionDuration
            set_reflection_pose!(state_ptr,
                line_reflection_point_ids, ReflectLineEndMirrored)
            phase = PhasePauseAfterSecondReflection
            timer = 0f0
        end
    elseif phase == PhasePauseAfterSecondReflection
        timer += dt
        if timer >= PauseAfterSecondReflectionDuration
            reset_cycle_state(state_ptr, state)
            return
        end
    end

    OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, phase, timer))
end


"""Dispatch one bridge-stable lifecycle operation for this animation."""
function animation_entry(
    state_ptr::Ptr{Cvoid}, operation::Int32, dt::Float32)::Bool

    if operation == OdinJuliaBridge.ANIMATION_OPERATION_ENTER
        initialize(state_ptr)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_TICK
        loop(state_ptr, dt)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_EXIT
        clean(state_ptr)
    else
        return false
    end
    return true
end

end

AnimationCatalog.animation(
    EuclidAlgebraGroupsZ2Inverse.AnimationId,
    EuclidAlgebraGroupsZ2Inverse.animation_entry)
