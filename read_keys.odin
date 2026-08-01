package main

import "core:os"

// --- Enums & Core Types ---

Key_Code :: enum {
	UNKOWN,
	BACKSPACE, ENTER, ESCAPE, TAB, DELETE,
	UP, DOWN, LEFT, RIGHT,
	PAGE_UP, PAGE_DOWN, HOME, END,
	RUNE,
}

Key_Mod :: enum { SHIFT, CTRL, ALT }
Key_Modifiers :: bit_set[Key_Mod; u8]

Key_Event :: struct {
	code:      Key_Code,
	modifiers: Key_Modifiers,
	r:         rune,
}

Direction :: enum { UP, DOWN, LEFT, RIGHT, HOME, END, PAGE_UP, PAGE_DOWN }

// --- Actions ---

ActionMove                :: struct { dir: Direction }
ActionSelect              :: struct { dir: Direction }
ActionExplorerResize      :: struct { delta: i32 }
ActionBackspace           :: struct {}
ActionDelete              :: struct {}
ActionEnter               :: struct {}
ActionEscape              :: struct {}
ActionInsertChar          :: struct { r: rune }
ActionQuit                :: struct {}
ActionSave                :: struct {}
ActionOpenCommandPopup    :: struct {}
ActionToggleExplorer      :: struct {}
ActionToggleExplorerFocus :: struct {}

Action :: union {
	ActionMove,
	ActionSelect,
	ActionExplorerResize,
	ActionBackspace,
	ActionDelete,
	ActionEnter,
	ActionEscape,
	ActionInsertChar,
	ActionQuit,
	ActionSave,
	ActionOpenCommandPopup,
	ActionToggleExplorer,
	ActionToggleExplorerFocus,
}

Keymap :: struct {
	bindings: map[Key_Event]Action,
}

// --- Keymap Binding ---

bind_keys :: proc(km: ^Keymap, action: Action, events: ..Key_Event) {
	for e in events {
		km.bindings[e] = action
	}
}

init_keymap :: proc(km: ^Keymap) {
	km.bindings = make(map[Key_Event]Action)

	// Global / Shortcuts
	km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 'q'}] = ActionQuit{}
	km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 'p'}] = ActionOpenCommandPopup{}
	km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 's'}] = ActionSave{}
	km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 'b'}] = ActionToggleExplorer{}
	km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 'e'}] = ActionToggleExplorerFocus{}

	// Explorer Resizing
	km.bindings[{code = .LEFT, modifiers = {.ALT}}]  = ActionExplorerResize{delta = -2}
	km.bindings[{code = .RIGHT, modifiers = {.ALT}}] = ActionExplorerResize{delta = 2}

	// Normal Navigation
	bind_keys(km, ActionMove{dir = .UP},
		Key_Event{code = .UP},
		Key_Event{code = .RUNE, modifiers = {.ALT}, r = 'i'},
	)
	bind_keys(km, ActionMove{dir = .DOWN},
		Key_Event{code = .DOWN},
		Key_Event{code = .RUNE, modifiers = {.ALT}, r = 'k'},
	)
	bind_keys(km, ActionMove{dir = .LEFT},
		Key_Event{code = .LEFT},
		Key_Event{code = .RUNE, modifiers = {.ALT}, r = 'j'},
	)
	bind_keys(km, ActionMove{dir = .RIGHT},
		Key_Event{code = .RIGHT},
		Key_Event{code = .RUNE, modifiers = {.ALT}, r = 'l'},
	)
	bind_keys(km, ActionMove{dir = .HOME}, Key_Event{code = .HOME})
	bind_keys(km, ActionMove{dir = .END},  Key_Event{code = .END})

	// Selection Navigation (SHIFT + Movement)
	bind_keys(km, ActionSelect{dir = .UP},
		Key_Event{code = .UP, modifiers = {.SHIFT}},
		Key_Event{code = .RUNE, modifiers = {.ALT, .SHIFT}, r = 'I'},
	)
	bind_keys(km, ActionSelect{dir = .DOWN},
		Key_Event{code = .DOWN, modifiers = {.SHIFT}},
		Key_Event{code = .RUNE, modifiers = {.ALT, .SHIFT}, r = 'K'},
	)
	bind_keys(km, ActionSelect{dir = .LEFT},
		Key_Event{code = .LEFT, modifiers = {.SHIFT}},
		Key_Event{code = .RUNE, modifiers = {.ALT, .SHIFT}, r = 'J'},
	)
	bind_keys(km, ActionSelect{dir = .RIGHT},
		Key_Event{code = .RIGHT, modifiers = {.SHIFT}},
		Key_Event{code = .RUNE, modifiers = {.ALT, .SHIFT}, r = 'L'},
	)
	bind_keys(km, ActionSelect{dir = .HOME}, Key_Event{code = .HOME, modifiers = {.SHIFT}})
	bind_keys(km, ActionSelect{dir = .END},  Key_Event{code = .END, modifiers = {.SHIFT}})

	// Editing & System
	km.bindings[{code = .BACKSPACE}] = ActionBackspace{}
	km.bindings[{code = .DELETE}]    = ActionDelete{}
	km.bindings[{code = .ENTER}]     = ActionEnter{}
	km.bindings[{code = .ESCAPE}]    = ActionEscape{}
}

