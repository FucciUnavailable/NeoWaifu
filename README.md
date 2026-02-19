# waifu.nvim

A mood-reactive waifu overlay for Neovim. Your mascot gets happier as your code gets cleaner.

```
    ≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋
  ╭─────────────────╮
  │  ╲──      ──╱  │
  │  (ò  ) (  ó)   │
  │       ▾         │
  │   ╭─────────╮   │
  │   │ !! !!   │   │
  ╰─────────────────╯
        │     │
     ───┴─────┴───
   !! 11+ ERRORS !!
   "FIX IT NOW!!"
    !! !! !! !!
```

Mood levels driven by LSP / diagnostic error count:

| Errors | Mood     |
|--------|----------|
| 0      | happy    |
| 1–2    | content  |
| 3–5    | neutral  |
| 6–10   | worried  |
| 11+    | angry    |

---

## Requirements

- Neovim ≥ 0.9
- Any LSP client (built-in `vim.lsp`) **or** any diagnostic source
  (null-ls, nvim-lint, etc.) – the plugin just reads `vim.diagnostic`

---

## Installation

### lazy.nvim (recommended)

```lua
{
  "your-username/WaifuExtension",
  event = "VeryLazy",
  opts = {},
}
```

### packer.nvim

```lua
use {
  "your-username/WaifuExtension",
  config = function()
    require("waifu").setup({})
  end,
}
```

### Manual (no plugin manager)

```bash
git clone https://github.com/your-username/WaifuExtension \
  ~/.local/share/nvim/site/pack/waifu/start/WaifuExtension
```

Then add to your `init.lua`:

```lua
require("waifu").setup({})
```

---

## Configuration

All options below are optional – the defaults work out of the box.

```lua
require("waifu").setup({
  -- Corner to dock in: "bottom-right" | "bottom-left" | "top-right" | "top-left"
  position = "bottom-right",

  -- Floating window dimensions
  width  = 32,
  height = 16,

  -- Cells of padding from the editor edge
  padding = 1,

  -- Milliseconds to debounce diagnostic updates (avoids spamming renders)
  update_debounce = 300,

  -- Error thresholds per mood (minimum errors to reach that mood)
  thresholds = {
    happy   = 0,
    content = 1,
    neutral = 3,
    worried = 6,
    angry   = 11,
  },

  -- Include warnings at half-weight in the error count
  count_warnings = false,

  -- Absolute path to a directory with your own mood images.
  -- Files must be named: happy.txt, content.txt, neutral.txt, worried.txt, angry.txt
  images_dir = nil,

  -- Window transparency (0 = opaque, 100 = invisible)
  blend = 15,

  -- Border style: "rounded" | "single" | "double" | "shadow" | "none"
  border = "rounded",
})
```

---

## Commands

| Command        | Description                  |
|----------------|------------------------------|
| `:WaifuToggle` | Show / hide the waifu window |
| `:WaifuShow`   | Force-show the window        |
| `:WaifuHide`   | Force-hide the window        |

---

## Custom Images

Replace the ASCII art with your own by pointing `images_dir` at a folder
containing five `.txt` files named after the moods:

```
my-waifus/
├── happy.txt
├── content.txt
├── neutral.txt
├── worried.txt
└── angry.txt
```

```lua
require("waifu").setup({
  images_dir = vim.fn.expand("~/.config/nvim/waifu-images"),
})
```

Each file is rendered as-is inside the floating window. Keep lines ≤ `width`
characters and total lines ≤ `height - 1` (the last line is reserved for the
error count footer).

---

## How It Works

1. Neovim fires `DiagnosticChanged` whenever any diagnostic source updates.
2. The plugin debounces that event by `update_debounce` ms, then calls
   `vim.diagnostic.get(nil)` to count errors across all buffers.
3. The error count maps to a mood level, which selects an image file.
4. The image is rendered into a scratch buffer displayed in a floating window.

No polling. No timers at rest. Zero CPU overhead when nothing changes.
