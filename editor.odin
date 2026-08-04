package main

import "core:bytes"
import "core:os"
import "core:unicode/utf8"
import "core:encoding/base64"
import "core:strings"
import "core:slice"

Panel :: enum {
	Editor,
	Command,
	Explorer,
    Find,
    Git,
    Terminal,
}

PopupBox :: struct {
	buff:   [dynamic]u8,
	cursor: Cursor,
}

Editor :: struct {
    keymap:         Keymap,
	cols:           int,
	rows:           int,
	row_offset:     int,
	lines:          [dynamic][dynamic]u8,
	cursor:         [dynamic]Cursor,

	explorer_width: int,
	show_explorer:  bool,
	filepath:       string,
	status_msg:     string,

	active_panel:   Panel,
	popup_box:        PopupBox,

	explorer:       Explorer,

    undo_mgr: Undo_Manager,
}

editor: Editor

init_editor :: proc() {
	err: bool
	editor.cols, editor.rows, err = get_window_size()
	if err {
		die("get_window_size")
	}
    init_keymap(&editor.keymap)
	editor.lines = make([dynamic][dynamic]u8)
	append(&editor.lines, make([dynamic]u8))
	cursor: Cursor = Cursor{}
	cursor.head = Position{x = 0, y = 0}
	append(&editor.cursor, cursor)
	editor.popup_box.buff = make([dynamic]u8)
	editor.explorer_width = 24
	editor.show_explorer = true
    init_undo_manager(&editor.undo_mgr)
}

destroy_editor :: proc() {
	for line in editor.lines {
		delete(line)
	}
	delete(editor.lines)
	delete(editor.popup_box.buff)
    delete(editor.keymap.bindings)
    destroy_undo_manager(&editor.undo_mgr)
}

clamp_popup_cursor :: proc() {
	editor.popup_box.cursor.head.x = clamp(editor.popup_box.cursor.head.x, 0, len(editor.popup_box.buff))
}

editor_open_file :: proc(filename: string) -> bool {
	data, ok := os.read_entire_file_from_path(filename, context.temp_allocator)
	if ok != nil do return false

	for line in editor.lines do delete(line)
	clear(&editor.lines)

	raw_lines := bytes.split(data, {'\n'}, context.temp_allocator)

	for raw_line in raw_lines {
		line := raw_line

		if len(line) > 0 && line[len(line) - 1] == '\r' {
			line = line[:len(line) - 1]
		}

		dyn_line := make([dynamic]u8)
		append(&dyn_line, ..line)
		append(&editor.lines, dyn_line)
	}

	if len(editor.lines) == 0 {
		append(&editor.lines, make([dynamic]u8))
	}

    clear_undo_manager(&editor.undo_mgr)
	return true
}

delete_selection :: proc() {
    begin_edit()
    if len(editor.cursor) == 0 do return

    cursor_indices := make([dynamic]int, 0, len(editor.cursor))
    defer delete(cursor_indices)

    for i in 0 ..< len(editor.cursor) {
        append(&cursor_indices, i)
    }

    slice.sort_by(cursor_indices[:], proc(i, j: int) -> bool {
        c1, c2 := editor.cursor[i], editor.cursor[j]
        start1 := c1.anchor.y < c1.head.y ? c1.anchor : c1.head
        start2 := c2.anchor.y < c2.head.y ? c2.anchor : c2.head
        
        if start1.y != start2.y do return start1.y > start2.y
        return start1.x > start2.x
    })

    for idx in cursor_indices {
        c := &editor.cursor[idx]
        if c.anchor == c.head do continue

        start_vis, end_vis: Position
        if c.anchor.y < c.head.y || (c.anchor.y == c.head.y && c.anchor.x <= c.head.x) {
            start_vis, end_vis = c.anchor, c.head
        } else {
            start_vis, end_vis = c.head, c.anchor
        }

        if start_vis.y == end_vis.y {
            line := &editor.lines[start_vis.y]
            
            start_byte := visual_x_to_byte_idx(line[:], start_vis.x)
            end_byte   := visual_x_to_byte_idx(line[:], end_vis.x)
            
            start_byte = clamp(start_byte, 0, len(line))
            end_byte   = clamp(end_byte, start_byte, len(line))

            delete_bytes := end_byte - start_byte
            if delete_bytes > 0 {
                copy(line[start_byte:], line[end_byte:])
                resize(line, len(line) - delete_bytes)
            }

        } else {
            start_line := &editor.lines[start_vis.y]
            end_line   := &editor.lines[end_vis.y]

            start_byte := visual_x_to_byte_idx(start_line[:], start_vis.x)
            end_byte   := visual_x_to_byte_idx(end_line[:], end_vis.x)

            start_byte = clamp(start_byte, 0, len(start_line))
            end_byte   = clamp(end_byte, 0, len(end_line))

            resize(start_line, start_byte)

            if end_byte < len(end_line) {
                append(start_line, ..end_line[end_byte:])
            }

            for y := end_vis.y; y > start_vis.y; y -= 1 {
                delete(editor.lines[y])
                ordered_remove(&editor.lines, y)
            }
        }

        c.head   = start_vis
        c.anchor = start_vis
    }
}

