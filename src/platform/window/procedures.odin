package window

import "../collections"
import "../debug"
import "core:strings"
import "vendor:sdl2"

createSubsystem :: proc() -> SubsystemState {
    output: SubsystemState
    output.valid = (0 == sdl2.Init(sdl2.INIT_VIDEO))
    output.success = output.valid
    output.events = EventBuffer{}
    output.windows = StateBuffer{}
    if !output.success do log_sdl_error()
    return output
}

destroySubsystem :: proc(state: ^SubsystemState) {
    if state.valid do sdl2.Quit()
    state.valid = false
    state.success = false
    collections.clear(&state.events.buffer)
}

updateSubsystem :: proc(requirements: ^RequirementBuffer, state: ^SubsystemState) {
    // create any new windows required
    {
        for i: u64 = 0; i < collections.get_count(&requirements.buffer); i += 1 {

            if collections.get_count(&state.windows.buffer) >= collections.get_capacity(&state.windows.buffer) {
                debug.log("Window Subsystem", debug.LogLevel.ERROR, "Window limit reached")
                break
            }

            requirement := collections.access(&requirements.buffer, i)
            windowState: State = ---
            title, err := strings.clone_to_cstring(requirement.title)
            if err != nil {
                debug.log("Window Subsystem", debug.LogLevel.ERROR, "Failed to clone title")
                continue
            }
            defer delete(title)

            windowState.ptr = sdl2.CreateWindow(
                title,
                sdl2.WINDOWPOS_UNDEFINED,
                sdl2.WINDOWPOS_UNDEFINED,
                requirement.width,
                requirement.height,
                sdl2.WINDOW_SHOWN | sdl2.WINDOW_VULKAN | sdl2.WINDOW_ALLOW_HIGHDPI,
            )

            if windowState.ptr == nil {
                log_sdl_error()
                continue
            }

            windowState.valid = true
            collections.try_add(&state.windows.buffer, windowState)

        }
    }

    // update idx
    {
        for i: u64 = 0; i < collections.get_count(&state.windows.buffer); i += 1 {
            windowState := collections.access(&state.windows.buffer, i)
            windowState.idx = u32(i)
        }
    }

    // create a temporary map
    windowMap: map[u32]^State = ---
    defer delete(windowMap)
    {
        windowMap = make(map[u32]^State, collections.get_count(&state.windows.buffer))
        for i: u64 = 0; i < collections.get_count(&state.windows.buffer); i += 1 {
            window := collections.access(&state.windows.buffer, i)
            windowMap[sdl2.GetWindowID((^sdl2.Window)(window.ptr))] = window
        }
    }

    // poll events
    {
        collections.clear(&state.events.buffer)
        evt: sdl2.Event = ---
        for sdl2.PollEvent(&evt) {
            if evt.type == sdl2.EventType.QUIT {
                count := u32(collections.get_count(&state.windows.buffer))
                for i: u32 = 0; i < count; i += 1 {
                    windowEvent: Event = ---
                    windowEvent.type = EventType.Close
                    windowEvent.close.windowIdx = i
                    if !collections.try_add(&state.events.buffer, windowEvent) {
                        debug.log("Window Subsystem", debug.LogLevel.ERROR, "Failed to add event")
                    }
                }
            } else if evt.type == sdl2.EventType.WINDOWEVENT {
                windowPtr := sdl2.GetWindowFromID(evt.window.windowID)
                if evt.window.event == sdl2.WindowEventID.CLOSE {
                    if window, success := windowMap[evt.window.windowID]; success {
                        windowEvent: Event = ---
                        windowEvent.type = EventType.Close
                        windowEvent.close.windowIdx = window.idx
                        if !collections.try_add(&state.events.buffer, windowEvent) {
                            debug.log("Window Subsystem", debug.LogLevel.ERROR, "Failed to add event")
                        }
                    }
                }
            } else if evt.type == sdl2.EventType.KEYDOWN {
                windowPtr := sdl2.GetWindowFromID(evt.key.windowID)
                if evt.key.keysym.sym == sdl2.Keycode.ESCAPE {
                    if window, success := windowMap[evt.window.windowID]; success {
                        windowEvent: Event = ---
                        windowEvent.type = EventType.Close
                        windowEvent.close.windowIdx = window.idx
                        if !collections.try_add(&state.events.buffer, windowEvent) {
                            debug.log("Window Subsystem", debug.LogLevel.ERROR, "Failed to add event")
                        }
                    }
                } else {
                    // ignore for now
                }
            } else {
                // ignore
            }
        }
    }

    // close any that need
    {
        for i: u64 = 0; i < collections.get_count(&state.events.buffer); i += 1 {
            event := collections.access(&state.events.buffer, i)
            if event.type == EventType.Close {
                windowState := collections.access(&state.windows.buffer, u64(event.close.windowIdx))
                sdl2.DestroyWindow((^sdl2.Window)(windowState.ptr))
                windowState.valid = false
                windowState.ptr = nil
            }
        }

        // remove any that are no longer valid
        for i: u64 = collections.get_count(&state.windows.buffer) - 1; true; i -= 1 {
            windowState := collections.access(&state.windows.buffer, i)
            if !windowState.valid {
                collections.try_erase_swap_back(&state.windows.buffer, i)
            }

            if i == 0 {
                break
            }
        }
    }
}

@(private = "file")
log_sdl_error :: proc() {
    error := sdl2.GetErrorString()
    debug.log("Window Subsystem", debug.LogLevel.ERROR, sdl2.GetErrorString())
}