get_action :: proc(km: ^Keymap, event: Key_Event) -> (Action, bool) {
	action, ok := km.bindings[event]
	return action, ok
}

resolve_action :: proc(km: ^Keymap, event: Key_Event) -> (Action, bool) {
	if action, ok := get_action(km, event); ok {
		return action, true
	}
	// Fallback for regular typing (no CTRL/ALT modifier)
	if event.code == .RUNE && !(.ALT in event.modifiers) && !(.CTRL in event.modifiers) {
		return ActionInsertChar{r = event.r}, true
	}
	return nil, false
}

// --- Keypress Execution Pipeline ---

process_keypress :: proc(km: ^Keymap) -> bool {
	event, ok := read_key()
	if !ok do return true

	action, resolved := resolve_action(km, event)
	if !resolved do return true

	// 1. Global Commands
	switch a in action {
	case ActionQuit:
		return false

	case ActionOpenCommandPopup:
		editor.active_panel = .CommandPopup
		clear(&editor.cmd_box.buff)
		editor.cmd_box.cursor.head.x = 0
		editor.cmd_box.cursor.head.y = 0
		return true

	case ActionSave:
		editor.status_msg = "saving..."
		save_file()
		return true

	case ActionToggleExplorer:
		editor.show_explorer = !editor.show_explorer
		return true

	case ActionToggleExplorerFocus:
		if editor.active_panel == .Explorer {
			editor.active_panel = .Editor
			editor.status_msg = "Focus: Editor"
		} else {
			editor.active_panel = .Explorer
			editor.status_msg = "Focus: Explorer (Use Up/Down, Enter to select, Esc to return)"
		}
		return true

	case ActionExplorerResize:
		if editor.show_explorer {
			max_w := max(10, editor.cols / 2)
			editor.explorer_width = clamp(editor.explorer_width + a.delta, 10, max_w)
		}
		return true

	case ActionMove, ActionSelect, ActionEnter, ActionEscape, ActionBackspace, ActionDelete, ActionInsertChar:
		// Fall through to panel dispatch
	case:
	}

	// 2. Active Panel Handler
	switch editor.active_panel {
	case .CommandPopup:
		dispatch_command_popup_action(action)
	case .Explorer:
		dispatch_explorer_action(action)
	case .Editor:
		dispatch_editor_action(action)
	}

	return true
}

// --- Panel Action Handlers ---

