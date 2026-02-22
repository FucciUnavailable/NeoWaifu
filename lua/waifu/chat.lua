-- Two-window VTuber chat panel.
-- Main window: avatar (top 10 lines) + separator + scrollable history.
-- Input window: small editable bar directly below.

local M = {}

local animator = require("waifu.animator")
local ai       = require("waifu.ai")
local context  = require("waifu.context")

-- ── module state ──────────────────────────────────────────────────────────────

local _cfg = {}

-- Buffer/window handles (buffers survive close; windows are recreated on open)
local main_buf  = nil
local main_win  = nil
local input_buf = nil
local input_win = nil

local buf_initialized = false  -- true once avatar+separator have been written
local keymaps_set     = false  -- keymaps are per-buffer; set once

-- Chat conversation state
local chat_history        = {}   -- { role, content } message list
local response_start_line = 0    -- 0-indexed line where current [nya~] response begins
local _streaming          = false

local DEFAULT_SYSTEM_PROMPT =
  "You are Nya, a cheerful and knowledgeable coding assistant who speaks like a VTuber. "
  .. "You're enthusiastic, caring, and give clear practical advice. "
  .. "Occasionally use 'nya~' naturally. Keep replies concise and focused on the user's code."

-- ── text helpers ──────────────────────────────────────────────────────────────

