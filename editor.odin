package main

import "core:bytes"
import "core:os"
import "core:unicode/utf8"

Panel :: enum {
	Editor,
	CommandPopup,
	Explorer,
}

PopupBox :: struct {
	buff:   [dynamic]u8,
	cursor: Cursor,
}

Editor :: struct {
    keymap:         Keymap,
	cols:           i32,
	rows:           i32,
	row_offset:     int,
	lines:          [dynamic][dynamic]u8,
	cursor:         [dynamic]Cursor,

	explorer_width: i32,
	show_explorer:  bool,
	filepath:       string,
	status_msg:     string,

	active_panel:   Panel,
	cmd_box:        PopupBox,

	explorer:       Explorer,
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
	editor.cmd_box.buff = make([dynamic]u8)
	editor.explorer_width = 24
	editor.show_explorer = true
}

destroy_editor :: proc() {
	for line in editor.lines {
		delete(line)
	}
	delete(editor.lines)
	delete(editor.cmd_box.buff)
    delete(editor.keymap.bindings)
}

// clamp_cursor :: proc() {
// 	if len(editor.lines) == 0 {
// 		editor.cursor[0].head.x = 0
// 		editor.cursor[0].head.y = 0
// 		return
// 	}
// 	editor.cursor[0].head.y = clamp(editor.cursor[0].head.y, 0, len(editor.lines) - 1)
// 	line_len := len(editor.lines[editor.cursor[0].head.y])
// 	editor.cursor[0].head.x = clamp(editor.cursor[0].head.x, 0, line_len)
// }

clamp_cmd_cursor :: proc() {
	editor.cmd_box.cursor.head.x = clamp(editor.cmd_box.cursor.head.x, 0, len(editor.cmd_box.buff))
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

	return true
}

insert_char :: proc(ch: rune) {
    if len(editor.lines) == 0 {
        append(&editor.lines, make([dynamic]u8))
    }

    clamp_cursor()

    line := &editor.lines[editor.cursor[0].head.y]

    byte_idx := visual_x_to_byte_idx(line[:], editor.cursor[0].head.x)
    buf, bytes_len := utf8.encode_rune(ch)

    for i in 0 ..< bytes_len {
        inject_at(line, byte_idx + i, buf[i])
    }

    if ch == '\t' {
        editor.cursor[0].head.x += 4 - (editor.cursor[0].head.x % 4)
        editor.cursor[0].anchor.x += 4 - (editor.cursor[0].head.x % 4)
    } else {
        editor.cursor[0].head.x += 1
        editor.cursor[0].anchor.x += 1
    }
}

insert_newline :: proc() {
	if len(editor.lines) == 0 {
		append(&editor.lines, make([dynamic]u8))
	}

	clamp_cursor()

	curr_line := &editor.lines[editor.cursor[0].head.y]
	new_line := make([dynamic]u8)

	if editor.cursor[0].head.x < len(curr_line) {
		append(&new_line, ..curr_line[editor.cursor[0].head.x:])
		resize(curr_line, editor.cursor[0].head.x)
	}

	inject_at(&editor.lines, editor.cursor[0].head.y + 1, new_line)

	editor.cursor[0].head.y += 1
	editor.cursor[0].head.x = 0
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

backspace_char :: proc() {
    if len(editor.lines) == 0 do return

    clamp_cursor()

    if editor.cursor[0].head.x > 0 {
        line := &editor.lines[editor.cursor[0].head.y]
        
        // 1. Find byte index before moving cursor
        byte_idx := visual_x_to_byte_idx(line[:], editor.cursor[0].head.x)
        
        if byte_idx > 0 {
            target_idx := byte_idx - 1
            deleted_char := line[target_idx]
            
            // Delete the byte at the calculated index
            ordered_remove(line, target_idx)
            
            // Adjust visual cursor.x based on what was actually deleted
            if deleted_char == '\t' {
                // Recalculate exact visual x at target_idx
                editor.cursor[0].head.x = 0
                for i in 0 ..< target_idx {
                    if line[i] == '\t' {
                        editor.cursor[0].head.x += 4 - (editor.cursor[0].head.x % 4)
                    } else {
                        editor.cursor[0].head.x += 1
                    }
                }
            } else {
                editor.cursor[0].head.x -= 1
            }
        }

    } else if editor.cursor[0].head.y > 0 {
        // Line joining logic (remains mostly the same, but calculate visual width)
        prev_line := &editor.lines[editor.cursor[0].head.y - 1]
        
        // Calculate visual length of previous line
        prev_visual_x := 0
        for b in prev_line {
            if b == '\t' {
                prev_visual_x += 4 - (prev_visual_x % 4)
            } else {
                prev_visual_x += 1
            }
        }

        curr_line := editor.lines[editor.cursor[0].head.y]
        append(prev_line, ..curr_line[:])

        delete(curr_line)
        ordered_remove(&editor.lines, editor.cursor[0].head.y)

        editor.cursor[0].head.y -= 1
        editor.cursor[0].head.x = prev_visual_x
    }
}

delete_char :: proc() {
    if len(editor.lines) == 0 do return

    clamp_cursor()

    line := &editor.lines[editor.cursor[0].head.y]
    byte_idx := visual_x_to_byte_idx(line[:], editor.cursor[0].head.x)

    if byte_idx < len(line^) {
        ordered_remove(line, byte_idx)

    } else if editor.cursor[0].head.y < len(editor.lines) - 1 {
        next_line := editor.lines[editor.cursor[0].head.y + 1]

        append(line, ..next_line[:])

        delete(next_line)
        ordered_remove(&editor.lines, editor.cursor[0].head.y + 1)
    }
}

scroll_viewport :: proc(visible_height: i32) {
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

scroll_explorer_viewport :: proc(visible_height: i32) {
	if visible_height <= 0 do return

	if editor.explorer.selected < editor.explorer.scroll_offset {
		editor.explorer.scroll_offset = editor.explorer.selected
	}

	if editor.explorer.selected >= editor.explorer.scroll_offset + int(visible_height) {
		editor.explorer.scroll_offset = editor.explorer.selected - int(visible_height) + 1
	}
}