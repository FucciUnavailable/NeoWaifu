-- Manages the persistent floating window that shows the waifu.
-- Only one window exists at a time; it is reused across updates.

local M = {}

local cfg = nil
local buf  = nil  -- scratch buffer (reused)
local win  = nil  -- floating window handle

local ns = vim.api.nvim_create_namespace("waifu_hl")

-- ── helpers ──────────────────────────────────────────────────────────────────

---Returns the absolute path of this file so we can locate images/ next to it.
local function plugin_root()
  -- source path looks like "@/path/to/lua/waifu/display.lua"
  local src = debug.getinfo(1, "S").source:sub(2)
  -- go up: display.lua → waifu/ → lua/ → plugin root
  return vim.fn.fnamemodify(src, ":h:h:h")
end

---Load an image file into a list of strings (one per line).
---@param mood string
---@return string[]
local function load_image(mood)
  local dir = cfg.images_dir or (plugin_root() .. "/images")
  local path = dir .. "/" .. mood .. ".txt"
  local lines = {}

  local f = io.open(path, "r")
  if not f then
    -- Graceful fallback so nothing hard-crashes
    return { string.format("  [ %s ]", mood) }
  end

  for line in f:lines() do
    table.insert(lines, line)
  end
  f:close()

  return lines
end

---Compute the (row, col) for the window based on cfg.position.
---@param width integer
---@param height integer
---@return integer row, integer col
local function win_pos(width, height)
  local pad  = cfg.padding
  local cols = vim.o.columns
  local rows = vim.o.lines

  -- Reserve space for the status line / command line at the bottom
  local usable_rows = rows - vim.o.cmdheight - 1

  local pos = cfg.position

  local row, col
  if pos == "top-left" then
    row = pad
    col = pad
  elseif pos == "top-right" then
    row = pad
    col = cols - width - pad - 2   -- -2 for border
  elseif pos == "bottom-left" then
    row = usable_rows - height - pad - 2
    col = pad
  else  -- bottom-right (default)
    row = usable_rows - height - pad - 2
    col = cols - width - pad - 2
  end

  return math.max(0, row), math.max(0, col)
end

-- ── highlighting ─────────────────────────────────────────────────────────────

local MOOD_HL = {
  happy   = "WaifuHappy",
  content = "WaifuContent",
  neutral = "WaifuNeutral",
  worried = "WaifuWorried",
  angry   = "WaifuAngry",
}

local ACCENT_CHARS = { "♡", "★", "✧", "♪", "♫", "☆", "♩" }

local function setup_highlights()
  vim.api.nvim_set_hl(0, "WaifuFace",    { fg = "#ffb3c6" })                -- soft pink
  vim.api.nvim_set_hl(0, "WaifuBody",    { fg = "#c9b3ff" })                -- lavender
  vim.api.nvim_set_hl(0, "WaifuAccent",  { fg = "#ffd700", bold = true })   -- gold
  vim.api.nvim_set_hl(0, "WaifuHappy",   { fg = "#a8e6a3", bold = true })   -- soft green
  vim.api.nvim_set_hl(0, "WaifuContent", { fg = "#87ceeb" })                -- sky blue
  vim.api.nvim_set_hl(0, "WaifuNeutral", { fg = "#d0d0d0" })                -- light gray
  vim.api.nvim_set_hl(0, "WaifuWorried", { fg = "#ffb347" })                -- orange
  vim.api.nvim_set_hl(0, "WaifuAngry",   { fg = "#ff6b6b", bold = true })   -- coral red
end

---Highlight accent characters (♡ ★ etc.) on a single line.
local function hl_accents(b, line_idx, text)
  for _, ch in ipairs(ACCENT_CHARS) do
    local pos = 1
    while true do
      local s, e = string.find(text, ch, pos, true)
      if not s then break end
      -- s/e are 1-indexed inclusive; nvim wants 0-indexed, col_end exclusive
      vim.api.nvim_buf_add_highlight(b, ns, "WaifuAccent", line_idx, s - 1, e)
      pos = e + 1
    end
  end
