-- OpenAI-compatible streaming chat client.
-- Uses vim.fn.jobstart + curl for async SSE streaming.
-- Compatible with any OpenAI-compatible API (Claude, local models) by changing base_url.

local M = {}

-- Find the plugin root by locating this file inside Neovim's runtimepath.
local _plugin_root = (function()
  for _, dir in ipairs(vim.api.nvim_list_runtime_paths()) do
    if vim.fn.filereadable(dir .. "/lua/waifu/ai.lua") == 1 then
      return dir
    end
  end
end)()

-- ── internal ──────────────────────────────────────────────────────────────────

---Read a specific key from the .env file at the plugin root.
---Handles `KEY=value` and `KEY="value"` (with or without quotes).
---@param key string
---@return string|nil
local function read_dotenv(key)
  local path = _plugin_root .. "/.env"
  local f = io.open(path, "r")
  if not f then return nil end
  for line in f:lines() do
    local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if k == key then
      f:close()
      -- Strip surrounding quotes if present
      v = v:match('^"(.*)"$') or v:match("^'(.*)'$") or v
      return v ~= "" and v or nil
    end
  end
  f:close()
  return nil
end

---Write a JSON payload to a temp file and return the path.
---Avoids shell-escaping issues with large/complex JSON bodies.
---@param payload string  JSON string
---@return string  temp file path
local function write_payload(payload)
  local tmp = vim.fn.tempname() .. ".json"
  local f = io.open(tmp, "w")
  if not f then return "" end
  f:write(payload)
  f:close()
  return tmp
end

-- ── public API ────────────────────────────────────────────────────────────────

---Start a streaming chat completion.
---
---@param messages table[]  List of {role, content} message objects
---@param cfg table         Plugin config (reads openai_key, openai_model, openai_base_url)
---@param on_chunk fun(token:string)       Called on the main thread for each streamed token
---@param on_done  fun(full:string, err:string|nil)  Called once when streaming finishes
function M.stream(messages, cfg, on_chunk, on_done)
  local api_key = cfg.openai_key or os.getenv("OPENAI_API_KEY") or read_dotenv("OPENAI_API_KEY")
  if not api_key then
    vim.schedule(function()
      on_done("", "No API key. Set OPENAI_API_KEY in .env, environment, or cfg.openai_key")
    end)
    return
  end

  local model    = cfg.openai_model    or "gpt-4o"
  local base_url = cfg.openai_base_url or "https://api.openai.com/v1"

  local payload = vim.fn.json_encode({
    model    = model,
    messages = messages,
    stream   = true,
  })

  local tmp = write_payload(payload)
  if tmp == "" then
    vim.schedule(function()
      on_done("", "Failed to write request payload to temp file")
    end)
    return
  end

  local cmd = {
    "curl", "-s", "-N",
    base_url .. "/chat/completions",
    "-H", "Content-Type: application/json",
    "-H", "Authorization: Bearer " .. api_key,
    "--data-binary", "@" .. tmp,
  }

  local full_text  = ""
  local done_fired = false  -- guard against duplicate on_done calls

  local function fire_done(err)
    if done_fired then return end
    done_fired = true
    pcall(os.remove, tmp)
    vim.schedule(function()
      on_done(full_text, err)
    end)
  end

  vim.fn.jobstart(cmd, {
    on_stdout = function(_, data, _)
      for _, raw_line in ipairs(data) do
        -- Skip empty lines (SSE uses blank lines as event separators)
        if raw_line == "" then goto continue end

        -- SSE lines have the form "data: <payload>"
        if not vim.startswith(raw_line, "data: ") then goto continue end

        local json_str = raw_line:sub(7)  -- strip "data: " (6 chars + 1)

        if json_str == "[DONE]" then
          fire_done(nil)
          return
        end

        local ok, decoded = pcall(vim.fn.json_decode, json_str)
        if not ok or type(decoded) ~= "table" then goto continue end

        local choices = decoded.choices
        if not choices or not choices[1] then goto continue end

        local delta = choices[1].delta
        if delta and type(delta.content) == "string" then
          local token = delta.content
          full_text = full_text .. token
          vim.schedule(function()
            on_chunk(token)
          end)
        end

        ::continue::
      end
    end,

    on_exit = function(_, exit_code, _)
      -- Called after all stdout has been processed.
      -- fire_done is a no-op if [DONE] already triggered it.
      local err = nil
      if exit_code ~= 0 then
        err = ("curl exited with code %d"):format(exit_code)
      end
      fire_done(err)
    end,

    -- Forward stderr to nowhere (suppress curl progress meter, etc.)
    on_stderr = function() end,
  })
end

return M
