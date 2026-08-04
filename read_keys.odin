package main

import "core:os"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

// Enums & Core Types

Key_Code :: enum {
    UNKNOWN,
    RUNE,
    UP, DOWN, LEFT, RIGHT,
    HOME, END, PAGE_UP, PAGE_DOWN,
    INSERT, DELETE, BACKSPACE, ENTER, TAB, ESCAPE,
    F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12,
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

ActionOpenCommand    	  :: struct {} // COMMAND_PANEL
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
ActionUndo				  :: struct {}
ActionRedo				  :: struct {}

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
	ActionUndo,
	ActionRedo
}

Keymap :: struct {
	bindings: map[Key_Event]Action,
}

// Keymap Binding

enable_extended_keyboard :: proc() {
    os.write_string(os.stdout, "\x1b[>4;2m\x1b[>1u")
}

disable_extended_keyboard :: proc() {
    os.write_string(os.stdout, "\x1b[<u\x1b[>4;0m")
}

bind_keys :: proc(km: ^Keymap, action: Action, events: ..Key_Event) {
	for e in events {
		km.bindings[e] = action
	}
}

init_keymap :: proc(km: ^Keymap) {
    km.bindings = make(map[Key_Event]Action)

    // System & Global Panels
    km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 'q'}]           = ActionQuit{}
    km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 's'}]           = ActionSave{}
    km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 'z'}]           = ActionUndo{}
    km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 'y'}]           = ActionRedo{}
    km.bindings[{code = .RUNE, modifiers = {.CTRL, .SHIFT}, r = 'z'}]   = ActionRedo{}
    km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 'p'}]           = ActionOpenCommand{}
    km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 'f'}]           = ActionOpenFindPanel{}
    km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = '`'}]           = ActionOpenTerminalPanel{}
    km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 'g'}]           = ActionOpenGitPanel{}
    km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 'b'}]           = ActionToggleExplorer{}
    km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 'e'}]           = ActionToggleExplorerFocus{}

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

    // Selection (SHIFT + Movement) — Use lowercase 'i', 'k', 'j', 'l'
    bind_keys(km, ActionSelect{dir = .UP},
        Key_Event{code = .UP, modifiers = {.SHIFT}},
        Key_Event{code = .RUNE, modifiers = {.ALT, .SHIFT}, r = 'i'},
    )
    bind_keys(km, ActionSelect{dir = .DOWN},
        Key_Event{code = .DOWN, modifiers = {.SHIFT}},
        Key_Event{code = .RUNE, modifiers = {.ALT, .SHIFT}, r = 'k'},
    )
    bind_keys(km, ActionSelect{dir = .LEFT},
        Key_Event{code = .LEFT, modifiers = {.SHIFT}},
        Key_Event{code = .RUNE, modifiers = {.ALT, .SHIFT}, r = 'j'},
    )
    bind_keys(km, ActionSelect{dir = .RIGHT},
        Key_Event{code = .RIGHT, modifiers = {.SHIFT}},
        Key_Event{code = .RUNE, modifiers = {.ALT, .SHIFT}, r = 'l'},
    )
    bind_keys(km, ActionSelect{dir = .HOME}, Key_Event{code = .HOME, modifiers = {.SHIFT}})
    bind_keys(km, ActionSelect{dir = .END},  Key_Event{code = .END, modifiers = {.SHIFT}})

    // Line Manipulation & Multi-Cursor
    km.bindings[{code = .UP, modifiers = {.ALT}}]                = ActionMoveLine{dir = .UP}
    km.bindings[{code = .DOWN, modifiers = {.ALT}}]              = ActionMoveLine{dir = .DOWN}
    km.bindings[{code = .UP, modifiers = {.ALT, .SHIFT}}]        = ActionDuplicateLine{dir = .UP}
    km.bindings[{code = .DOWN, modifiers = {.ALT, .SHIFT}}]      = ActionDuplicateLine{dir = .DOWN}
    km.bindings[{code = .UP, modifiers = {.CTRL, .ALT}}]         = ActionAddCursor{dir = .UP}
    km.bindings[{code = .DOWN, modifiers = {.CTRL, .ALT}}]       = ActionAddCursor{dir = .DOWN}

    // Clipboard Operations
    km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 'c'}]    = ActionCopy{}
    km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 'v'}]    = ActionPaste{}
    km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 'x'}]    = ActionCut{}

    // Code Navigation & Search — Use lowercase 'd'
    km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 'd'}]          = ActionSelectMatch{all = false}
    km.bindings[{code = .RUNE, modifiers = {.CTRL, .SHIFT}, r = 'd'}]  = ActionSelectMatch{all = true}
    km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 'l'}]          = ActionGoToLine{}
    km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = ']'}]          = ActionGoToDefinition{}

    // Formatting & Comments — Use base key '/'
    km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = '/'}]          = ActionComment{block = false}
    km.bindings[{code = .RUNE, modifiers = {.CTRL, .SHIFT}, r = '/'}]  = ActionComment{block = true}

    // Editor Splits & Macros — Use base key '\\'
    km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = '\\'}]         = ActionSplitEditor{vertical = true}
    km.bindings[{code = .RUNE, modifiers = {.CTRL, .SHIFT}, r = '\\'}] = ActionSplitEditor{vertical = false}
    km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 'r'}]          = ActionRecordMacro{}
    km.bindings[{code = .RUNE, modifiers = {.CTRL}, r = 'm'}]          = ActionPlayMacro{}

    // Editing & System
    km.bindings[{code = .BACKSPACE}]                                   = ActionBackspace{}
    km.bindings[{code = .DELETE}]                                      = ActionDelete{}
    km.bindings[{code = .ENTER}]                                       = ActionEnter{}
    km.bindings[{code = .ESCAPE}]                                      = ActionEscape{}
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
	case ActionUndo:
		editor_undo()
		return true
	case ActionRedo:
		editor_redo()
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
	case ActionCopy:					copy_selection_to_clipboard()
	case ActionPaste:					paste_from_clipboard()
	case ActionCut:						cut_selection_to_clipboard()

	// Text Editing
	case ActionEnter:      				insert_newline()
	case ActionDelete:     				delete_char()
	case ActionBackspace:  				backspace_char()
	case ActionEscape:     				reset_to_single_cursor()
	case ActionInsertChar: 				if a.r >= 32 && a.r <= 126 do insert_char(a.r)

	// Matching & Search
	case ActionSelectMatch:
		if a.all do						select_all_matches()
		else do							select_next_match()

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

