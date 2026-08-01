package main

import "core:unicode/utf8"

Position :: struct {
	x: int,
	y: int
}

Cursor :: struct {
	anchor: Position,
	head: Position
}

get_line_visual_len :: proc(line: []u8) -> int {
    return byte_idx_to_visual_x(line, len(line))
}

// Returns normalized start and end positions for rendering or deleting selections
get_selection_range :: proc(c: Cursor) -> (start: Position, end: Position, active: bool) {
    if c.anchor.x == c.head.x && c.anchor.y == c.head.y {
        return c.head, c.head, false
    }

    if c.anchor.y < c.head.y || (c.anchor.y == c.head.y && c.anchor.x < c.head.x) {
        return c.anchor, c.head, true
    }
    
    return c.head, c.anchor, true
}

ensure_primary_cursor :: proc() {
    if len(editor.cursor) == 0 {
        append(&editor.cursor, Cursor{anchor = {0, 0}, head = {0, 0}})
    }
}

is_pos_selected :: proc(c: Cursor, x, y: int) -> bool {
    start, end, active := get_selection_range(c)
    if !active do return false

    // Multi-line selection check
    if y < start.y || y > end.y do return false
    if y == start.y && y == end.y do return x >= start.x && x < end.x
    if y == start.y do return x >= start.x
    if y == end.y do return x < end.x

    return true // Entire line is selected inside a multi-line range
}

is_selected_in_any_cursor :: proc(x, y: int) -> bool {
    for c in editor.cursor {
        if is_pos_selected(c, x, y) {
            return true
        }
    }
    return false
}

// Retains only the primary cursor (clears multi-cursors)
reset_to_single_cursor :: proc() {
    ensure_primary_cursor()
    if len(editor.cursor) > 1 {
        primary := editor.cursor[0]
        clear(&editor.cursor)
        append(&editor.cursor, primary)
    }
}

// Keeps head and anchor within valid file line and character bounds
clamp_cursor :: proc() {
    ensure_primary_cursor()

    num_lines := len(editor.lines)
    if num_lines == 0 {
        for &c in editor.cursor {
            c.head = {0, 0}
            c.anchor = {0, 0}
        }
        return
    }

    for &c in editor.cursor {
        // Clamp Y
        c.head.y = clamp(c.head.y, 0, num_lines - 1)
        
        // Clamp X to current line length
        line := editor.lines[c.head.y][:]
        vis_len := get_line_visual_len(line)
        c.head.x = clamp(c.head.x, 0, vis_len)

        // Repeat for anchor if no active selection
        if c.anchor == c.head {
            c.anchor = c.head
        } else {
            c.anchor.y = clamp(c.anchor.y, 0, num_lines - 1)
            anchor_line := editor.lines[c.anchor.y][:]
            c.anchor.x = clamp(c.anchor.x, 0, get_line_visual_len(anchor_line))
        }
    }
}

// Keeps the primary cursor in view by scrolling row_offset
scroll_cursor_into_view :: proc() {
    ensure_primary_cursor()
    primary := editor.cursor[0]

    // Vertical scrolling
    if primary.head.y < editor.row_offset {
        editor.row_offset = primary.head.y
    }
    if primary.head.y >= editor.row_offset + int(editor.rows) {
        editor.row_offset = primary.head.y - int(editor.rows) + 1
    }
}

// ---------------------------------------------------------------------------
// Navigation Routines (Supports Shift-selection across all directions)
// ---------------------------------------------------------------------------

move_cursor_left :: proc(shift_held: bool) {
    ensure_primary_cursor()
    
    for &c in editor.cursor {
        if c.head.x > 0 {
            c.head.x -= 1
        } else if c.head.y > 0 {
            c.head.y -= 1
            prev_line := editor.lines[c.head.y][:]
            c.head.x = get_line_visual_len(prev_line)
        }

        if !shift_held {
            c.anchor = c.head
        }
    }
    scroll_cursor_into_view()
}

move_cursor_right :: proc(shift_held: bool) {
    ensure_primary_cursor()

    for &c in editor.cursor {
        line := editor.lines[c.head.y][:]
        vis_len := get_line_visual_len(line)

        if c.head.x < vis_len {
            c.head.x += 1
        } else if c.head.y < len(editor.lines) - 1 {
            c.head.y += 1
            c.head.x = 0
        }

        if !shift_held {
            c.anchor = c.head
        }
    }
    scroll_cursor_into_view()
}

move_cursor_up :: proc(shift_held: bool) {
    ensure_primary_cursor()

    for &c in editor.cursor {
        if c.head.y > 0 {
            c.head.y -= 1
            line := editor.lines[c.head.y][:]
            c.head.x = min(c.head.x, get_line_visual_len(line))
        }

        if !shift_held {
            c.anchor = c.head
        }
    }
    scroll_cursor_into_view()
}

move_cursor_down :: proc(shift_held: bool) {
    ensure_primary_cursor()

    for &c in editor.cursor {
        if c.head.y < len(editor.lines) - 1 {
            c.head.y += 1
            line := editor.lines[c.head.y][:]
            c.head.x = min(c.head.x, get_line_visual_len(line))
        }

        if !shift_held {
            c.anchor = c.head
        }
    }
    scroll_cursor_into_view()
}

move_cursor_home :: proc(shift_held: bool) {
    ensure_primary_cursor()

    for &c in editor.cursor {
        c.head.x = 0
        if !shift_held {
            c.anchor = c.head
        }
    }
    scroll_cursor_into_view()
}

move_cursor_end :: proc(shift_held: bool) {
    ensure_primary_cursor()

    for &c in editor.cursor {
        line := editor.lines[c.head.y][:]
        c.head.x = get_line_visual_len(line)
        if !shift_held {
            c.anchor = c.head
        }
    }
    scroll_cursor_into_view()
}