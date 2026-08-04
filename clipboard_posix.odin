#+build !windows
package main

import "core:c/libc"
import "core:os"
import "core:strings"

foreign import lib_c "system:c"
@(default_calling_convention = "c")
foreign lib_c {
    popen  :: proc(command: cstring, mode: cstring) -> ^libc.FILE ---
    pclose :: proc(stream: ^libc.FILE) -> i32 ---
}

copy_to_os_clipboard :: proc(text: string) {
    when ODIN_OS == .Darwin {
        pipe_to_cli("pbcopy", text)
    } else {
        if is_wayland() {
            pipe_to_cli("wl-copy", text)
        } else {
            pipe_to_cli("xclip -selection clipboard", text)
        }
    }
}

read_os_clipboard :: proc(allocator := context.temp_allocator) -> string {
    when ODIN_OS == .Darwin {
        return read_from_cli("pbpaste", allocator)
    } else {
        if is_wayland() {
            return read_from_cli("wl-paste -n", allocator)
        } else {
            return read_from_cli("xclip -selection clipboard -o", allocator)
        }
    }
}

is_wayland :: proc() -> bool {
    _, found := os.lookup_env("WAYLAND_DISPLAY", context.temp_allocator)
    return found
}

pipe_to_cli :: proc(cmd: string, text: string) -> bool {
    cmd_cstring := strings.clone_to_cstring(cmd, context.temp_allocator)
    pipe := popen(cmd_cstring, "w")
    if pipe == nil do return false

    if len(text) > 0 {
        libc.fwrite(raw_data(text), 1, len(text), pipe)
    }

    return pclose(pipe) == 0
}

read_from_cli :: proc(cmd: string, allocator := context.temp_allocator) -> string {
    cmd_cstring := strings.clone_to_cstring(cmd, context.temp_allocator)
    pipe := popen(cmd_cstring, "r")
    if pipe == nil do return ""

    builder: strings.Builder
    strings.builder_init(&builder, allocator)

    buf: [512]byte
    for {
        bytes_read := libc.fread(&buf[0], 1, size_of(buf), pipe)
        if bytes_read == 0 do break
        strings.write_bytes(&builder, buf[:bytes_read])
    }

    pclose(pipe)

    res := strings.to_string(builder)
    return strings.trim_right(res, "\r\n")
}