dispatch_command_popup_action :: proc(action: Action) {
	#partial switch a in action {
	case ActionMove:
		#partial switch a.dir {
		case .LEFT:  editor.cmd_box.cursor.head.x -= 1
		case .RIGHT: editor.cmd_box.cursor.head.x += 1
		case .HOME:  editor.cmd_box.cursor.head.x = 0
		case .END:   editor.cmd_box.cursor.head.x = len(editor.cmd_box.buff)
		}
		clamp_cmd_cursor()

	case ActionEscape:
		editor.active_panel = .Editor
		clear(&editor.cmd_box.buff)
		editor.cmd_box.cursor.head.x = 0

	case ActionEnter:
		execute_command(string(editor.cmd_box.buff[:]))
		editor.active_panel = .Editor
		clear(&editor.cmd_box.buff)
		editor.cmd_box.cursor.head.x = 0

	case ActionDelete:
		if editor.cmd_box.cursor.head.x < len(editor.cmd_box.buff) {
			ordered_remove(&editor.cmd_box.buff, editor.cmd_box.cursor.head.x)
		}

	case ActionBackspace:
		if editor.cmd_box.cursor.head.x > 0 {
			editor.cmd_box.cursor.head.x -= 1
			ordered_remove(&editor.cmd_box.buff, editor.cmd_box.cursor.head.x)
		}

	case ActionInsertChar:
		if a.r >= 32 && a.r <= 126 {
			inject_at(&editor.cmd_box.buff, editor.cmd_box.cursor.head.x, u8(a.r))
			editor.cmd_box.cursor.head.x += 1
		}
	case:
	}
}

dispatch_explorer_action :: proc(action: Action) {
	#partial switch a in action {
	case ActionMove:
		if len(editor.explorer.entries) == 0 do return
		#partial switch a.dir {
		case .UP:
			editor.explorer.selected = clamp(editor.explorer.selected - 1, 0, len(editor.explorer.entries) - 1)
		case .DOWN:
			editor.explorer.selected = clamp(editor.explorer.selected + 1, 0, len(editor.explorer.entries) - 1)
		}

	case ActionEnter:
		sel := editor.explorer.selected
		if sel >= 0 && sel < len(editor.explorer.entries) {
			entry := editor.explorer.entries[sel]
			if !entry.is_dir {
				editor.filepath = entry.fullpath
				editor_open_file(entry.fullpath)
				editor.active_panel = .Editor
			} else {
				explorer_toggle_expand(&editor.explorer, sel)
			}
		}

	case ActionInsertChar:
		if a.r >= 32 && a.r <= 126 {
			find_matching_file(&editor.explorer, u8(a.r))
		}
	case:
	}
}

dispatch_editor_action :: proc(action: Action) {
	#partial switch a in action {
	case ActionMove:
		#partial switch a.dir {
		case .UP:        move_cursor_up(shift_held = false)
		case .DOWN:      move_cursor_down(shift_held = false)
		case .LEFT:      move_cursor_left(shift_held = false)
		case .RIGHT:     move_cursor_right(shift_held = false)
		case .HOME:      move_cursor_home(shift_held = false)
		case .END:       move_cursor_end(shift_held = false)
		case .PAGE_UP, .PAGE_DOWN:
		}

	case ActionSelect:
		#partial switch a.dir {
		case .UP:        move_cursor_up(shift_held = true)
		case .DOWN:      move_cursor_down(shift_held = true)
		case .LEFT:      move_cursor_left(shift_held = true)
		case .RIGHT:     move_cursor_right(shift_held = true)
		case .HOME:      move_cursor_home(shift_held = true)
		case .END:       move_cursor_end(shift_held = true)
		case .PAGE_UP, .PAGE_DOWN:
		}

	case ActionEnter:      insert_newline()
	case ActionDelete:     delete_char()
	case ActionBackspace:  backspace_char()
	case ActionEscape:     reset_to_single_cursor()
	case ActionInsertChar: if a.r >= 32 && a.r <= 126 do insert_char(a.r)
	case:
	}
}

// --- Terminal Input Reader ---