---Wrap a prefixed message into display lines.
---The prefix appears on the first line; continuation lines are indented to match.
---@param prefix string   e.g. "  [nya~] "
---@param text   string
---@param max_w  integer  max characters per line
---@return string[]
local function wrap_message(prefix, text, max_w)
  local indent = string.rep(" ", #prefix)
  local result = {}
  local used_prefix = false

  -- Process each paragraph (newline-separated chunk)
  for para in (text .. "\n"):gmatch("([^\n]*)\n") do
    if para == "" then
      if used_prefix then table.insert(result, "") end
    else
      local remaining = para
      while #remaining > 0 do
        local pfx  = (not used_prefix) and prefix or indent
        used_prefix = true
        local avail = max_w - #pfx
        if avail < 1 then avail = 1 end
        if #remaining <= avail then
          table.insert(result, pfx .. remaining)
          remaining = ""
        else
          table.insert(result, pfx .. remaining:sub(1, avail))
          remaining = remaining:sub(avail + 1)
        end
      end
    end
  end

  if #result == 0 then result = { prefix } end
  return result
end

-- ── buffer helpers ────────────────────────────────────────────────────────────

local function inner_width()
  return _cfg.chat_width - 4  -- subtract 2 borders + 2 padding columns
end

local function scroll_to_bottom()
  if main_win and vim.api.nvim_win_is_valid(main_win) then
    local lcount = vim.api.nvim_buf_line_count(main_buf)
    pcall(vim.api.nvim_win_set_cursor, main_win, { lcount, 0 })
  end
end

---Append one or more display lines at the end of the main buffer.
---@param lines string[]
local function append_lines(lines)
  if not main_buf or not vim.api.nvim_buf_is_valid(main_buf) then return end
  local count = vim.api.nvim_buf_line_count(main_buf)
  vim.bo[main_buf].modifiable = true
  vim.api.nvim_buf_set_lines(main_buf, count, count, false, lines)
  vim.bo[main_buf].modifiable = false
  scroll_to_bottom()
end

---Append a wrapped chat message.
---@param prefix string
---@param text   string
local function append_message(prefix, text)
  append_lines(wrap_message(prefix, text, inner_width()))
end

---Replace lines from response_start_line to end-of-buffer with wrapped text.
---This is the "growing in place" streaming effect.
---@param text string  Full accumulated response so far
local function update_response(text)
  if not main_buf or not vim.api.nvim_buf_is_valid(main_buf) then return end
  local lines = wrap_message("  [nya~] ", text, inner_width())
  vim.bo[main_buf].modifiable = true
  vim.api.nvim_buf_set_lines(main_buf, response_start_line, -1, false, lines)
  vim.bo[main_buf].modifiable = false
  scroll_to_bottom()
end

-- ── AI message building ───────────────────────────────────────────────────────

local function build_messages()
  local ctx     = context.get()
  local ctx_str = context.format(ctx)
  local system  = (_cfg.chat_system_prompt or DEFAULT_SYSTEM_PROMPT)
    .. "\n\n--- Current Editor Context ---\n" .. ctx_str

  local msgs = { { role = "system", content = system } }
  for _, m in ipairs(chat_history) do
    table.insert(msgs, m)
  end
  return msgs
end

-- ── keymaps ───────────────────────────────────────────────────────────────────

local function setup_keymaps()
  if keymaps_set then return end
  keymaps_set = true

  local function map(buf, mode, lhs, rhs)
    vim.api.nvim_buf_set_keymap(buf, mode, lhs, rhs,
      { noremap = true, silent = true, nowait = true })
  end

  -- Input window: submit on <CR>, close on Esc/q
  map(input_buf, "i", "<CR>", "<Cmd>lua require('waifu.chat').submit()<CR>")
  map(input_buf, "n", "<CR>", "<Cmd>lua require('waifu.chat').submit()<CR>")
  map(input_buf, "n", "<Esc>", "<Cmd>lua require('waifu.chat').close()<CR>")
  map(input_buf, "n", "q",    "<Cmd>lua require('waifu.chat').close()<CR>")

  -- Main window: jump to input on i/a, close on q/Esc
  map(main_buf, "n", "i",    "<Cmd>lua require('waifu.chat').focus_input()<CR>")
  map(main_buf, "n", "a",    "<Cmd>lua require('waifu.chat').focus_input()<CR>")
  map(main_buf, "n", "q",    "<Cmd>lua require('waifu.chat').close()<CR>")
  map(main_buf, "n", "<Esc>","<Cmd>lua require('waifu.chat').close()<CR>")
end

-- ── window layout ─────────────────────────────────────────────────────────────

local function win_col()
  return math.max(0, vim.o.columns - _cfg.chat_width - 3)
end

local function main_height()
  local usable = vim.o.lines - vim.o.cmdheight - 1
  return math.max(12, usable - 6)  -- leave room for input window (2 content + 2 borders + 2 gap)
end

-- ── public API ────────────────────────────────────────────────────────────────

---@param cfg table  Full plugin config
function M.setup(cfg)
  _cfg = cfg
end

function M.is_open()
  return main_win ~= nil and vim.api.nvim_win_is_valid(main_win)
end

---Open the chat panel (no-op if already open).
function M.open()
  if M.is_open() then return end

  local W = _cfg.chat_width
  local col = win_col()
  local mh  = main_height()

  -- ── main buffer ─────────────────────────────────────────────────────────────
  if not main_buf or not vim.api.nvim_buf_is_valid(main_buf) then
    main_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[main_buf].bufhidden  = "hide"
    vim.bo[main_buf].buftype    = "nofile"
    vim.bo[main_buf].swapfile   = false
    buf_initialized = false
    keymaps_set     = false
  end

  if not buf_initialized then
    buf_initialized = true
    local frames    = require("waifu.frames")
    local separator = "  " .. string.rep("─", W - 4)
    local init      = vim.deepcopy(frames.base)
    table.insert(init, separator)
    vim.bo[main_buf].modifiable = true
    vim.api.nvim_buf_set_lines(main_buf, 0, -1, false, init)
    vim.bo[main_buf].modifiable = false
  end

  -- ── main window ─────────────────────────────────────────────────────────────
  main_win = vim.api.nvim_open_win(main_buf, false, {
    relative  = "editor",
    width     = W,
    height    = mh,
    row       = 0,
    col       = col,
    style     = "minimal",
    border    = "rounded",
    focusable = true,
    zindex    = 20,
    title     = " nyaa~ ",
    title_pos = "center",
  })
  vim.wo[main_win].wrap       = true
  vim.wo[main_win].number     = false
  vim.wo[main_win].signcolumn = "no"
  vim.wo[main_win].cursorline = false

  -- ── input buffer ────────────────────────────────────────────────────────────
  if not input_buf or not vim.api.nvim_buf_is_valid(input_buf) then
    input_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[input_buf].bufhidden  = "hide"
    vim.bo[input_buf].buftype    = "nofile"
    vim.bo[input_buf].swapfile   = false
    vim.bo[input_buf].modifiable = true
    vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, { "> " })
  end

  -- ── input window ────────────────────────────────────────────────────────────
  -- Positioned directly below the main window (after main's border)
  local input_row = mh + 2  -- mh content rows + top border(1) + bottom border(1)
  input_win = vim.api.nvim_open_win(input_buf, false, {
    relative  = "editor",
    width     = W,
    height    = 2,
    row       = input_row,
    col       = col,
    style     = "minimal",
    border    = "rounded",
    focusable = true,
    zindex    = 20,
    title     = " you ",
    title_pos = "center",
  })
  vim.wo[input_win].wrap       = false
  vim.wo[input_win].number     = false
  vim.wo[input_win].signcolumn = "no"

  -- ── keymaps ─────────────────────────────────────────────────────────────────
  setup_keymaps()

  -- ── animator ────────────────────────────────────────────────────────────────
  animator.setup(main_buf, 0)  -- avatar lives at lines 0-9
  animator.start_state("idle")

  -- ── focus input ─────────────────────────────────────────────────────────────
  M.focus_input()
end

---Close both windows (buffers are preserved for the next open).
function M.close()
  animator.stop()

  if input_win and vim.api.nvim_win_is_valid(input_win) then
    vim.api.nvim_win_close(input_win, true)
  end
  input_win = nil

  if main_win and vim.api.nvim_win_is_valid(main_win) then
    vim.api.nvim_win_close(main_win, true)
  end
  main_win = nil
end

function M.toggle()
  if M.is_open() then M.close() else M.open() end
end

---Move focus to the input window and enter insert mode.
function M.focus_input()
  if input_win and vim.api.nvim_win_is_valid(input_win) then
    vim.api.nvim_set_current_win(input_win)
    vim.cmd("startinsert!")
  end
end

---Submit the current input as a user message.
function M.submit()
  if _streaming then return end
  if not input_buf or not vim.api.nvim_buf_is_valid(input_buf) then return end

  -- Read and clean input text
  local raw_lines = vim.api.nvim_buf_get_lines(input_buf, 0, -1, false)
  local raw_text  = table.concat(raw_lines, "\n")

  -- Strip the "> " prompt prefix if present
  if vim.startswith(raw_text, "> ") then
    raw_text = raw_text:sub(3)
  end
  local user_text = vim.trim(raw_text)
  if user_text == "" then return end

  -- Reset input buffer
  vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, { "> " })

  -- Add user message to chat history & display
  table.insert(chat_history, { role = "user", content = user_text })
  append_message("  [you] ", user_text)

  -- Insert placeholder for upcoming response
  response_start_line = vim.api.nvim_buf_line_count(main_buf)
  append_lines({ "  [nya~] " })

  -- Kick off the AI call
  _streaming      = true
  local first     = true
  local accum     = ""
  local messages  = build_messages()

  animator.start_state("thinking")

  ai.stream(messages, _cfg,
    function(token)  -- on_chunk (already on main thread via vim.schedule)
      if first then
        first = false
        animator.start_state("talking")
      end
      accum = accum .. token
      update_response(accum)
    end,
    function(full_text, err)  -- on_done
      _streaming = false
      animator.start_state("idle")

      if err then
        -- Show error in chat
        vim.bo[main_buf].modifiable = true
        vim.api.nvim_buf_set_lines(main_buf, response_start_line, -1, false,
          { "  [nya~] (error: " .. err .. ")" })
        vim.bo[main_buf].modifiable = false
      else
        -- Finalise response in history and add visual spacing
        table.insert(chat_history, { role = "assistant", content = full_text })
        append_lines({ "" })  -- blank separator after response
      end

      scroll_to_bottom()
      -- Return focus to input so user can type next message
      M.focus_input()
    end
  )
end

return M
