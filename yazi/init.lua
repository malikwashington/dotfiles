-- Plugins are pinned in package.toml; `ya pkg install` fetches them.

-- full-border: draw borders around all three panes
require("full-border"):setup {
	type = ui.Border.ROUNDED,
}

-- git: show each file's git status in the file list (fetchers are in yazi.toml)
require("git"):setup {
	order = 1500,
}

-- relative-motions: number prefixes for motions, with relative line numbers
require("relative-motions"):setup {
	show_numbers = "relative",
	show_motion = true,
}
