package main

import "core:time"

Undo_State :: struct {
    lines:   [dynamic][dynamic]u8,
    cursors: [dynamic]Cursor,
}

Undo_Manager :: struct {
    undo_stack:     [dynamic]Undo_State,
    redo_stack:     [dynamic]Undo_State,
    
    last_edit_time: time.Time,
    is_grouping:    bool,
    max_history:    int,
}

clone_lines :: proc(lines: [dynamic][dynamic]u8) -> [dynamic][dynamic]u8 {
    res := make([dynamic][dynamic]u8, len(lines))
    for line, i in lines {
        res[i] = make([dynamic]u8, len(line))
        copy(res[i][:], line[:])
    }
    return res
}

clone_cursors :: proc(cursors: [dynamic]Cursor) -> [dynamic]Cursor {
    res := make([dynamic]Cursor, len(cursors))
    copy(res[:], cursors[:])
    return res
}

free_undo_state :: proc(state: ^Undo_State) {
    for line in state.lines {
        delete(line)
    }
    delete(state.lines)
    delete(state.cursors)
}

init_undo_manager :: proc(mgr: ^Undo_Manager, max_history: int = 200) {
    mgr.undo_stack = make([dynamic]Undo_State)
    mgr.redo_stack = make([dynamic]Undo_State)
    mgr.max_history = max_history
    mgr.is_grouping = false
}

destroy_undo_manager :: proc(mgr: ^Undo_Manager) {
    for &state in mgr.undo_stack {
        free_undo_state(&state)
    }
    delete(mgr.undo_stack)

    for &state in mgr.redo_stack {
        free_undo_state(&state)
    }
    delete(mgr.redo_stack)
}

clear_undo_manager :: proc(mgr: ^Undo_Manager) {
    for &state in mgr.undo_stack do free_undo_state(&state)
    clear(&mgr.undo_stack)

    for &state in mgr.redo_stack do free_undo_state(&state)
    clear(&mgr.redo_stack)

    mgr.is_grouping = false
}

begin_edit :: proc() {
    mgr := &editor.undo_mgr
    now := time.now()
    
    elapsed_ms := time.duration_milliseconds(time.diff(mgr.last_edit_time, now))
    if elapsed_ms > 500 {
        mgr.is_grouping = false
    }
    mgr.last_edit_time = now

    if !mgr.is_grouping {
        snapshot := Undo_State{
            lines   = clone_lines(editor.lines),
            cursors = clone_cursors(editor.cursor),
        }

        append(&mgr.undo_stack, snapshot)

        if len(mgr.undo_stack) > mgr.max_history {
            oldest := mgr.undo_stack[0]
            free_undo_state(&oldest)
            ordered_remove(&mgr.undo_stack, 0)
        }

        for &state in mgr.redo_stack do free_undo_state(&state)
        clear(&mgr.redo_stack)

        mgr.is_grouping = true
    }
}

flush_undo_group :: proc() {
    editor.undo_mgr.is_grouping = false
}

editor_undo :: proc() {
    flush_undo_group()
    mgr := &editor.undo_mgr

    if len(mgr.undo_stack) == 0 do return

    current_state := Undo_State{
        lines   = clone_lines(editor.lines),
        cursors = clone_cursors(editor.cursor),
    }
    append(&mgr.redo_stack, current_state)

    prev_state := pop(&mgr.undo_stack)

    for line in editor.lines do delete(line)
    delete(editor.lines)
    delete(editor.cursor)

    editor.lines  = prev_state.lines
    editor.cursor = prev_state.cursors
}

editor_redo :: proc() {
    flush_undo_group()
    mgr := &editor.undo_mgr

    if len(mgr.redo_stack) == 0 do return

    current_state := Undo_State{
        lines   = clone_lines(editor.lines),
        cursors = clone_cursors(editor.cursor),
    }
    append(&mgr.undo_stack, current_state)

    next_state := pop(&mgr.redo_stack)

    for line in editor.lines do delete(line)
    delete(editor.lines)
    delete(editor.cursor)

    editor.lines  = next_state.lines
    editor.cursor = next_state.cursors
}