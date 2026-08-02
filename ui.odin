package main

import "core:fmt"
import "core:strings"
import "core:terminal/ansi"
import "core:unicode/utf8"

// ┊ │

INDENT_COLORS := [4][3]u8{
    { 60,  80, 110}, // Level 0: Soft slate blue
    { 80,  70, 110}, // Level 1: Soft purple
    { 60,  95,  90}, // Level 2: Soft teal
    {100,  80,  60}, // Level 3: Soft amber
}

move_cursor :: proc(x, y: int) {
	fmt.printf("\x1b[%d;%dH", y + 1, x + 1)
}

set_fg_rgb :: proc(r, g, b: u8) {
	fmt.printf("\x1b[38;2;%d;%d;%dm", r, g, b)
}

set_bg_rgb :: proc(r, g, b: u8) {
	fmt.printf("\x1b[48;2;%d;%d;%dm", r, g, b)
}

reset_color :: proc() {
	fmt.print("\x1b[0m")
}

draw_explorer :: proc(width, height: int) {
	if width <= 1 do return

	content_w := int(width) - 1

	truncate_vis :: proc(s: string, max_vis_w: int) -> (string, int) {
		cur_w := 0
		for r, i in s {
			rune_w := 2 if (r == '📁' || r == '📄') else 1
			if cur_w + rune_w > max_vis_w {
				return s[:i], cur_w
			}
			cur_w += rune_w
		}
		return s, cur_w
	}

	for y in 0 ..< height {
		move_cursor(0, y)
		set_bg_rgb(24, 27, 35)

		entry_idx := int(y) + editor.explorer.scroll_offset

		if entry_idx < len(editor.explorer.entries) {
			entry := editor.explorer.entries[entry_idx]

			is_selected := (entry_idx == editor.explorer.selected)
			is_focused := (editor.active_panel == .Explorer)

			if is_selected {
				if is_focused {
					set_bg_rgb(45, 65, 95)
					set_fg_rgb(255, 255, 255)
				} else {
					set_bg_rgb(35, 40, 50)
					set_fg_rgb(140, 150, 165)
				}
			} else {
				set_fg_rgb(170, 180, 195)
			}

			str_to_print, vis_w := truncate_vis(entry.display, content_w)
			fmt.print(str_to_print)

			padding := content_w - vis_w
			for _ in 0 ..< max(0, padding) {
				fmt.print(" ")
			}
		} else {
			for _ in 0 ..< max(0, content_w) {
				fmt.print(" ")
			}
		}

		reset_color()
		set_fg_rgb(60, 68, 80)
		fmt.print("│")
		reset_color()
	}
}

get_line_indent_spaces :: proc(line: string) -> (spaces: int, non_space_idx: int) {
    i := 0
    for i < len(line) {
        if line[i] == ' ' {
            spaces += 1
            i += 1
        } else if line[i] == '\t' {
            spaces += 4 - (spaces % 4)
            i += 1
        } else {
            break
        }
    }
    return spaces, i
}

// Looks ahead to find the indent level for an empty/blank line
get_effective_indent_spaces :: proc(lines: [][dynamic]u8, start_idx: int) -> int {
    for i in start_idx ..< len(lines) {
        line := string(lines[i][:])
        spaces, non_space_idx := get_line_indent_spaces(line)
        
        // Return spaces of the first non-empty line we hit
        if non_space_idx < len(line) {
            return spaces
        }
    }
    return 0
}