read_key :: proc() -> (Key_Event, bool) {
	buf: [8]byte
	bytes_read, _ := os.read(os.stdin, buf[:1])
	if bytes_read <= 0 do return {}, false

	ch := buf[0]

	if ch == 127 || ch == 8 do return {code = .BACKSPACE}, true

	if ch > 0 && ch < 27 {
		if ch == 9  do return {code = .TAB}, true
		if ch == 13 do return {code = .ENTER}, true
		return {code = .RUNE, modifiers = {.CTRL}, r = rune(ch + 96)}, true
	}

	if ch >= 128 && ch < 255 {
		return {code = .RUNE, modifiers = {.ALT}, r = rune(ch & 0x7f)}, true
	}

	if ch == 27 {
		// Read all remaining sequence bytes in one batch
		n_seq, _ := os.read(os.stdin, buf[1:])
		if n_seq <= 0 do return {code = .ESCAPE}, true

		if buf[1] == '[' {
			// Modified arrow keys: \x1b[1;2A (Shift+Up), \x1b[1;5A (Ctrl+Up), etc.
			if n_seq >= 4 && buf[2] == '1' && buf[3] == ';' {
				mod := parse_mod(buf[4])
				dir := parse_dir(buf[5])
				return {code = dir, modifiers = mod}, true
			}

			// Modified tilde keys: \x1b[3;2~ (Shift+Delete), etc.
			if n_seq >= 4 && buf[2] >= '0' && buf[2] <= '9' && buf[3] == ';' {
				mod := parse_mod(buf[4])
				code: Key_Code = .UNKOWN
				switch buf[2] {
				case '3': code = .DELETE
				case '5': code = .PAGE_UP
				case '6': code = .PAGE_DOWN
				case '1', '7': code = .HOME
				case '4', '8': code = .END
				case:
				}
				if code != .UNKOWN do return {code = code, modifiers = mod}, true
			}

			// Simple tilde escape sequences: \x1b[3~ (Delete), \x1b[5~ (PageUp), etc.
			if n_seq >= 2 && buf[2] >= '0' && buf[2] <= '9' {
				if n_seq >= 3 && buf[3] == '~' {
					switch buf[2] {
					case '3': return {code = .DELETE}, true
					case '5': return {code = .PAGE_UP}, true
					case '6': return {code = .PAGE_DOWN}, true
					case '1', '7': return {code = .HOME}, true
					case '4', '8': return {code = .END}, true
					case:
					}
				}
			}

			// Simple arrow keys: \x1b[A, \x1b[B, etc.
			if n_seq >= 2 {
				code := parse_dir(buf[2])
				if code != .UNKOWN do return {code = code}, true
			}
		} else if buf[1] == 'O' {
			if n_seq >= 2 {
				switch buf[2] {
				case 'H': return {code = .HOME}, true
				case 'F': return {code = .END}, true
				case:
				}
			}
		} else if buf[1] >= 'A' && buf[1] <= 'Z' {
			// ALT + SHIFT + Uppercase Letter
			return {code = .RUNE, modifiers = {.ALT, .SHIFT}, r = rune(buf[1])}, true
		} else if (buf[1] >= 'a' && buf[1] <= 'z') || (buf[1] >= '0' && buf[1] <= '9') {
			// ALT + Lowercase Letter / Digit
			return {code = .RUNE, modifiers = {.ALT}, r = rune(buf[1])}, true
		}

		return {code = .ESCAPE}, true
	}

	return {code = .RUNE, r = rune(ch)}, true
}

@(private)
parse_mod :: proc(b: byte) -> Key_Modifiers {
	switch b {
	case '2': return {.SHIFT}
	case '3': return {.ALT}
	case '4': return {.ALT, .SHIFT}
	case '5': return {.CTRL}
	case '6': return {.CTRL, .SHIFT}
	case '7': return {.ALT, .SHIFT}
	case '8': return {.CTRL, .ALT, .SHIFT}
	case:
	}
	return {}
}

@(private)
parse_dir :: proc(b: byte) -> Key_Code {
	switch b {
	case 'A': return .UP
	case 'B': return .DOWN
	case 'C': return .RIGHT
	case 'D': return .LEFT
	case 'H': return .HOME
	case 'F': return .END
	case:
	}
	return .UNKOWN
}