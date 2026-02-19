local M = {}

M.defaults = {
  -- Corner to display in: "top-right" | "top-left" | "bottom-right" | "bottom-left"
  position = "bottom-right",

  -- Floating window size
  width = 32,
  height = 16,

  -- Padding from the editor edge (in cells)
  padding = 1,

  -- Milliseconds to wait after a diagnostic change before re-rendering.
  -- Keeps things snappy without hammering the UI on every keystroke.
  update_debounce = 300,

  -- Error thresholds that map to each mood level.
  -- mood = minimum error count to reach that mood
  thresholds = {
    happy   = 0,   -- 0 errors
    content = 1,   -- 1-2 errors
    neutral = 3,   -- 3-5 errors
    worried = 6,   -- 6-10 errors
    angry   = 11,  -- 11+ errors
  },

  -- Whether to include warnings (at half-weight) in the error count.
  count_warnings = false,

  -- Absolute path to a custom images directory.
  -- Defaults to the plugin's own images/ folder.
  images_dir = nil,

  -- Window blend (0-100). Higher = more transparent.
  blend = 15,

  -- Show a border around the waifu window.
  border = "rounded",

  -- ── Windows Terminal background integration ──────────────────────────────
  -- Set wt_background = true to enable live background image switching.
  wt_background = false,

  -- Auto-detected via /mnt/c/Users/*/AppData/Local/Packages/Microsoft.WindowsTerminal*
  -- Override if auto-detection fails.
  wt_settings_path = nil,

  -- Windows path to your mood images folder (use double backslashes in Lua strings).
  -- Example: "C:\\neowaifu\\"
  wt_images_win_dir = nil,

  -- File extension of your mood images.
  wt_image_ext = "jpg",

  -- GUID of the Windows Terminal profile to update.
  -- Find it in your settings.json next to the profile name you use.
  wt_profile_guid = nil,

  -- How opaque the background image is (0.0 = invisible, 1.0 = fully opaque).
  wt_image_opacity = 0.15,

  -- How the image fills the terminal window.
  -- "uniformToFill" = fill & crop  |  "uniform" = fit with letterbox
  wt_stretch_mode = "uniformToFill",
}

return M
