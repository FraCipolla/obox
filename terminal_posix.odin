#+build !windows
package main

import "core:fmt"
import "core:os"
import "core:terminal/ansi"
import "core:sys/posix"
import "core:sys/linux"

Winsize :: struct {
    ws_row, ws_col:       u16,
    ws_xpixel, ws_ypixel: u16,
}

orig_termios: posix.termios

get_err :: proc() -> posix.Errno {
    return posix.get_errno()
}

enable_raw_mode :: proc() {
    if posix.tcgetattr(posix.STDIN_FILENO, &orig_termios) == .FAIL {
        die("tcgetattr")
    }
    
    raw := orig_termios
    raw.c_iflag -= {.BRKINT, .ICRNL, .INPCK, .ISTRIP, .IXON}
    raw.c_oflag -= {.OPOST}
    raw.c_cflag |= {.CS8}
    raw.c_lflag -= {.ICANON, .ECHO, .ISIG, .IEXTEN}
    raw.c_cc[.VMIN] = 1
    raw.c_cc[.VTIME] = 0

    if posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &raw) == .FAIL {
        die("tcsetattr")
    }
}

disable_raw_mode :: proc() {
    posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &orig_termios)
}

die :: proc(s: string) {
    fmt.print(ansi.CSI + "2J")
    fmt.print(ansi.CSI + ansi.DECTCEM_SHOW)
    fmt.eprintln(s)
    os.exit(1)
}

get_window_size :: proc() -> (width, height: i32, err: bool) {
    ws: Winsize
    res := linux.ioctl(linux.Fd(1), linux.TIOCGWINSZ, uintptr(&ws))

    if res < 0xFFFFF000 {
        return i32(ws.ws_col), i32(ws.ws_row), false
    }
    return 80, 24, true
}

update_terminal_size :: proc() {
    ws: Winsize
    if linux.ioctl(1, linux.TIOCGWINSZ, uintptr(&ws)) == 0 && ws.ws_col > 0 && ws.ws_row > 0 {
        editor.cols = i32(ws.ws_col)
        editor.rows = i32(ws.ws_row)
    }
}
