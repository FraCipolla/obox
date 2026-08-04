package main

import "core:encoding/base64"
import "core:fmt"
import "core:slice"
import "core:strings"

copy_selection_to_clipboard :: proc() {
    text: string

    if has_any_selection() {
        text = get_selected_text(context.temp_allocator)
    } else {
        ensure_primary_cursor()
        c := &editor.cursor[0]
        if c.head.y < len(editor.lines) {
            line := editor.lines[c.head.y][:]
            builder: strings.Builder
            strings.builder_init(&builder, context.temp_allocator)
            strings.write_bytes(&builder, line)
            strings.write_string(&builder, "\n")
            text = strings.to_string(builder)
        }
    }

    if len(text) == 0 do return

    send_osc52(text)

    copy_to_os_clipboard(text)
}

cut_selection_to_clipboard :: proc() {
    copy_selection_to_clipboard()

    if has_any_selection() {
        delete_selection()
    } else {
        ensure_primary_cursor()
        c := &editor.cursor[0]
        if c.head.y < len(editor.lines) {
            delete(editor.lines[c.head.y])
            ordered_remove(&editor.lines, c.head.y)
            if len(editor.lines) == 0 {
                append(&editor.lines, make([dynamic]u8))
            }
            clamp_cursor()
        }
    }
}

paste_from_clipboard :: proc() {
    text := read_os_clipboard(context.temp_allocator)
    if len(text) == 0 do return

    insert_text(text)
}

insert_text :: proc(text: string) {
    if len(text) == 0 do return

    if has_any_selection() {
        delete_selection()
    }

    for ch in text {
        if ch == '\r' do continue
        if ch == '\n' {
            insert_newline()
        } else {
            insert_char(ch)
        }
    }
}

get_selected_text :: proc(allocator := context.temp_allocator) -> string {
    if len(editor.cursor) == 0 do return ""

    builder: strings.Builder
    strings.builder_init(&builder, allocator)

    cursor_indices := make([dynamic]int, 0, len(editor.cursor), context.temp_allocator)
    for i in 0 ..< len(editor.cursor) {
        append(&cursor_indices, i)
    }

    slice.sort_by(cursor_indices[:], proc(i, j: int) -> bool {
        c1, c2 := editor.cursor[i], editor.cursor[j]
        s1, _, _ := get_selection_range(c1)
        s2, _, _ := get_selection_range(c2)
        if s1.y != s2.y do return s1.y < s2.y
        return s1.x < s2.x
    })

    selections_count := 0

    for idx in cursor_indices {
        c := editor.cursor[idx]
        start, end, active := get_selection_range(c)
        if !active do continue

        if selections_count > 0 {
            strings.write_string(&builder, "\n")
        }

        for y := start.y; y <= end.y; y += 1 {
            if y >= len(editor.lines) do break
            line := editor.lines[y][:]

            start_byte := 0
            end_byte := len(line)

            if y == start.y {
                start_byte = visual_x_to_byte_idx(line, start.x)
                start_byte = clamp(start_byte, 0, len(line))
            }
            if y == end.y {
                end_byte = visual_x_to_byte_idx(line, end.x)
                end_byte = clamp(end_byte, 0, len(line))
            }

            if start_byte <= end_byte {
                strings.write_bytes(&builder, line[start_byte:end_byte])
            }

            if y < end.y {
                strings.write_string(&builder, "\n")
            }
        }
        selections_count += 1
    }

    return strings.to_string(builder)
}

send_osc52 :: proc(text: string) {
    encoded := base64.encode(transmute([]u8)text, allocator = context.temp_allocator)
    fmt.printf("\x1b]52;c;%s\x07", encoded)
}