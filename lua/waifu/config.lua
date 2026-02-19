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
}

return M
