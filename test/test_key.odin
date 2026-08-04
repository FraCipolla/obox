package main

import "core:fmt"
import "core:os"
import "core:sys/posix"

enable_raw_mode :: proc() -> (posix.termios, bool) {
    orig: posix.termios
    if posix.tcgetattr(posix.STDIN_FILENO, &orig) != .OK {
        fmt.println("Error: tcgetattr failed!")
        return orig, false
    }

    raw := orig

    // 1. Disable signals (Ctrl+Z / Ctrl+C), canonical mode, local echo, and extended input
    raw.c_lflag -= {.ECHO, .ECHONL, .ICANON, .ISIG, .IEXTEN}
    // 2. Disable software flow control (Ctrl+S / Ctrl+Q) and newline translations
    raw.c_iflag -= {.IGNBRK, .BRKINT, .PARMRK, .ISTRIP, .INLCR, .IGNCR, .ICRNL, .IXON}
    // 3. Disable output processing
    raw.c_oflag -= {.OPOST}
    // 4. Set 8-bit character size
    // raw.c_cflag -= {.CSIZE, .PARENB}
    raw.c_cflag += {.CS8}

    // 5. Read byte-by-byte immediately without timeout
    raw.c_cc[.VMIN]  = 1
    raw.c_cc[.VTIME] = 0

    if posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &raw) != .OK {
        fmt.println("Error: tcsetattr failed!")
        return orig, false
    }

    return orig, true
}

disable_raw_mode :: proc(orig: ^posix.termios) {
    posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, orig)
}

enable_extended_keyboard :: proc() {
    // Enable modifyOtherKeys mode 2 (CSI u)
    os.write_string(os.stdout, "\x1b[?9001h\x1b[>4;2m\x1b[>1u")
}

disable_extended_keyboard :: proc() {
    os.write_string(os.stdout, "\x1b[?9001l\x1b[<u\x1b[>4;0m")
}

main :: proc() {
    orig_termios, ok := enable_raw_mode()
    if !ok {
        fmt.println("Failed to enable raw mode.")
        return
    }
    defer disable_raw_mode(&orig_termios)

    enable_extended_keyboard()
    defer disable_extended_keyboard()

    fmt.printf("Raw mode active! Press keys to inspect bytes (Press 'q' to exit):\r\n")

    buf: [16]byte
    for {
        n, _ := os.read(os.stdin, buf[:])
        if n > 0 {
            fmt.printf("Bytes (%d): %v\r\n", n, buf[:n])
            if n == 1 && buf[0] == 'q' do break // Press 'q' to exit
        }
    }
}