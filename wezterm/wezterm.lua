-- Ported from https://github.com/kunchenguid/dotfiles/blob/main/home/.config/wezterm/wezterm.lua
-- His config targets macOS; the Windows equivalents are annotated below.

local wezterm = require("wezterm")

local config = wezterm.config_builder()

-- The whole point of running WezTerm natively rather than under WSLg: the window
-- is a Windows window (so DWM composites it, which is what makes the
-- transparency and Acrylic below actually work), while the shell is still bash
-- in Ubuntu. Everything inside the terminal is unchanged from before.
config.default_domain = "WSL:Ubuntu"

config.color_scheme = "rose-pine-moon"
config.font = wezterm.font("Hack Nerd Font")
config.hide_tab_bar_if_only_one_tab = true

-- His 15.0 is a macOS number and does not transfer. font_size is in points, and
-- the two platforms use different logical baselines: macOS 72 DPI (so 15.0 is a
-- 15px em) versus Windows 96 (so 15.0 would be a 20px em -- a third larger).
-- 15 * 72/96 = 11.25 is the faithful translation; rounded up slightly for the
-- 27" 1440p primary, which sits a touch above 96 PPI.
config.font_size = 11.5

-- NOT win32_system_backdrop. Acrylic was the obvious mapping for his
-- macos_window_background_blur, and it is the wrong one: it hands the background
-- to DWM's system backdrop, which *replaces* WezTerm's own alpha compositing
-- with a heavy blur plus a dark tint. Over a dark scheme the result is a flat
-- frosted slab that reads as fully opaque -- measured at #252d30/#252c33 with
-- near-zero variance across the window, versus #1e1c2d/#1c2d2b/#2f1a2b (real
-- backdrop bleed) with plain alpha. Windows has no exposed per-window blur that
-- behaves like the macOS one, so the choice is blur-but-flat or see-through-but-
-- sharp. This picks see-through.
--
-- Well above his 0.8. Without a blur pass to soften what shows through, the low
-- 0.8x range leaves text in the window behind fully legible -- visual noise
-- rather than depth. 0.93 reads as tinted glass: the backdrop still modulates
-- the background, but nothing behind it is readable.
config.window_background_opacity = 0.93

-- Borderless, as he has it. That leaves no titlebar to grab, and
-- hide_tab_bar_if_only_one_tab removes the tab bar as a fallback drag handle
-- (his workflow uses tmux windows, so the wezterm tab bar is essentially always
-- hidden). CTRL+SHIFT+drag below restores mouse movement without giving up the
-- look; switch this to "TITLE|RESIZE" if you would rather have the real titlebar.
config.window_decorations = "RESIZE"

-- Drag the window from anywhere in the terminal body.
config.mouse_bindings = {
	{
		event = { Drag = { streak = 1, button = "Left" } },
		mods = "CTRL|SHIFT",
		action = wezterm.action.StartWindowDrag,
	},
}

-- Size the window to a fraction of the screen and center it there. The default
-- window is 80x24 cells, which at this font size is a small box wherever Windows
-- decides to drop it.
--
-- Not initial_cols/initial_rows: those are a fixed cell count, so the window
-- would be a different fraction of each of the three monitors here (1920x1200
-- and two 2560x1440), and they cannot center it. Reading the screen at the
-- moment we place the window does both.
local WINDOW_SCREEN_FRACTION = 0.8

local function fit_window_to_screen(gui_window)
	-- The screen with input focus, so this follows the window rather than always
	-- targeting the primary monitor.
	local screen = wezterm.gui.screens().active
	local width = screen.width * WINDOW_SCREEN_FRACTION
	local height = screen.height * WINDOW_SCREEN_FRACTION

	gui_window:set_inner_size(width, height)
	-- Both screen.x/y and set_position are in virtual-desktop coordinates, which
	-- span all three monitors and are negative to the left of the primary, so the
	-- centered offset has to be added to the target screen's own origin.
	gui_window:set_position(screen.x + (screen.width - width) / 2, screen.y + (screen.height - height) / 2)
end

