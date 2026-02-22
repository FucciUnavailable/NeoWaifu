-- Generation-counter based animation engine.
-- Uses vim.defer_fn callbacks tagged with a generation number.
-- Incrementing _gen invalidates all pending callbacks — no explicit cancel needed.

local M = {}

local _buf       = nil   -- chat scratch buffer
local _line_start = 0    -- 0-indexed line offset of the avatar section in buf
local _gen       = 0     -- current generation; ticks with stale gen are no-ops
local _running   = false

-- ── internal ──────────────────────────────────────────────────────────────────

local function apply_frame(frame)
  if not _buf or not vim.api.nvim_buf_is_valid(_buf) then return end

  local frames = require("waifu.frames")
  local base   = frames.base

  -- Build display lines: base with patches applied
  local lines = {}
  for i, base_line in ipairs(base) do
    lines[i] = (frame.patch and frame.patch[i]) or base_line
  end

  vim.bo[_buf].modifiable = true
  vim.api.nvim_buf_set_lines(_buf, _line_start, _line_start + #lines, false, lines)
  vim.bo[_buf].modifiable = false
end

local function tick(state_frames, idx, gen)
  if gen ~= _gen then return end  -- stale; bail out silently

  apply_frame(state_frames[idx])

  local next_idx = (idx % #state_frames) + 1
  local delay    = state_frames[idx].ms

  vim.defer_fn(function()
    tick(state_frames, next_idx, gen)
  end, delay)
end

-- ── public API ────────────────────────────────────────────────────────────────

---Bind the animator to a buffer and an avatar line offset.
---@param buf integer   Buffer handle (the chat main buffer)
---@param line_start integer  0-indexed first line of the avatar block
function M.setup(buf, line_start)
  _buf        = buf
  _line_start = line_start or 0
end

---Start animating the given state (loops until stop() or another start_state()).
---@param state string  Key into frames.states
function M.start_state(state)
  _gen     = _gen + 1
  _running = true

  local frames_mod = require("waifu.frames")
  local state_frames = frames_mod.states[state]
  if not state_frames or #state_frames == 0 then
    -- Unknown state — just render base
    apply_frame({ patch = {} })
    return
  end

  tick(state_frames, 1, _gen)
end

---Stop animation and render the base portrait.
function M.stop()
  _gen     = _gen + 1
  _running = false

  if _buf and vim.api.nvim_buf_is_valid(_buf) then
    local base = require("waifu.frames").base
    vim.bo[_buf].modifiable = true
    vim.api.nvim_buf_set_lines(_buf, _line_start, _line_start + #base, false, base)
    vim.bo[_buf].modifiable = false
  end
end

---@return boolean
function M.is_running()
  return _running
end

return M