read_key :: proc() -> (Key_Event, bool) {
    ch, ok := read_byte()
    if !ok do return {}, false

    // Backspace (127 = DEL, 8 = BS / Ctrl+H)
    if ch == 127 || ch == 8 {
        return {code = .BACKSPACE}, true
    }

    // Control Characters (ASCII 0x00 - 0x1F)
    if ch < 32 {
        switch ch {
        case 0:  return {code = .RUNE, modifiers = {.CTRL}, r = ' '}, true
        case 9:  return {code = .TAB}, true
        case 13: return {code = .ENTER}, true
        case 28: return {code = .RUNE, modifiers = {.CTRL}, r = '\\'}, true
        case 29: return {code = .RUNE, modifiers = {.CTRL}, r = ']'}, true
        case 30: return {code = .RUNE, modifiers = {.CTRL}, r = '^'}, true
        case 31: return {code = .RUNE, modifiers = {.CTRL}, r = '/'}, true
        case 27:
            // Process escape sequences
            return parse_escape_sequence()
        case:
            // Legacy Ctrl + A..Z (ASCII 1..26)
            return {code = .RUNE, modifiers = {.CTRL}, r = rune('a' + ch - 1)}, true
        }
    }

    // UTF-8 Multibyte Characters
    if ch >= 128 {
        r, u_ok := read_utf8_rune(ch)
        if u_ok {
            return {code = .RUNE, r = r}, true
        }
        return {}, false
    }

    // Standard Printable ASCII Character
    return {code = .RUNE, r = rune(ch)}, true
}

// --- Internal Parsing Logic ---

@(private)
read_byte :: proc() -> (byte, bool) {
    buf: [1]byte
    n, _ := os.read(os.stdin, buf[:])
    if n <= 0 do return 0, false
    return buf[0], true
}

@(private)
parse_escape_sequence :: proc() -> (Key_Event, bool) {
    b1, ok := read_byte()
    if !ok do return {code = .ESCAPE}, true // Single ESC key press

    if b1 == '[' {
        return parse_csi()
    } else if b1 == 'O' {
        // SS3 sequences (e.g. F1-F4)
        b2, b2_ok := read_byte()
        if !b2_ok do return {code = .ESCAPE}, true

        switch b2 {
        case 'P': return {code = .F1}, true
        case 'Q': return {code = .F2}, true
        case 'R': return {code = .F3}, true
        case 'S': return {code = .F4}, true
        case 'H': return {code = .HOME}, true
        case 'F': return {code = .END}, true
        case:     return {code = .ESCAPE}, true
        }
    } else {
        // Alt + Printable key (e.g., \x1b a)
        mods: Key_Modifiers = {.ALT}
        r := rune(b1)
        if b1 >= 'A' && b1 <= 'Z' {
            mods += {.SHIFT}
        }
        return {code = .RUNE, modifiers = mods, r = r}, true
    }
}