end

---Apply zone + accent highlights after lines are written to the buffer.
---@param b integer
---@param lines string[]
---@param mood string
local function apply_highlights(b, lines, mood)
  vim.api.nvim_buf_clear_namespace(b, ns, 0, -1)

  local mood_hl = MOOD_HL[mood] or "WaifuNeutral"
  local face_hl = (mood == "angry") and "WaifuAngry" or "WaifuFace"

  for i, line in ipairs(lines) do
    local idx = i - 1  -- nvim API is 0-indexed

    if idx <= 4 then
      vim.api.nvim_buf_add_highlight(b, ns, face_hl, idx, 0, -1)
    elseif idx <= 10 then
      vim.api.nvim_buf_add_highlight(b, ns, "WaifuBody", idx, 0, -1)
    elseif idx >= 12 and idx <= 14 then
      vim.api.nvim_buf_add_highlight(b, ns, mood_hl, idx, 0, -1)
    end

    hl_accents(b, idx, line)
  end

  -- Footer is always the last line
  vim.api.nvim_buf_add_highlight(b, ns, mood_hl, #lines - 1, 0, -1)
end

-- ─────────────────────────────────────────────────────────────────────────────

---Ensure the scratch buffer exists and is valid.
local function ensure_buf()
  if buf and vim.api.nvim_buf_is_valid(buf) then return end
  buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].buftype   = "nofile"
  vim.bo[buf].swapfile  = false
  vim.bo[buf].modifiable = true
end

-- ── public API ───────────────────────────────────────────────────────────────

---Must be called once before any other function.
---@param config table
function M.setup(config)
  cfg = config
  setup_highlights()
end

---Update (or create) the floating window with the given mood and error count.
---@param mood string
---@param count integer
function M.update(mood, count)
  if not cfg then return end

  local W = cfg.width
  local H = cfg.height

  -- Build content: image lines padded/truncated to W, then a status footer
  local raw = load_image(mood)
  local lines = {}

  -- Fill up to H-1 lines with image content
  for i = 1, H - 1 do
    local l = raw[i] or ""
    -- Trim to window width (avoids wrapping)
    if vim.fn.strdisplaywidth(l) > W then
      -- Safe byte-truncation (good enough for ASCII art)
      l = l:sub(1, W)
    end
    table.insert(lines, l)
  end

  -- Footer: error count + mood label
  local footer = string.format(" errors: %d  (%s)", count, mood)
  if #footer > W then footer = footer:sub(1, W) end
  table.insert(lines, footer)

  -- Write into buffer
  ensure_buf()
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  apply_highlights(buf, lines, mood)

  local row, col = win_pos(W, H)

  if win and vim.api.nvim_win_is_valid(win) then
    -- Just reposition + resize in case the editor was resized
    vim.api.nvim_win_set_config(win, {
      relative = "editor",
      width    = W,
      height   = H,
      row      = row,
      col      = col,
    })
  else
    win = vim.api.nvim_open_win(buf, false, {
      relative  = "editor",
      width     = W,
      height    = H,
      row       = row,
      col       = col,
      style     = "minimal",
      border    = cfg.border,
      focusable = false,
      zindex    = 10,
    })
    -- Transparency + no line numbers / sign column
    vim.wo[win].winblend   = cfg.blend
    vim.wo[win].wrap       = false
    vim.wo[win].number     = false
    vim.wo[win].signcolumn = "no"
    vim.wo[win].cursorline = false
  end
end

---Close the floating window (does not destroy the buffer).
function M.close()
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
    win = nil
  end
end

---Toggle visibility.
---@param mood string
---@param count integer
function M.toggle(mood, count)
  if win and vim.api.nvim_win_is_valid(win) then
    M.close()
  else
    M.update(mood, count)
  end
end

---Returns true if the window is currently visible.
function M.is_open()
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

return M
