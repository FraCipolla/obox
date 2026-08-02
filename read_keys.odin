package main

import "core:os"

// Enums & Core Types

Key_Code :: enum {
	UNKOWN,									// fallback case
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

// Actions

ActionMove                :: struct { dir: Direction }
ActionSelect              :: struct { dir: Direction }
ActionMoveLine            :: struct { dir: Direction } // MOVE_LINE_UP / DOWN
ActionDuplicateLine       :: struct { dir: Direction } // DOUBLE_LINE_UP / DOWN
ActionAddCursor           :: struct { dir: Direction } // ADD_CURSOR_UP / DOWN

ActionCopy                :: struct {} // COPY
ActionPaste               :: struct {} // PASTE
ActionCut                 :: struct {} // CUT

ActionBackspace           :: struct {} // BACKSPACE
ActionDelete              :: struct {} // DEL
ActionEnter               :: struct {} // ENTER
ActionEscape              :: struct {} 
ActionInsertChar          :: struct { r: rune }

ActionSelectMatch         :: struct { all: bool } // SELECT_NEXT_MATCH / SELECT_ALL_MATCHES
ActionGoToLine            :: struct {}            // GO_TO_LINE
ActionGoToDefinition      :: struct {}            // GO_TO_DEFINITION

ActionOpenCommand    :: struct {} // COMMAND_PANEL
ActionOpenFindPanel       :: struct {} // FIND_PANEL
ActionOpenTerminalPanel   :: struct {} // TERMINAL_PANEL
ActionOpenGitPanel        :: struct {} // GIT_PANEL

ActionToggleExplorer      :: struct {} 
ActionToggleExplorerFocus :: struct {}
ActionExplorerResize      :: struct { delta: int }

ActionComment             :: struct { block: bool } // COMMENT_LINE / BLOCK_COMMENT
ActionSplitEditor         :: struct { vertical: bool } // SPLIT_EDITOR_V / H
ActionRecordMacro         :: struct {} // RECORD_MACRO
ActionPlayMacro           :: struct {} // PLAY_MACRO

ActionQuit                :: struct {}
ActionSave                :: struct {}

Action :: union {
	ActionMove,
	ActionSelect,
	ActionMoveLine,
	ActionDuplicateLine,
	ActionAddCursor,
	ActionCopy,
	ActionPaste,
	ActionCut,
	ActionBackspace,
	ActionDelete,
	ActionEnter,
	ActionEscape,
	ActionInsertChar,
	ActionSelectMatch,
	ActionGoToLine,
	ActionGoToDefinition,
	ActionOpenCommand,
	ActionOpenFindPanel,
	ActionOpenTerminalPanel,
	ActionOpenGitPanel,
	ActionToggleExplorer,
	ActionToggleExplorerFocus,
	ActionExplorerResize,
	ActionComment,
	ActionSplitEditor,
	ActionRecordMacro,
	ActionPlayMacro,
	ActionQuit,
	ActionSave,
}

Keymap :: struct {
	bindings: map[Key_Event]Action,
}

// Keymap Binding

bind_keys :: proc(km: ^Keymap, action: Action, events: ..Key_Event) {
	for e in events {
		km.bindings[e] = action
	}
}

init_keymap :: proc(km: ^Keymap) {
	km.bindings = make(map[Key_Event]Action)

	// System & Global Panels
	km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 'q'}] = ActionQuit{}
	km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 's'}] = ActionSave{}
	km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 'p'}] = ActionOpenCommand{}
	km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 'f'}] = ActionOpenFindPanel{}
	km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = '`'}] = ActionOpenTerminalPanel{}
	km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 'g'}] = ActionOpenGitPanel{}
	km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 'b'}] = ActionToggleExplorer{}
	km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 'e'}] = ActionToggleExplorerFocus{}

	// Explorer Resizing
	km.bindings[{code = .LEFT, modifiers = {.ALT}}]  = ActionExplorerResize{delta = -2}
	km.bindings[{code = .RIGHT, modifiers = {.ALT}}] = ActionExplorerResize{delta = 2}

	// Basic Movement
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

	// Selection (SHIFT + Movement)
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

	// Line Manipulation & Multi-Cursor
	km.bindings[{code = .UP, modifiers = {.ALT}}]         				= ActionMoveLine{dir = .UP}
	km.bindings[{code = .DOWN, modifiers = {.ALT}}]       				= ActionMoveLine{dir = .DOWN}
	km.bindings[{code = .UP, modifiers = {.ALT, .SHIFT}}]   			= ActionDuplicateLine{dir = .UP}
	km.bindings[{code = .DOWN, modifiers = {.ALT, .SHIFT}}] 			= ActionDuplicateLine{dir = .DOWN}
	km.bindings[{code = .UP, modifiers = {.CTRL, .ALT}}]  				= ActionAddCursor{dir = .UP}
	km.bindings[{code = .DOWN, modifiers = {.CTRL, .ALT}}] 				= ActionAddCursor{dir = .DOWN}

	// Clipboard Operations
	km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 'c'}] 			= ActionCopy{}
	km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 'v'}] 			= ActionPaste{}
	km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 'x'}] 			= ActionCut{}

	// Code Navigation & Search
	km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 'd'}]         	= ActionSelectMatch{all = false}
	km.bindings[{code = .RUNE, modifiers = {.CTRL, .SHIFT}, r = 'D'}] 	= ActionSelectMatch{all = true}
	km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 'l'}]         	= ActionGoToLine{}
	km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = ']'}]         	= ActionGoToDefinition{}

	// Formatting & Comments
	km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = '/'}]         	= ActionComment{block = false}
	km.bindings[{code = .RUNE, modifiers = {.CTRL, .SHIFT}, r = '?'}] 	= ActionComment{block = true}

	// Editor Splits & Macros
	km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = '\\'}]        	= ActionSplitEditor{vertical = true}
	km.bindings[{code = .RUNE, modifiers = {.CTRL, .SHIFT}, r = '|'}] 	= ActionSplitEditor{vertical = false}
	km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 'r'}]         	= ActionRecordMacro{}
	km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 'm'}]         	= ActionPlayMacro{}

	// Editing & System
	km.bindings[{code = .BACKSPACE}] 									= ActionBackspace{}
	km.bindings[{code = .DELETE}]    									= ActionDelete{}
	km.bindings[{code = .ENTER}]     									= ActionEnter{}
	km.bindings[{code = .ESCAPE}]    									= ActionEscape{}
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

