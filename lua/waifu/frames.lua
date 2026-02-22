-- Animation frame definitions for the VTuber avatar.
-- Uses a patch-based system: only lines that differ from base are specified.
-- patch = {} means "use base" for all lines.
-- patch = { [2] = "new line" } means replace line 2 with "new line", rest from base.

local M = {}

-- 10-line base portrait (cat girl, neutral expression, open eyes)
M.base = {
  "    /\\_____/\\    ",
  "   /  ◕   ◕  \\   ",
  "  (  ( ‿  )  )  ",
  "   \\   ╰─╯  /   ",
  "    ╰───────╯   ",
  "  ╭──╮   ╭──╮  ",
  "  │  ╰───╯  │  ",
  "  ╰────┬────╯  ",
  "        │       ",
  "       ─┴─      ",
}

-- States: list of frames, each frame = { patch = {[line_1idx] = str}, ms = duration }
M.states = {}

-- ── idle ─────────────────────────────────────────────────────────────────────
-- Eyes open for 3s, then a quick blink (close + reopen), then repeat
M.states.idle = {
  { patch = {},                                          ms = 3000 },  -- open eyes
  { patch = { [2] = "   /  ─   ─  \\   " },             ms = 80   },  -- eyes closing
  { patch = { [2] = "   /  .   .  \\   " },             ms = 50   },  -- fully closed
  { patch = { [2] = "   /  ─   ─  \\   " },             ms = 80   },  -- eyes opening
  { patch = {},                                          ms = 3000 },  -- open eyes
}

-- ── thinking ─────────────────────────────────────────────────────────────────
-- Eyes shift left/right + animated dots in mouth area
M.states.thinking = {
  { patch = { [2] = "   /  ◕   .  \\   ", [3] = "  (  ( .   )  )  " }, ms = 300 },
  { patch = { [2] = "   /  .   ◕  \\   ", [3] = "  (  ( ..  )  )  " }, ms = 300 },
  { patch = { [2] = "   /  ◕   .  \\   ", [3] = "  (  ( ... )  )  " }, ms = 300 },
  { patch = { [2] = "   /  .   ◕  \\   ", [3] = "  (  ( ..  )  )  " }, ms = 300 },
}

-- ── talking ───────────────────────────────────────────────────────────────────
-- Mouth alternates open / closed rapidly (120ms each)
M.states.talking = {
  { patch = { [3] = "  (  ( ᴗ  )  )  " }, ms = 120 },  -- mouth open
  { patch = { [3] = "  (  ( ─  )  )  " }, ms = 120 },  -- mouth closed
}

-- ── surprised ────────────────────────────────────────────────────────────────
-- Wide eyes + gasp face flash twice
M.states.surprised = {
  { patch = { [2] = "   /  ◎   ◎  \\   ", [3] = "  (  ( ▽  )  )  " }, ms = 200 },
  { patch = {},                                                          ms = 150 },
  { patch = { [2] = "   /  ◎   ◎  \\   ", [3] = "  (  ( ▽  )  )  " }, ms = 200 },
  { patch = {},                                                          ms = 150 },
}

-- ── happy_react ───────────────────────────────────────────────────────────────
-- Sparkle + heart eyes alternating
M.states.happy_react = {
  { patch = { [2] = "  ✦/  ♡   ♡  \\✦  ", [3] = "  (  ( ‿  )  )  " }, ms = 150 },
  { patch = { [2] = "  ✧/  ◕   ◕  \\✧  ", [3] = "  (  ( ᵕ  )  )  " }, ms = 150 },
}

return M
