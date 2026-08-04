package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

SubFlags :: struct {
    case_insensitive: bool, // /i
    whole_word:       bool, // /w
    global_on_line:   bool, // /g
    max_replacements: int,  // /1, /2, /5... (0 means unlimited)
}

LineScope :: struct {
    start_line: int, // 0-indexed
    end_line:   int, // 0-indexed (inclusive)
}

split_once_by_byte :: proc(s: string, b: byte) -> (head, tail: string, ok: bool) {
    idx := strings.index_byte(s, b)
    if idx == -1 do return s, "", false
    return s[:idx], s[idx + 1:], true
}

is_word_char :: proc(b: byte) -> bool {
    return (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') || (b >= '0' && b <= '9') || b == '_'
}

parse_token :: proc(input: string) -> (token, rest: string, ok: bool) {
    src := strings.trim_space(input)
    if len(src) == 0 do return "", "", false

    quote_char := src[0]
    if quote_char == '\'' || quote_char == '"' {
        end_quote := strings.index_byte(src[1:], quote_char)
        if end_quote == -1 do return "", "", false
        
        token = src[1 : end_quote + 1]
        rest = src[end_quote + 2:]
        return token, rest, true
    } else {
        end_idx := -1
        for b, i in src {
            if b == '=' || b == '/' {
                end_idx = i
                break
            }
        }
        if end_idx == -1 {
            return src, "", true
        }
        token = strings.trim_space(src[:end_idx])
        rest = src[end_idx:]
        return token, rest, true
    }
}

parse_substitution_cmd :: proc(
    cmd: string, 
    current_line: int, 
    total_lines: int,
) -> (target, replacement: string, scope: LineScope, flags: SubFlags, ok: bool) {
    
    dollar_idx := strings.index_byte(cmd, '$')
    if dollar_idx == -1 do return "", "", {}, {}, false

    scope_str := strings.trim_space(cmd[:dollar_idx])
    parsed_scope := LineScope{0, max(0, total_lines - 1)}

    if len(scope_str) > 0 {
        if scope_str == "." {
            parsed_scope = LineScope{current_line, current_line}
        } else if scope_str == "%" {
            parsed_scope = LineScope{0, max(0, total_lines - 1)}
        } else if strings.contains(scope_str, ",") {
            if head, tail, s_ok := split_once_by_byte(scope_str, ','); s_ok {
                start, s_num_ok := strconv.parse_int(head)
                end,   e_num_ok := strconv.parse_int(tail)
                if s_num_ok && e_num_ok {
                    parsed_scope.start_line = clamp(start - 1, 0, max(0, total_lines - 1))
                    parsed_scope.end_line   = clamp(end - 1, parsed_scope.start_line, max(0, total_lines - 1))
                }
            }
        }
    }

    body := cmd[dollar_idx + 1:]
    
    t, rest1, t_ok := parse_token(body)
    if !t_ok || len(t) == 0 do return "", "", {}, {}, false

    rest1 = strings.trim_space(rest1)
    if !strings.has_prefix(rest1, "=") do return "", "", {}, {}, false
    after_eq := rest1[1:]

    r, rest2, r_ok := parse_token(after_eq)
    if !r_ok do return "", "", {}, {}, false

    parsed_flags := SubFlags{
        case_insensitive = false,
        whole_word       = false,
        global_on_line   = true,
        max_replacements = 0, // 0 = unlimited
    }

    rest2 = strings.trim_space(rest2)
    if strings.has_prefix(rest2, "/") {
        flag_str := rest2[1:]
        
        num_buf: strings.Builder
        strings.builder_init(&num_buf, context.temp_allocator)

        for ch in flag_str {
            switch ch {
            case 'i': parsed_flags.case_insensitive = true
            case 'w': parsed_flags.whole_word = true
            case 'g': parsed_flags.global_on_line = true
            case '0'..='9':
                strings.write_rune(&num_buf, ch)
            }
        }

        // Parse explicit numeric count if provided (editor.g., /1, /2, /10)
        if strings.builder_len(num_buf) > 0 {
            if val, num_ok := strconv.parse_int(strings.to_string(num_buf)); num_ok && val > 0 {
                parsed_flags.max_replacements = val
            }
        }
    }

    return t, r, parsed_scope, parsed_flags, true
}

replace_in_line :: proc(
    src, target, replacement: string, 
    flags: SubFlags, 
    max_line_matches: int, // -1 means no limit for this line
    allocator := context.allocator,
) -> (result: string, count: int) {
    if len(target) == 0 do return strings.clone(src, allocator), 0

    target_len := len(target)
    src_len := len(src)

    lower_src := strings.to_lower(src, context.temp_allocator) if flags.case_insensitive else src
    lower_target := strings.to_lower(target, context.temp_allocator) if flags.case_insensitive else target

    b := strings.builder_make(allocator)
    i := 0

    for i < src_len {
        if max_line_matches >= 0 && count >= max_line_matches {
            strings.write_string(&b, src[i:])
            break
        }

        match := false
        if i + target_len <= src_len {
            if lower_src[i : i + target_len] == lower_target {
                match = true

                if flags.whole_word {
                    is_start := (i == 0) || !is_word_char(src[i - 1])
                    is_end   := (i + target_len == src_len) || !is_word_char(src[i + target_len])
                    if !is_start || !is_end do match = false
                }
            }
        }

        if match {
            strings.write_string(&b, replacement)
            i += target_len
            count += 1
        } else {
            strings.write_byte(&b, src[i])
            i += 1
        }
    }

    return strings.to_string(b), count
}

execute_command :: proc(cmd: string) {
    if len(cmd) == 0 do return

    current_line := editor.cursor[0].head.y
    total_lines  := len(editor.lines)

    if total_lines == 0 {
        editor.status_msg = "Buffer is empty"
        return
    }

    target, replacement, scope, flags, ok := parse_substitution_cmd(cmd, current_line, total_lines)
    if !ok {
        editor.status_msg = "Syntax Error: Use [scope]$target=replacement[/flags]"
        return
    }

    total_replacements := 0

    for line_idx in scope.start_line..=scope.end_line {
        if flags.max_replacements > 0 && total_replacements >= flags.max_replacements {
            break
        }

        line_ref := &editor.lines[line_idx]
        line_str := string(line_ref[:])

        max_allowed := -1
        if flags.max_replacements > 0 {
            max_allowed = flags.max_replacements - total_replacements
        }

        new_str, count := replace_in_line(
            line_str, target, replacement, flags, max_allowed, context.temp_allocator,
        )

        if count > 0 {
            total_replacements += count
            clear(line_ref)
            append(line_ref, ..transmute([]u8)new_str)
        }
    }

    editor.status_msg = fmt.tprintf(
        "Substituted %d occurrence(s) [Lines %d-%d]: '%s' -> '%s'", 
        total_replacements, scope.start_line + 1, scope.end_line + 1, target, replacement,
    )
}

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