-- Text paste that never leaves the terminal. Claude Code's own Ctrl+V is an
-- image-paste path, and on WSL it answers "is there an image on the clipboard?"
-- by shelling out to powershell.exe with System.Windows.Forms -- measured at
-- 330-590ms warm on this machine, and worse cold. Ctrl+Shift+V already pastes
-- directly. Shift+Insert, the other habitual Windows paste, was bound to
-- PrimarySelection, which does not exist on Windows, so it silently did nothing;
-- point it at the real clipboard.
--
-- Deliberately NOT rebinding plain Ctrl+V. It is blockwise-visual in Neovim, and
-- WezTerm cannot scope the binding to the program that wants it: under tmux the
-- foreground process it sees is always the tmux client, never the pane's.
config.keys = {
	{ key = "Insert", mods = "SHIFT", action = wezterm.action.PasteFrom("Clipboard") },

	-- Shift+Enter inserts a newline in Claude Code's prompt instead of submitting.
	-- WezTerm can report Shift+Enter distinctly, but only under modifyOtherKeys=2.
	-- Claude Code asks its own terminal for level 2; inside tmux that request stops
	-- at tmux, and tmux 3.4 in turn asks WezTerm for level *1* (Eneks=\E[>4;1m, see
	-- `tmux info`) -- a level whose definition exempts Return. So Shift+Enter
	-- arrives at tmux as a bare CR and no amount of extended-keys config recovers
	-- it. ESC+CR is what Claude Code's own /terminal-setup writes for VS Code, the
	-- prompt reads it as "newline" with no protocol negotiation involved, and tmux
	-- forwards it untouched as M-Enter.
	{ key = "Enter", mods = "SHIFT", action = wezterm.action.SendString("\x1b\r") },

	-- Re-run the startup placement on demand. Unplugging a monitor leaves Windows
	-- to relocate the window, and with window_decorations = "RESIZE" there is no
	-- titlebar to double-click and no maximize button to fix it with; the only
	-- recovery was restarting WezTerm. The built-in ResetFontAndWindowSize is not
	-- this: it restores initial_cols/initial_rows (unset here, so 80x24) and does
	-- not move the window.
	{
		key = "Home",
		mods = "CTRL|SHIFT",
		action = wezterm.action_callback(function(window)
			fit_window_to_screen(window)
		end),
	},
}

-- gui-startup fires once, for the window created at launch. Windows opened later
-- with CTRL+SHIFT+N get the default size and OS placement until CTRL+SHIFT+Home.
wezterm.on("gui-startup", function(cmd)
	local _, _, window = wezterm.mux.spawn_window(cmd or {})
	fit_window_to_screen(window:gui_window())
end)

-- Dim unfocused windows so the focused one is obvious at a glance.
local UNFOCUSED_FOREGROUND_TEXT_HSB = { hue = 1.0, saturation = 0.25, brightness = 0.45 }
-- His 0.62 is tuned against a blurred backdrop. With plain alpha and nothing
-- softening what shows through, 0.62 turns an unfocused window into a window
-- into whatever is behind it. Kept a fixed step below the focused value so
-- unfocused still reads as recessed without becoming see-through.
local UNFOCUSED_WINDOW_BACKGROUND_OPACITY = 0.85

-- get_config_overrides() hands back a copy, so the current value is never the
-- same table we last stored; compare the fields instead of the identity.
local function same_text_hsb(actual, expected)
	if actual == nil or expected == nil then
		return actual == expected
	end
	return actual.hue == expected.hue
		and actual.saturation == expected.saturation
		and actual.brightness == expected.brightness
end

wezterm.on("window-focus-changed", function(window)
	local overrides = window:get_config_overrides() or {}
	local text_hsb, opacity
	if not window:is_focused() then
		text_hsb = UNFOCUSED_FOREGROUND_TEXT_HSB
		opacity = UNFOCUSED_WINDOW_BACKGROUND_OPACITY
	end

	-- Only write when one of the two values we own actually changes; a redundant
	-- set_config_overrides() call would trigger another config reload.
	if same_text_hsb(overrides.foreground_text_hsb, text_hsb) and overrides.window_background_opacity == opacity then
		return
	end

	overrides.foreground_text_hsb = text_hsb
	overrides.window_background_opacity = opacity
	window:set_config_overrides(overrides)
end)

return config
