include(joinpath(@__DIR__, "sysimage_core.jl"))

Scratchpad.classify_parse("sum(1:3)")
Scratchpad.classify_parse("begin\n    value = 1")
Scratchpad.longest_completion_prefix(["EuclidGeometry", "EuclidAnimations"])

let host_runtime = Scratchpad.create_runtime_state(), state_ptr = Ptr{Cvoid}(0)
    session = Scratchpad.create_session(host_runtime, state_ptr, -1)
    host_runtime.current_session = session
    Scratchpad.queue_input(host_runtime, state_ptr, "sum(1:3)")
    Scratchpad.complete_backslash(host_runtime, state_ptr, "\\alpha")
    Scratchpad.complete_input(host_runtime, state_ptr, "EuclidRep", 9)
    Scratchpad.loop(host_runtime, state_ptr, 0f0)
    host_runtime.current_session = nothing
end