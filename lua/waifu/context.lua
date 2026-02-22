-- Gathers current editor context (file, cursor, code, diagnostics)
-- to inject into AI system prompts.

local M = {}

-- ── internal ──────────────────────────────────────────────────────────────────

---Find the first regular file buffer/window (skips nofile/scratch/chat buffers).
---@return integer|nil buf, integer|nil win
local function find_code_win()
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local b  = vim.api.nvim_win_get_buf(w)
    local bt = vim.bo[b].buftype
    if bt == "" then  -- normal file buffer
      return b, w
    end
  end
  return nil, nil
end

-- ── public API ────────────────────────────────────────────────────────────────

---Gather context from the current code buffer.
---@return table  { filename, filetype, code, errors[], cursor_line }
function M.get()
  local buf, win = find_code_win()

  if not buf then
    return { filename = "", filetype = "", code = "", errors = {}, cursor_line = 1 }
  end

  local cursor      = vim.api.nvim_win_get_cursor(win)
  local cursor_line = cursor[1]  -- 1-indexed
  local filename    = vim.api.nvim_buf_get_name(buf)
  local filetype    = vim.bo[buf].filetype

  -- 200 lines centred on cursor (100 before, 100 after)
  local total      = vim.api.nvim_buf_line_count(buf)
  local start_line = math.max(0, cursor_line - 101)          -- 0-indexed, inclusive
  local end_line   = math.min(total, cursor_line + 100)      -- 0-indexed, exclusive
  local code_lines = vim.api.nvim_buf_get_lines(buf, start_line, end_line, false)
  local code       = table.concat(code_lines, "\n")

  -- Diagnostics for the code buffer
  local raw    = vim.diagnostic.get(buf)
  local errors = {}
  for _, d in ipairs(raw) do
    local sev = vim.diagnostic.severity
    local label = "INFO"
    if     d.severity == sev.ERROR then label = "ERROR"
    elseif d.severity == sev.WARN  then label = "WARN"
    elseif d.severity == sev.HINT  then label = "HINT"
    end
    table.insert(errors, {
      line     = d.lnum + 1,   -- convert to 1-indexed
      col      = d.col  + 1,
      severity = label,
      message  = d.message,
    })
  end

  return {
    filename    = filename,
    filetype    = filetype,
    code        = code,
    errors      = errors,
    cursor_line = cursor_line,
  }
end

---Format context table as a readable string for the AI system prompt.
---@param ctx table
---@return string
function M.format(ctx)
  local parts = {}

  if ctx.filename ~= "" then
    table.insert(parts, ("File: %s  [%s]"):format(ctx.filename, ctx.filetype))
  end
  table.insert(parts, ("Cursor: line %d"):format(ctx.cursor_line))

  if #ctx.errors > 0 then
    table.insert(parts, ("\nDiagnostics (%d total):"):format(#ctx.errors))
    for _, e in ipairs(ctx.errors) do
      table.insert(parts, ("  [%s] line %d:%d — %s"):format(
        e.severity, e.line, e.col, e.message))
    end
  else
    table.insert(parts, "\nNo active diagnostics.")
  end

  if ctx.code ~= "" then
    table.insert(parts, ("\nCode (lines %d±100):"):format(ctx.cursor_line))
    table.insert(parts, ("```%s"):format(ctx.filetype))
    table.insert(parts, ctx.code)
    table.insert(parts, "```")
  end

  return table.concat(parts, "\n")
end

return M
