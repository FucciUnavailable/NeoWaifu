-- waifu.nvim – mood-reactive waifu overlay driven by LSP diagnostics
--
-- Usage (lazy.nvim):
--   { "your-username/WaifuExtension", opts = {} }
--
-- Usage (manual):
--   require("waifu").setup({})

local M = {}

local defaults  = require("waifu.config").defaults
local display   = require("waifu.display")
local diags     = require("waifu.diagnostics")
local winterm   = require("waifu.winterm")
local chat      = require("waifu.chat")
local voice     = require("waifu.voice")

local _cfg   = {}
local _timer = nil   -- uv timer for debouncing

-- ── internal ─────────────────────────────────────────────────────────────────

local function do_update()
  local mood, count = diags.get_mood(_cfg)
  display.update(mood, count)
  winterm.set_mood(mood, count)
end

-- Debounced wrapper – collapses rapid diagnostic bursts into a single render.
local function schedule_update()
  if _timer then
    _timer:stop()
  end
  _timer = vim.defer_fn(function()
    _timer = nil
    -- Guard: only update if the window should be visible
    if display.is_open() then
      do_update()
    end
  end, _cfg.update_debounce)
end

-- ── public API ───────────────────────────────────────────────────────────────

---@param user_cfg? table
function M.setup(user_cfg)
  _cfg = vim.tbl_deep_extend("force", defaults, user_cfg or {})

  display.setup(_cfg)
  winterm.setup(_cfg)
  chat.setup(_cfg)   -- also calls voice.setup internally
  voice.setup(_cfg)

  local group = vim.api.nvim_create_augroup("WaifuMood", { clear = true })

  -- Trigger on every diagnostic refresh (fired by LSP, null-ls, nvim-lint, …)
  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group    = group,
    callback = schedule_update,
  })

  -- Reposition after terminal resize
  vim.api.nvim_create_autocmd("VimResized", {
    group    = group,
    callback = function()
      if display.is_open() then do_update() end
    end,
  })

  -- ── commands ───────────────────────────────────────────────────────────────

  -- :WaifuToggle  – show / hide the window
  vim.api.nvim_create_user_command("WaifuToggle", function()
    local mood, count = diags.get_mood(_cfg)
    display.toggle(mood, count)
  end, { desc = "Toggle the waifu mood window" })

  -- :WaifuShow  – force-show
  vim.api.nvim_create_user_command("WaifuShow", function()
    do_update()
  end, { desc = "Show the waifu mood window" })

  -- :WaifuHide  – force-hide
  vim.api.nvim_create_user_command("WaifuHide", function()
    display.close()
  end, { desc = "Hide the waifu mood window" })

  -- :WaifuChat  – open / close the AI chat panel
  vim.api.nvim_create_user_command("WaifuChat", function()
    chat.toggle()
  end, { desc = "Toggle the Nya AI chat panel" })

  -- :WaifuVoice  – toggle voice recording / transcription
  vim.api.nvim_create_user_command("WaifuVoice", function()
    chat.toggle_voice()
  end, { desc = "Toggle voice recording for the Nya AI chat" })

  -- :WaifuBgToggle  – toggle Windows Terminal background image on/off
  vim.api.nvim_create_user_command("WaifuBgToggle", function()
    local on = winterm.toggle()
    if on then
      -- re-apply current mood immediately
      local mood, count = diags.get_mood(_cfg)
      winterm.set_mood(mood, count)
      vim.notify("Waifu background: ON", vim.log.levels.INFO)
    else
      vim.notify("Waifu background: OFF", vim.log.levels.INFO)
    end
  end, { desc = "Toggle Windows Terminal waifu background" })

  -- Initial render.
  -- When loaded with 'VeryLazy' or similar, VimEnter has already fired,
  -- so vim.v.vim_did_enter == 1 and we show immediately instead of waiting.
  if vim.v.vim_did_enter == 1 then
    vim.defer_fn(do_update, 100)
  else
    vim.api.nvim_create_autocmd("VimEnter", {
      group = group,
      once  = true,
      callback = function()
        -- Small delay lets LSP attach and send its first diagnostics
        vim.defer_fn(do_update, 500)
      end,
    })
  end
end

return M