render_line_with_indent_guides :: proc(line: string, line_idx: int, lines: [][dynamic]u8) {
    spaces, i := get_line_indent_spaces(line)

    if i >= len(line) {
        spaces = get_effective_indent_spaces(lines, line_idx + 1)
    }

    guides := spaces / 4
    remainder_spaces := spaces % 4

    current_x := 0

    for guide_idx in 0 ..< guides {
        color := INDENT_COLORS[guide_idx % len(INDENT_COLORS)]
        
        for col_offset in 0 ..< 4 {
            vis_x := current_x + col_offset

            if is_selected_in_any_cursor(vis_x, line_idx) {
                fmt.print("\x1b[48;2;60;90;140m") // Selection background
            } else {
                fmt.print("\x1b[49m")             // Default background
            }

            if col_offset == 0 {
                set_fg_rgb(color.r, color.g, color.b)
                fmt.print("│")
            } else {
                fmt.print(" ")
            }
        }
        current_x += 4
    }

    if i < len(line) {
        for _ in 0 ..< remainder_spaces {
            if is_selected_in_any_cursor(current_x, line_idx) {
                fmt.print("\x1b[48;2;60;90;140m")
            } else {
                fmt.print("\x1b[49m")
            }
            fmt.print(" ")
            current_x += 1
        }

        set_fg_rgb(220, 225, 235)
        text_content := line[i:]

        for ch_idx in 0 ..< len(text_content) {
            ch := text_content[ch_idx]

            if is_selected_in_any_cursor(current_x, line_idx) {
                fmt.print("\x1b[48;2;60;90;140m")
            } else {
                fmt.print("\x1b[49m")
            }

            if ch == '\t' {
                tab_size := 4 - (current_x % 4)
                for _ in 0 ..< tab_size {
                    fmt.print(" ")
                }
                current_x += tab_size
            } else {
                fmt.printf("%c", ch)
                current_x += 1
            }
        }
    }

    // Reset background & foreground ANSI styles
    fmt.print("\x1b[0m")
}

draw_code_editor :: proc(start_x, start_y, width, height: int) {
    gutter_width: int = 6

    for y in 0 ..< height {
        move_cursor(start_x, start_y + y)

        line_idx := int(y) + editor.row_offset

        if line_idx < len(editor.lines) {
            line_no := line_idx + 1
            line_str := string(editor.lines[line_idx][:])

            set_fg_rgb(90, 100, 120)
            fmt.printf("%3d │ ", line_no)

            max_text_len := int(width - gutter_width)
            if max_text_len > 0 && len(line_str) > max_text_len {
                line_str = line_str[:max_text_len]
            }

            render_line_with_indent_guides(line_str, line_idx, editor.lines[:])
        } else {
            set_fg_rgb(60, 68, 80)
            fmt.print("  ~")
        }

        fmt.print(ansi.CSI + "K")
        reset_color()
    }

    draw_cursors(start_x, start_y, width, height, gutter_width)
}

draw_cursors :: proc(start_x, start_y, width, height, gutter_width: int) {
    if len(editor.cursor) == 0 do return

    for c, i in editor.cursor {
        if c.head.y < editor.row_offset || c.head.y >= editor.row_offset + height {
            continue
        }

        screen_y := start_y + (c.head.y - editor.row_offset)
        screen_x := start_x + gutter_width + c.head.x

        if screen_x >= start_x + width do continue

        move_cursor(screen_x, screen_y)

        if i == 0 {
            continue
        }

        char_at_cursor: byte = ' '
        if c.head.y < len(editor.lines) {
            line := editor.lines[c.head.y]
            byte_idx := visual_x_to_byte_idx(line[:], c.head.x)
            if byte_idx < len(line) {
                char_at_cursor = line[byte_idx]
            }
        }

		if char_at_cursor == '\t' do char_at_cursor = ' '
		
        fmt.print(ansi.CSI + "7m")
        fmt.printf("%c", char_at_cursor)
        fmt.print(ansi.CSI + "27m")
    }

    // Finally, position the real hardware terminal cursor at cursor[0]
    primary := editor.cursor[0]
    if primary.head.y >= editor.row_offset && primary.head.y < editor.row_offset + height {
        screen_y := start_y + (primary.head.y - editor.row_offset)
        screen_x := start_x + gutter_width + primary.head.x
        move_cursor(screen_x, screen_y)
    }
}

draw_status_bar :: proc(width, height: int) {
	if width <= 0 || height < 2 do return

	move_cursor(0, height - 2)
	set_bg_rgb(50, 90, 160)
	set_fg_rgb(255, 255, 255)

	filename := editor.filepath if len(editor.filepath) > 0 else "[No Name]"

	status := fmt.tprintf(
		" NORMAL MODE │ %s │ Ln %d, Col %d │ %d lines ",
		filename,
		editor.cursor[0].head.y + 1,
		editor.cursor[0].head.x + 1,
		len(editor.lines),
	)

	status_vis_w := utf8.rune_count_in_string(status)
	if status_vis_w > int(width) {
		status = status[:max(0, int(width))]
		status_vis_w = utf8.rune_count_in_string(status)
	}

	fmt.print(status)

	padding1 := int(width) - status_vis_w
	for _ in 0 ..< max(0, padding1) {
		fmt.print(" ")
	}
	reset_color()

	move_cursor(0, height - 1)
	set_bg_rgb(20, 22, 28)

	msg :=
		editor.status_msg if len(editor.status_msg) > 0 else " ^S Save  │  ^B Toggle explorer  │  Alt+Left/Right Resize  │  ^Q Exit"

	set_fg_rgb(140, 150, 160)
	msg_vis_w := utf8.rune_count_in_string(msg)
	if msg_vis_w > int(width) {
		msg = msg[:max(0, int(width))]
		msg_vis_w = utf8.rune_count_in_string(msg)
	}

	fmt.print(msg)

	padding2 := int(width) - msg_vis_w
	for _ in 0 ..< max(0, padding2) {
		fmt.print(" ")
	}
	reset_color()
}

