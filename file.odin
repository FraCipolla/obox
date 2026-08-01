package main

import "core:os"
import "core:fmt"

save_file :: proc() -> bool {
    if len(editor.filepath) == 0 {
        editor.status_msg = "Error: No file path specified"
        return false
    }

    tmp_path := fmt.tprintf("%s.tmp", editor.filepath)

    flags := os.O_WRONLY | os.O_CREATE | os.O_TRUNC
    
    fd, open_err := os.open(tmp_path, flags, {.Read_User, .Write_User, .Read_Group, .Read_Other})
    if open_err != 0 {
        editor.status_msg = fmt.tprintf("Save Error: Could not open temp file")
        return false
    }

    total_bytes := 0
    write_success := true

    for line, i in editor.lines {
        if len(line) > 0 {
            n, write_err := os.write(fd, line[:])
            if write_err != 0 {
                write_success = false
                break
            }
            total_bytes += n
        }

        n, write_err := os.write_string(fd, "\n")
        if write_err != 0 {
            write_success = false
            break
        }
        total_bytes += n
    }

    os.close(fd)

    if !write_success {
        os.remove(tmp_path)
        editor.status_msg = "Save Error: Failed writing buffer to disk"
        return false
    }

    rename_err := os.rename(tmp_path, editor.filepath)
    if rename_err != 0 {
        os.remove(tmp_path)
        editor.status_msg = "Save Error: Rename failed"
        return false
    }

    editor.status_msg = fmt.tprintf("\"%s\" %dL, %dB written", editor.filepath, len(editor.lines), total_bytes)
    return true
}