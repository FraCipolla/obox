#+build windows
package main

import win "core:sys/windows"

@(private="file")
orig_mode: win.DWORD

enable_raw_mode :: proc() {
    stdin := win.GetStdHandle(win.STD_INPUT_HANDLE)
    win.GetConsoleMode(stdin, &orig_mode)
    raw_mode := orig_mode & ~win.ENABLE_LINE_INPUT & ~win.ENABLE_ECHO_INPUT
    win.SetConsoleMode(stdin, raw_mode)
}

disable_raw_mode :: proc() {
    stdin := win.GetStdHandle(win.STD_INPUT_HANDLE)
    win.SetConsoleMode(stdin, orig_mode)
}

get_terminal_size :: proc() -> (width: i32, height: i32) {
    stdout := win.GetStdHandle(win.STD_OUTPUT_HANDLE)
    info: win.CONSOLE_SCREEN_BUFFER_INFO

    if win.GetConsoleScreenBufferInfo(stdout, &info) {
        width  = i32(info.srWindow.Right - info.srWindow.Left + 1)
        height = i32(info.srWindow.Bottom - info.srWindow.Top + 1)
        return width, height
    }
    return 80, 24
}
