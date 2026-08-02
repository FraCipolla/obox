package main

import "core:unicode/utf8"
import "core:slice"
import "core:bytes"

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

move_cursor_left :: proc(shift_held: bool = false) {
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

move_line_up :: proc() {
    for &c in editor.cursor {
        if c.anchor.y == 0 do continue 
        swap := editor.lines[c.anchor.y]
        editor.lines[c.anchor.y] = editor.lines[c.anchor.y - 1]
        editor.lines[c.anchor.y - 1] = swap
        move_cursor_up(false)
    }
}

move_line_down :: proc() {
    for &c in editor.cursor {
        if c.anchor.y == editor.rows do continue 
        swap := editor.lines[c.anchor.y]
        editor.lines[c.anchor.y] = editor.lines[c.anchor.y + 1]
        editor.lines[c.anchor.y + 1] = swap
        move_cursor_down(false)
    }
}

duplicate_line_up :: proc() {
    for &c in editor.cursor {
        inject_at(&editor.lines, c.anchor.y, slice.clone_to_dynamic(editor.lines[c.anchor.y][:]))
    }
}

duplicate_line_down :: proc() {
    for &c in editor.cursor {
        inject_at(&editor.lines, c.anchor.y, slice.clone_to_dynamic(editor.lines[c.anchor.y][:]))
        move_cursor_down(false)
    }
}

add_cursor_above :: proc() {
    if len(editor.cursor) == 0 || len(editor.lines) == 0 do return

    top_cursor := editor.cursor[0]
    for c in editor.cursor {
        if c.head.y < top_cursor.head.y {
            top_cursor = c
        }
    }

    target_y := top_cursor.head.y - 1
    if target_y < 0 do return

    line_len := len(editor.lines[target_y])
    target_x := clamp(top_cursor.head.x, 0, line_len)

    for c in editor.cursor {
        if c.head.y == target_y && c.head.x == target_x do return
    }

    pos := Position{x = target_x, y = target_y}
    append(&editor.cursor, Cursor{anchor = pos, head = pos})
}

add_cursor_below :: proc() {
    if len(editor.cursor) == 0 || len(editor.lines) == 0 do return

    bottom_cursor := editor.cursor[0]
    for c in editor.cursor {
        if c.head.y > bottom_cursor.head.y {
            bottom_cursor = c
        }
    }

    target_y := bottom_cursor.head.y + 1
    if target_y >= len(editor.lines) do return

    line_len := len(editor.lines[target_y])
    target_x := clamp(bottom_cursor.head.x, 0, line_len)

    for c in editor.cursor {
        if c.head.y == target_y && c.head.x == target_x do return
    }

    pos := Position{x = target_x, y = target_y}
    append(&editor.cursor, Cursor{anchor = pos, head = pos})
}

expand_word_from_cursor_pos :: proc(c: ^Cursor) {
    if c.head.y >= len(editor.lines) do return
    line := editor.lines[c.head.y][:]
    if len(line) == 0 do return

    x := clamp(c.head.x, 0, len(line) - 1)

    if !is_word_char(line[x - 1]) do return

    start_x := x
    for start_x > 0 && is_word_char(line[start_x - 1]) {
        start_x -= 1
    }

    end_x := x
    for end_x < len(line) && is_word_char(line[end_x]) {
        end_x += 1
    }

    c.anchor.x = start_x
    c.head.x   = end_x
}

find_next_occurrence :: proc(target: []u8, start_y, start_x: int) -> (found_y, found_x: int, ok: bool) {
    num_lines := len(editor.lines)
    if num_lines == 0 || len(target) == 0 do return 0, 0, false

    for i in 0 ..< num_lines {
        y := (start_y + i) % num_lines
        line := editor.lines[y][:]

        search_from := 0
        if i == 0 {
            search_from = clamp(start_x, 0, len(line))
        }

        if search_from >= len(line) do continue
        if match_offset := bytes.index(line[search_from:], target); match_offset != -1 {
            return y, search_from + match_offset, true
        }
    }

    return 0, 0, false
}

select_next_match :: proc() {
    if len(editor.cursor) == 0 do return

    primary := &editor.cursor[0]

    if primary.anchor == primary.head {
        expand_word_from_cursor_pos(primary)
        return
    }

    line := editor.lines[primary.head.y][:]
    sel_start := min(primary.anchor.x, primary.head.x)
    sel_end   := max(primary.anchor.x, primary.head.x)

    if sel_start < 0 || sel_end > len(line) do return
    target := line[sel_start:sel_end]
    if len(target) == 0 do return

    last_cursor := editor.cursor[len(editor.cursor) - 1]
    search_start_y := last_cursor.head.y
    search_start_x := max(last_cursor.anchor.x, last_cursor.head.x)

    found_y, found_x, ok := find_next_occurrence(target, search_start_y, search_start_x)
    if !ok do return
    
    for c in editor.cursor {
        c_min_x := min(c.anchor.x, c.head.x)
        if c.head.y == found_y && c_min_x == found_x {
            return
        }
    }

    new_cursor: Cursor
    new_cursor.anchor = { x = found_x,               y = found_y }
    new_cursor.head   = { x = found_x + len(target), y = found_y }

    append(&editor.cursor, new_cursor)
}