// Keypress Execution Pipeline

process_keypress :: proc(km: ^Keymap) -> bool {
	event, ok := read_key()
	if !ok do return true

	action, resolved := resolve_action(km, event)
	if !resolved do return true

	switch a in action {
	case ActionQuit:
		return false

	case ActionSave:
		editor.status_msg = "saving..."
		save_file()
		return true

	case ActionOpenCommand:
		editor.active_panel = .Command
		clear(&editor.popup_box.buff)
		editor.popup_box.cursor.head.x = 0
		editor.popup_box.cursor.head.y = 0
		return true

	case ActionOpenFindPanel:
		editor.active_panel = .Find
		clear(&editor.popup_box.buff)
		editor.popup_box.cursor.head.x = 0
		editor.popup_box.cursor.head.y = 0
		return true

	case ActionOpenTerminalPanel:
		editor.active_panel = .Terminal
		return true

	case ActionOpenGitPanel:
		editor.active_panel = .Git
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
			editor.status_msg = "Focus: Explorer"
		}
		return true

	case ActionExplorerResize:
		if editor.show_explorer {
			max_w := max(10, editor.cols / 2)
			editor.explorer_width = clamp(editor.explorer_width + a.delta, 10, max_w)
		}
		return true

	case ActionMove, ActionSelect, ActionMoveLine, ActionDuplicateLine, ActionAddCursor,
	     ActionCopy, ActionPaste, ActionCut, ActionBackspace, ActionDelete, ActionEnter,
	     ActionEscape, ActionInsertChar, ActionSelectMatch, ActionGoToLine, ActionGoToDefinition,
	     ActionComment, ActionSplitEditor, ActionRecordMacro, ActionPlayMacro:
		// Fall through to panel dispatch
	case:
	}

	switch editor.active_panel {
	case .Command: 		dispatch_command_popup_action(action)
	case .Explorer:     dispatch_explorer_action(action)
	case .Editor:       dispatch_editor_action(action)
	case .Find:         dispatch_find_action(action)
	case .Terminal:     // dispatch_terminal_action(action)
	case .Git:          // dispatch_git_action(action)
	}

	return true
}

// Detailed Editor Action Dispatcher

dispatch_editor_action :: proc(action: Action) {
	#partial switch a in action {
	// Movement & Selection
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

	// Line Rearranging & Duplication
	case ActionMoveLine:
		#partial switch a.dir {
		case .UP:						move_line_up()
		case .DOWN:						move_line_down()
		}

	case ActionDuplicateLine:
		#partial switch a.dir {
		case .UP:						duplicate_line_up()
		case .DOWN:						duplicate_line_down()
		}

	case ActionAddCursor:
		#partial switch a.dir {
		case .UP:						add_cursor_above()
		case .DOWN:						add_cursor_below()
		}

	// Clipboard Operations
	case ActionCopy:  // copy_selection_to_clipboard()
	case ActionPaste: // paste_from_clipboard()
	case ActionCut:   // cut_selection_to_clipboard()

	// Text Editing
	case ActionEnter:      				insert_newline()
	case ActionDelete:     				delete_char()
	case ActionBackspace:  				backspace_char()
	case ActionEscape:     				reset_to_single_cursor()
	case ActionInsertChar: 				if a.r >= 32 && a.r <= 126 do insert_char(a.r)

	// Matching & Search
	case ActionSelectMatch:
		if a.all {
			// select_all_matches()
		} else {
			select_next_match()
		}

	case ActionGoToLine:       // prompt_go_to_line()
	case ActionGoToDefinition: // go_to_definition()

	// Comments & Splits
	case ActionComment:
		if a.block {
			// toggle_block_comment()
		} else {
			// toggle_line_comment()
		}

	case ActionSplitEditor:
		if a.vertical {
			// split_editor_vertically()
		} else {
			// split_editor_horizontally()
		}

	// Macros
	case ActionRecordMacro: // toggle_macro_recording()
	case ActionPlayMacro:   // replay_macro()

	case:
	}
}

// Panel Action Handlers

dispatch_command_popup_action :: proc(action: Action) {
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
		execute_command(string(editor.popup_box.buff[:]))
		editor.active_panel = .Editor
		clear(&editor.popup_box.buff)
		editor.popup_box.cursor.head.x = 0

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

// Terminal Input Reader

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
	case '7': return {.CTRL, .ALT}
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