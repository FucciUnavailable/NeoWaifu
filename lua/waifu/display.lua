-- Manages the persistent floating window that shows the waifu.
-- Only one window exists at a time; it is reused across updates.

local M = {}

local cfg = nil
local buf  = nil  -- scratch buffer (reused)
local win  = nil  -- floating window handle

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