has_any_selection :: proc() -> bool {
    for c in editor.cursor {
        if c.anchor != c.head do return true
    }
    return false
}

insert_char :: proc(ch: rune) {
    begin_edit()
    if len(editor.lines) == 0 {
        append(&editor.lines, make([dynamic]u8))
    }

    clamp_cursor()
    delete_selection()

    indices := make([dynamic]int, 0, len(editor.cursor))
    defer delete(indices)

    for i in 0 ..< len(editor.cursor) {
        append(&indices, i)
    }

    slice.sort_by(indices[:], proc(i, j: int) -> bool {
        c1, c2 := editor.cursor[i], editor.cursor[j]
        if c1.head.y != c2.head.y do return c1.head.y > c2.head.y
        return c1.head.x > c2.head.x
    })

    for idx in indices {
        c := &editor.cursor[idx]
        line := &editor.lines[c.head.y]

        byte_idx := visual_x_to_byte_idx(line[:], c.head.x)
        buf, bytes_len := utf8.encode_rune(ch)

        for i in 0 ..< bytes_len {
            inject_at(line, byte_idx + i, buf[i])
        }

        step := 1
        if ch == '\t' {
            step = 4 - (c.head.x % 4)
        }

        orig_x := c.head.x

        c.head.x += step
        c.anchor = c.head

        for &other in editor.cursor {
            if &other == c do continue
            if other.head.y == c.head.y && other.head.x > orig_x {
                other.head.x += step
                other.anchor.x += step
            }
        }
    }
}

insert_newline :: proc() {
    begin_edit()
	if len(editor.lines) == 0 {
		append(&editor.lines, make([dynamic]u8))
	}

	clamp_cursor()
    delete_selection()

	curr_line := &editor.lines[editor.cursor[0].head.y]
	new_line := make([dynamic]u8)

	if editor.cursor[0].head.x < len(curr_line) {
		append(&new_line, ..curr_line[editor.cursor[0].head.x:])
		resize(curr_line, editor.cursor[0].head.x)
	}

	inject_at(&editor.lines, editor.cursor[0].head.y + 1, new_line)

	editor.cursor[0].head.y += 1
    editor.cursor[0].anchor.y += 1
	editor.cursor[0].head.x = 0
	editor.cursor[0].anchor.x = 0
}

visual_x_to_byte_idx :: proc(line: []u8, target_x: int) -> int {
    curr_x := 0
    for i := 0; i < len(line); i += 1 {
        if curr_x >= target_x do return i

        if line[i] == '\t' {
            curr_x += 4 - (curr_x % 4)
        } else {
            curr_x += 1
        }
    }
    return len(line)
}

byte_idx_to_visual_x :: proc(line: []u8, target_byte: int) -> int {
    vis_x := 0
    limit := min(target_byte, len(line))

    for i := 0; i < limit; i += 1 {
        if line[i] == '\t' {
            vis_x += 4 - (vis_x % 4)
        } else {
            vis_x += 1
        }
    }
    return vis_x
}

