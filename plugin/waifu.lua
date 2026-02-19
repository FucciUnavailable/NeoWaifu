-- Auto-loading entry point.
-- Neovim sources everything in plugin/ at startup.
-- We intentionally do NOT call setup() here so the user controls configuration.
-- The plugin only activates when the user calls require("waifu").setup({}).

if vim.g.loaded_waifu then return end
vim.g.loaded_waifu = true