draw_command_box :: proc(cursor_screen_x, cursor_screen_y: int) -> (int, int) {
	if editor.active_panel != .Command do return 0, 0

	box_width: int = 36

	px := cursor_screen_x
	py := cursor_screen_y + 1

	if px + box_width >= editor.cols {
		px = max(0, editor.cols - box_width - 1)
	}

	if py + 2 >= editor.rows - 2 {
		py = max(0, cursor_screen_y - 3)
	}

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
	fmt.print("┌─ Command ")
	for _ in 0 ..< (box_width - 11) {fmt.print("─")}
	fmt.print("┐")

	move_cursor(px, py + 1)
	fmt.print("│ ")
	set_fg_rgb(130, 170, 255)
	fmt.print(":")
	set_fg_rgb(230, 235, 245)

	fmt.print(display_cmd)

	pad := max_input_w - len(display_cmd)
	for _ in 0 ..< pad {fmt.print(" ")}

	set_fg_rgb(90, 105, 125)
	fmt.print(" │")

	move_cursor(px, py + 2)
	fmt.print("└")
	for _ in 0 ..< (box_width - 1) {fmt.print("─")}
	fmt.print("┘")

	reset_color()

	input_cursor_x := px + 3 + int(cmd_cursor - scroll_offset)
	input_cursor_y := py + 1
	return input_cursor_x, input_cursor_y
}

format_entry_display :: proc(entry: ^Explorer_Entry) -> string {
	indent := strings.repeat("  ", entry.depth, context.temp_allocator)

	if entry.is_dir {
		arrow := entry.expanded ? "▾ " : "▸ "
		icon := entry.expanded ? "📂 " : "📁 "
		return fmt.tprintf("%s%s%s%s", indent, arrow, icon, entry.name)
	} else {
		return fmt.tprintf("%s  📄 %s", indent, entry.name)
	}
}

editor_refresh_screen :: proc() {
	update_terminal_size()
	fmt.print(ansi.CSI + ansi.DECTCEM_HIDE)

	explorer_w := editor.show_explorer ? editor.explorer_width : 0
	content_height := max(1, editor.rows - 2)
	gutter_width: int = 6

	scroll_viewport(content_height)
	scroll_explorer_viewport(content_height)

	if editor.show_explorer && explorer_w > 0 {
		draw_explorer(explorer_w, content_height)
		draw_code_editor(explorer_w, 0, editor.cols - explorer_w, content_height)
	} else {
		draw_code_editor(0, 0, editor.cols, content_height)
	}

	draw_status_bar(editor.cols, editor.rows)

	screen_x := explorer_w + gutter_width + int(editor.cursor[0].head.x)
	screen_y := int(editor.cursor[0].head.y - editor.row_offset)

	#partial switch editor.active_panel {
	case .Command:
		popup_cursor_x, popup_cursor_y := draw_command_box(screen_x, screen_y)
		move_cursor(popup_cursor_x, popup_cursor_y)
		fmt.print(ansi.CSI + ansi.DECTCEM_SHOW)
	case .Explorer:
		exp_y := int(editor.explorer.selected - editor.explorer.scroll_offset)
		move_cursor(1, exp_y)
	case .Find:
		popup_cursor_x, popup_cursor_y := draw_find_box()
		move_cursor(popup_cursor_x, popup_cursor_y)
		fmt.print(ansi.CSI + ansi.DECTCEM_SHOW)
	case:
		move_cursor(screen_x, screen_y)
		fmt.print(ansi.CSI + ansi.DECTCEM_SHOW)
	}
}