get_line_visual_width :: proc(line: []u8) -> int {
    return byte_idx_to_visual_x(line, len(line))
}

backspace_char :: proc() {
    begin_edit()
    if len(editor.lines) == 0 do return
    clamp_cursor()

    if has_any_selection() {
        delete_selection()
        return
    }

    indices := make([dynamic]int, 0, len(editor.cursor))
    defer delete(indices)

    for i in 0 ..< len(editor.cursor) {
        append(&indices, i)
    }

    slice.sort_by(indices[:], proc(i, j: int) -> bool {
        c1, c2 := editor.cursor[i], editor.cursor[j]
        if c1.head.y != c2.head.y do return c1.head.y > c2.head.y
        return c1.head.x > c2.head.x
    })

    for idx in indices {
        c := &editor.cursor[idx]

        if c.head.x > 0 {
            line := &editor.lines[c.head.y]
            byte_idx := visual_x_to_byte_idx(line[:], c.head.x)

            if byte_idx > 0 {
                target_idx := byte_idx - 1
                orig_x := c.head.x

                ordered_remove(line, target_idx)
                c.head.x = byte_idx_to_visual_x(line[:], target_idx)
                c.anchor = c.head
                vis_delta := orig_x - c.head.x
                for &other in editor.cursor {
                    if &other == c do continue
                    if other.head.y == c.head.y && other.head.x > orig_x {
                        other.head.x = max(0, other.head.x - vis_delta)
                        other.anchor = other.head
                    }
                }
            }

        } else if c.head.y > 0 {
            deleted_line_idx := c.head.y
            prev_line_idx := c.head.y - 1

            prev_line := &editor.lines[prev_line_idx]
            prev_visual_x := get_line_visual_width(prev_line[:])

            curr_line := editor.lines[deleted_line_idx]
            append(prev_line, ..curr_line[:])

            delete(curr_line)
            ordered_remove(&editor.lines, deleted_line_idx)

            c.head.y = prev_line_idx
            c.head.x = prev_visual_x

            c.anchor = c.head

            for &other in editor.cursor {
                if &other == c do continue
                if other.head.y == deleted_line_idx {
                    other.head.y = prev_line_idx
                    other.head.x += prev_visual_x
                    other.anchor = other.head
                } else if other.head.y > deleted_line_idx {
                    move_cursor_left()
                }
            }
        }
    }
}

delete_char :: proc() {
    begin_edit()
    if len(editor.lines) == 0 do return
    clamp_cursor()

    if has_any_selection() {
        delete_selection()
        return
    }

    for &c in editor.cursor {
        line := &editor.lines[c.head.y]
        byte_idx := visual_x_to_byte_idx(line[:], c.head.x)
    
        if byte_idx < len(line^) {
            ordered_remove(line, byte_idx)
        } else if c.head.y < len(editor.lines) - 1 {
            next_line := editor.lines[c.head.y + 1]
    
            append(line, ..next_line[:])
    
            delete(next_line)
            ordered_remove(&editor.lines, c.head.y + 1)
        }
    }
}

scroll_viewport :: proc(visible_height: int) {
	if visible_height <= 0 do return

	if editor.row_offset >= len(editor.lines) && len(editor.lines) > 0 {
		editor.row_offset = max(0, len(editor.lines) - 1)
	}

	if editor.cursor[0].head.y < editor.row_offset {
		editor.row_offset = editor.cursor[0].head.y
	}

	if editor.cursor[0].head.y >= editor.row_offset + int(visible_height) {
		editor.row_offset = editor.cursor[0].head.y - int(visible_height) + 1
	}
}

scroll_explorer_viewport :: proc(visible_height: int) {
	if visible_height <= 0 do return

	if editor.explorer.selected < editor.explorer.scroll_offset {
		editor.explorer.scroll_offset = editor.explorer.selected
	}

	if editor.explorer.selected >= editor.explorer.scroll_offset + int(visible_height) {
		editor.explorer.scroll_offset = editor.explorer.selected - int(visible_height) + 1
	}
}