@(private)
parse_csi :: proc() -> (Key_Event, bool) {
    param_buf: [32]byte
    param_len := 0
    term_byte: byte = 0

    // Read CSI body until terminal byte ('@' through '~')
    for param_len < len(param_buf) {
        b, ok := read_byte()
        if !ok do break

        if b >= '@' && b <= '~' {
            term_byte = b
            break
        }

        param_buf[param_len] = b
        param_len += 1
    }

    if term_byte == 0 do return {code = .ESCAPE}, true

    // Parse parameters delimited by ';'
    param_str := string(param_buf[:param_len])
    params: [8]int
    num_params := 0

    if len(param_str) > 0 {
        clean_str := param_str
        if clean_str[0] == '?' || clean_str[0] == '>' {
            clean_str = clean_str[1:]
        }

        parts := strings.split(clean_str, ";", context.temp_allocator)
        for p in parts {
            if num_params >= len(params) do break
            val, parse_ok := strconv.parse_int(p)
            if parse_ok {
                params[num_params] = val
                num_params += 1
            }
        }
    }

    switch term_byte {
    case 'u':
        // CSI u Protocol: \x1b[<keycode>;<modifiers>u
        if num_params >= 1 {
            key_code := params[0]
            mod_code := num_params >= 2 ? params[1] : 1
            return map_csi_u_key(key_code, parse_csi_mod(mod_code))
        }

    case '~':
        // Tilde sequences & modifyOtherKeys: \x1b[27;<mod>;<key>~
        if num_params >= 3 && params[0] == 27 {
            return map_csi_u_key(params[2], parse_csi_mod(params[1]))
        } else if num_params >= 1 {
            mod_code := num_params >= 2 ? params[1] : 1
            return map_tilde_key(params[0], parse_csi_mod(mod_code))
        }

    case 'A', 'B', 'C', 'D', 'H', 'F':
        // Arrow keys & Home/End (\x1b[A or \x1b[1;<mod>A)
        mod_code := num_params >= 2 ? params[1] : 1
        code: Key_Code
        switch term_byte {
        case 'A': code = .UP
        case 'B': code = .DOWN
        case 'C': code = .RIGHT
        case 'D': code = .LEFT
        case 'H': code = .HOME
        case 'F': code = .END
        }
        return {code = code, modifiers = parse_csi_mod(mod_code)}, true
    }

    return {code = .ESCAPE}, true
}

// --- Helper Functions ---

@(private)
utf8_byte_count :: proc(b: byte) -> int {
    if b < 0x80           do return 1 // 0xxxxxxx
    if (b & 0xE0) == 0xC0 do return 2 // 110xxxxx
    if (b & 0xF0) == 0xE0 do return 3 // 1110xxxx
    if (b & 0xF8) == 0xF0 do return 4 // 11110xxx
    return 1 // Fallback for invalid lead bytes
}

@(private)
read_utf8_rune :: proc(first_byte: byte) -> (rune, bool) {
    buf: [4]byte
    buf[0] = first_byte

    need := utf8_byte_count(first_byte)
    if need <= 1 do return rune(first_byte), true

    for i := 1; i < need; i += 1 {
        b, ok := read_byte()
        if !ok do return 0, false
        buf[i] = b
    }

    r, _ := utf8.decode_rune(buf[:need])
    return r, true
}

@(private)
parse_csi_mod :: proc(mod_val: int) -> Key_Modifiers {
    mods: Key_Modifiers
    m := mod_val - 1
    if (m & 1) != 0 do mods += {.SHIFT}
    if (m & 2) != 0 do mods += {.ALT}
    if (m & 4) != 0 do mods += {.CTRL}
    return mods
}

@(private)
map_csi_u_key :: proc(key_code: int, mods: Key_Modifiers) -> (Key_Event, bool) {
    switch key_code {
    case 13:      return {code = .ENTER, modifiers = mods}, true
    case 9:       return {code = .TAB, modifiers = mods}, true
    case 27:      return {code = .ESCAPE, modifiers = mods}, true
    case 127, 8:  return {code = .BACKSPACE, modifiers = mods}, true
    }

    return {code = .RUNE, modifiers = mods, r = rune(key_code)}, true
}

@(private)
map_tilde_key :: proc(key_code: int, mods: Key_Modifiers) -> (Key_Event, bool) {
    code: Key_Code = .UNKNOWN
    switch key_code {
    case 1, 7: code = .HOME
    case 2:    code = .INSERT
    case 3:    code = .DELETE
    case 4, 8: code = .END
    case 5:    code = .PAGE_UP
    case 6:    code = .PAGE_DOWN
    case 11:   code = .F1
    case 12:   code = .F2
    case 13:   code = .F3
    case 14:   code = .F4
    case 15:   code = .F5
    case 17:   code = .F6
    case 18:   code = .F7
    case 19:   code = .F8
    case 20:   code = .F9
    case 21:   code = .F10
    case 23:   code = .F11
    case 24:   code = .F12
    }

    if code != .UNKNOWN {
        return {code = code, modifiers = mods}, true
    }
    return {code = .UNKNOWN}, true
}