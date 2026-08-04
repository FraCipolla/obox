package main
// prova
import "core:strings"
import "core:fmt"
import "core:os"
import "core:slice"

Explorer_Entry :: struct {
    name:     string,
    fullpath: string,
    is_dir:   bool,
    expanded: bool,
    depth:    int,
    display:  string,
}

Explorer :: struct {
    current_path:   string,
    entries:        [dynamic]Explorer_Entry,
    selected:       int,
    scroll_offset:  int
}

to_lower_ascii :: proc(c: u8) -> u8 {
    if c >= 'A' && c <= 'Z' do return c + 32
    return c
}

string_less_ci :: proc(a, b: string) -> bool {
    min_len := min(len(a), len(b))
    for i in 0..<min_len {
        ca := to_lower_ascii(a[i])
        cb := to_lower_ascii(b[i])
        if ca != cb do return ca < cb
    }
    return len(a) < len(b)
}

explorer_refresh :: proc(e: ^Explorer) {
    // Clear old items
    for entry in e.entries {
        delete(entry.name)
        delete(entry.fullpath)
        delete(entry.display)
    }
    clear(&e.entries)

    path := len(e.current_path) > 0 ? e.current_path : "."

    // Read top level items at depth 0
    top_entries := read_dir_contents(path, 0)
    defer delete(top_entries)

    for entry in top_entries {
        append(&e.entries, entry)
    }
}

read_dir_contents :: proc(dir_path: string, depth: int) -> [dynamic]Explorer_Entry {
    res := make([dynamic]Explorer_Entry)

    f, open_err := os.open(dir_path, os.O_RDONLY)
    if open_err != 0 do return res
    defer os.close(f)

    files, read_err := os.read_dir(f, -1, context.allocator)
    if read_err != 0 do return res
    defer os.file_info_slice_delete(files, context.allocator)

    for fi in files {
        entry := Explorer_Entry{
            name     = strings.clone(fi.name),
            fullpath = strings.clone(fi.fullpath),
            is_dir   = fi.type == .Directory,
            expanded = false,
            depth    = depth,
        }
        entry.display = strings.clone(format_entry_display(&entry))
        append(&res, entry)
    }

    slice.sort_by(res[:], proc(a, b: Explorer_Entry) -> bool {
        if a.is_dir != b.is_dir {
            return a.is_dir
        }
        return string_less_ci(a.name, b.name)
    })

    return res
}

explorer_toggle_expand :: proc(e: ^Explorer, index: int) {
    if index < 0 || index >= len(e.entries) do return

    entry := &e.entries[index]
    if !entry.is_dir do return

    if entry.expanded {
        entry.expanded = false
        
        delete(entry.display)
        entry.display = strings.clone(format_entry_display(entry))

        remove_count := 0
        for i := index + 1; i < len(e.entries); i += 1 {
            if e.entries[i].depth <= entry.depth do break
            remove_count += 1
        }

        for _ in 0..<remove_count {
            child := e.entries[index + 1]
            delete(child.name)
            delete(child.fullpath)
            delete(child.display)
            ordered_remove(&e.entries, index + 1)
        }

    } else {
        entry.expanded = true

        delete(entry.display)
        entry.display = strings.clone(format_entry_display(entry))

        children := read_dir_contents(entry.fullpath, entry.depth + 1)
        defer delete(children)

        for child, i in children {
            inject_at(&e.entries, index + 1 + i, child)
        }
    }
}

find_matching_file :: proc(e: ^Explorer, c: u8) {
    if len(e.entries) == 0 do return

    target_char := to_lower_ascii(c)
    start_idx := (e.selected + 1) % len(e.entries)

    for i in 0..<len(e.entries) {
        idx := (start_idx + i) % len(e.entries)
        entry_name := e.entries[idx].name

        if len(entry_name) > 0 {
            first_char := to_lower_ascii(entry_name[0])
            if first_char == target_char {
                e.selected = idx
                return
            }
        }
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