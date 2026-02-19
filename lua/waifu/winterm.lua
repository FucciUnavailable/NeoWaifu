-- Dynamically updates the Windows Terminal background image by patching
-- settings.json on every mood change. Windows Terminal hot-reloads that
-- file, so the background swaps live with zero user interaction.

local M = {}

local _cfg = nil
local _enabled = true -- runtime toggle, independent of wt_background config flag

---Auto-locate Windows Terminal settings.json via the WSL /mnt/c mount.
---@return string|nil
local function find_settings()
	local matches = vim.fn.glob(
		"/mnt/c/Users/*/AppData/Local/Packages/Microsoft.WindowsTerminal*/LocalState/settings.json",
		false,
		true
	)
	if matches and #matches > 0 then
		return matches[1]
	end
	return nil
end

---@param cfg table  Full plugin config
function M.setup(cfg)
	_cfg = cfg
end

---Update the Windows Terminal background image for the configured profile.
---Runs asynchronously so it never blocks the editor.
---@param mood string
function M.set_mood(mood)
	if not _cfg or not _cfg.wt_background or not _enabled then
		return
	end

	local path = _cfg.wt_settings_path or find_settings()
	if not path then
		return
	end

	-- Run in a one-shot timer so we're off the main call stack
	vim.defer_fn(function()
		-- Read
		local rf = io.open(path, "r")
		if not rf then
			return
		end
		local content = rf:read("*a")
		rf:close()

		-- Parse  (settings.json has no comments so json_decode handles it fine)
		local ok, settings = pcall(vim.fn.json_decode, content)
		if not ok or type(settings) ~= "table" then
			return
		end

		-- Build the Windows image path.
		-- _cfg.wt_images_win_dir is a Lua string with single backslashes,
		-- e.g.  "C:\\neowaifu\\"  in the config  =  C:\neowaifu\  at runtime.
		local dir = _cfg.wt_images_win_dir or "C:\\neowaifu\\final\\"
		local ext = _cfg.wt_image_ext or "jpg"
		local img = dir .. mood .. "." .. ext

		local opacity = _cfg.wt_image_opacity or 0.15
		local stretch = _cfg.wt_stretch_mode or "uniformToFill"

		-- Patch the specific profile by GUID (preferred), or fall back to defaults.
		local guid = _cfg.wt_profile_guid
		local updated = false

		if guid and settings.profiles and settings.profiles.list then
			for _, profile in ipairs(settings.profiles.list) do
				if profile.guid == guid then
					profile.backgroundImage = img
					profile.backgroundImageOpacity = opacity
					profile.backgroundImageStretchMode = stretch
					updated = true
					break
				end
			end
		end

		if not updated and settings.profiles then
			local d = settings.profiles.defaults or {}
			d.backgroundImage = img
			d.backgroundImageOpacity = opacity
			d.backgroundImageStretchMode = stretch
			settings.profiles.defaults = d
		end

		-- Write back (compact JSON – Windows Terminal parses it fine)
		local wf = io.open(path, "w")
		if not wf then
			return
		end
		wf:write(vim.fn.json_encode(settings))
		wf:close()
	end, 0)
end

---Remove the background image from Windows Terminal (restore plain background).
function M.clear()
	if not _cfg then
		return
	end
	local path = _cfg.wt_settings_path or find_settings()
	if not path then
		return
	end

	vim.defer_fn(function()
		local rf = io.open(path, "r")
		if not rf then
			return
		end
		local content = rf:read("*a")
		rf:close()

		local ok, settings = pcall(vim.fn.json_decode, content)
		if not ok or type(settings) ~= "table" then
			return
		end

		local guid = _cfg.wt_profile_guid
		if guid and settings.profiles and settings.profiles.list then
			for _, profile in ipairs(settings.profiles.list) do
				if profile.guid == guid then
					profile.backgroundImage = vim.NIL
					profile.backgroundImageOpacity = vim.NIL
					break
				end
			end
		elseif settings.profiles and settings.profiles.defaults then
			settings.profiles.defaults.backgroundImage = vim.NIL
			settings.profiles.defaults.backgroundImageOpacity = vim.NIL
		end

		local wf = io.open(path, "w")
		if not wf then
			return
		end
		wf:write(vim.fn.json_encode(settings))
		wf:close()
	end, 0)
end

---Toggle the Windows Terminal background on/off at runtime.
---@return boolean  new state (true = on)
function M.toggle()
	_enabled = not _enabled
	if not _enabled then
		M.clear()
	end
	return _enabled
end

---@return boolean
function M.is_enabled()
	return _enabled
end

return M
