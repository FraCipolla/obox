package main

import "core:fmt"
import "core:os"
import "core:terminal/ansi"

HELP :: `obox modern terminal IDE
    usage:
      - obox <file>`

main :: proc() {
	args := os.args
	if len(args) < 2 {
		fmt.println(HELP)
		os.exit(0)
	}

	editor.filepath = args[1]

	enable_raw_mode()
	defer disable_raw_mode()
	init_editor()
	defer destroy_editor()
	enable_extended_keyboard()
	defer disable_extended_keyboard()
	editor_open_file(editor.filepath)

	fmt.print(ansi.CSI + ansi.DECASB_ENTER)
	fmt.print(ansi.CSI + "2J")

	defer {
		fmt.print(ansi.CSI + ansi.RESET + ansi.SGR)
		fmt.print(ansi.CSI + ansi.DECTCEM_SHOW)
		fmt.print(ansi.CSI + ansi.DECASB_EXIT)
	}
	explorer_refresh(&editor.explorer)
	for {
		editor_refresh_screen()
		if !process_keypress(&editor.keymap) do break
	}
}
