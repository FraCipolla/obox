package main

import "core:strings"
import "core:fmt"

highlight_text :: proc(y, x, len: int) {
    editor.cursor[0].anchor.y = y
    editor.cursor[0].anchor.x = x
    editor.cursor[0].head.y = y
    editor.cursor[0].head.x = x + len
}

dispatch_find_action :: proc(action: Action) {
    #partial switch a in action {
	case ActionMove:
		#partial switch a.dir {
		case .LEFT:  editor.popup_box.cursor.head.x -= 1
		case .RIGHT: editor.popup_box.cursor.head.x += 1
		case .HOME:  editor.popup_box.cursor.head.x = 0
		case .END:   editor.popup_box.cursor.head.x = len(editor.popup_box.buff)
		}
		clamp_popup_cursor()

	case ActionEscape:
		editor.active_panel = .Editor
		clear(&editor.popup_box.buff)
		editor.popup_box.cursor.head.x = 0

	case ActionEnter:
		y, x, success := execute_find(string(editor.popup_box.buff[:]))
        if success {
            // highlight match
            highlight_text(y, x, len(editor.popup_box.buff))
        }
        
	case ActionDelete:
		if editor.popup_box.cursor.head.x < len(editor.popup_box.buff) {
			ordered_remove(&editor.popup_box.buff, editor.popup_box.cursor.head.x)
		}

	case ActionBackspace:
		if editor.popup_box.cursor.head.x > 0 {
			editor.popup_box.cursor.head.x -= 1
			ordered_remove(&editor.popup_box.buff, editor.popup_box.cursor.head.x)
		}

	case ActionInsertChar:
		if a.r >= 32 && a.r <= 126 {
			inject_at(&editor.popup_box.buff, editor.popup_box.cursor.head.x, u8(a.r))
			editor.popup_box.cursor.head.x += 1
		}
	case:
	}
}

execute_find :: proc(match: string) -> (int, int, bool) {
	if len(match) == 0 do return -1, -1, false
	total_lines := len(editor.lines)
	if total_lines == 0 do return -1, -1, false

	start_y := editor.cursor[0].head.y
	start_x := editor.cursor[0].head.x

	for y in start_y..<total_lines {
		offset_x := 0
		if y == start_y {
			offset_x = start_x
		}

		if offset_x < len(editor.lines[y]) {
			line_slice := string(editor.lines[y][offset_x:])
			find := strings.index(line_slice, match)
			if find != -1 {
				return y, offset_x + find, true
			}
		}
	}

	for y in 0..<start_y {
		line_slice := string(editor.lines[y][:])
		find := strings.index(line_slice, match)
		if find != -1 {
			return y, find, true
		}
	}

	return -1, -1, false
}

draw_find_box :: proc() -> (int, int) {
	if editor.active_panel != .Find do return 0, 0

	box_width: int = 36

	px := max(0, editor.cols - box_width - 1) 
    py := 0

	cmd_len := len(editor.popup_box.buff)
    cmd_cursor := clamp(editor.popup_box.cursor.head.x, 0, cmd_len)

	max_input_w := int(box_width - 4)

	// Horizontal scroll tracking inside popup input
	scroll_offset := 0
	if cmd_cursor >= max_input_w {
		scroll_offset = cmd_cursor - max_input_w + 1
	}

	visible_len := min(cmd_len - scroll_offset, max_input_w)
	display_cmd := ""
	if visible_len > 0 && scroll_offset < cmd_len {
		display_cmd = string(editor.popup_box.buff[scroll_offset:scroll_offset + visible_len])
	}

	set_bg_rgb(30, 34, 42)

	move_cursor(px, py)
	set_fg_rgb(90, 105, 125)
	fmt.print("┌─ Find ")
	for _ in 0 ..< (box_width - 8) {fmt.print("─")}
	fmt.print("┐")

	move_cursor(px, py + 1)
	fmt.print("│ ")
	set_fg_rgb(130, 170, 255)
	fmt.print("")
	set_fg_rgb(230, 235, 245)

	fmt.print(display_cmd)

	pad := max_input_w - len(display_cmd) + 1
	for _ in 0 ..< pad {fmt.print(" ")}

	set_fg_rgb(90, 105, 125)
	fmt.print(" │")

	move_cursor(px, py + 2)
	fmt.print("└")
	for _ in 0 ..< (box_width - 1) {fmt.print("─")}
	fmt.print("┘")

	reset_color()

	input_cursor_x := px + 2 + int(cmd_cursor - scroll_offset)
	input_cursor_y := py + 1
	return input_cursor_x, input_cursor_y
}