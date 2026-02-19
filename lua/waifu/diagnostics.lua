-- Reads Neovim's built-in diagnostic store (populated by LSP, null-ls, etc.)
-- This is O(total diagnostics) but runs only on DiagnosticChanged events,
-- so it never polls and is effectively free at rest.

local M = {}

---@return integer errors, integer warnings
local function count_all()
  local errors   = 0
  local warnings = 0

  -- nil = query every buffer
  for _, d in ipairs(vim.diagnostic.get(nil)) do
    if d.severity == vim.diagnostic.severity.ERROR then
      errors = errors + 1
    elseif d.severity == vim.diagnostic.severity.WARN then
      warnings = warnings + 1
    end
  end

  return errors, warnings
end

---Determine current mood and raw error count.
---@param cfg table  Plugin config table
---@return string mood, integer count
function M.get_mood(cfg)
  local errors, warnings = count_all()

  -- Warnings count at half weight when enabled
  local count = errors
  if cfg.count_warnings then
    count = errors + math.floor(warnings / 2)
  end

  local t = cfg.thresholds

  if count >= t.angry then
    return "angry", count
  elseif count >= t.worried then
    return "worried", count
  elseif count >= t.neutral then
    return "neutral", count
  elseif count >= t.content then
    return "content", count
  else
    return "happy", count
  end
end

return M
