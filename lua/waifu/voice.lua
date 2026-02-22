-- Voice recording + Whisper transcription pipeline.
-- Records via ffmpeg and transcribes with OpenAI-compatible /audio/transcriptions.

local M = {}

-- ── plugin root ───────────────────────────────────────────────────────────────

local _plugin_root = (function()
  for _, dir in ipairs(vim.api.nvim_list_runtime_paths()) do
    if vim.fn.filereadable(dir .. "/lua/waifu/voice.lua") == 1 then
      return dir
    end
  end
end)()

-- ── internal state ────────────────────────────────────────────────────────────

local _cfg          = {}
local _recording    = false
local _transcribing = false
local _job_id       = nil  -- jobstart id of the ffmpeg recorder
local _wav_path     = nil  -- temp file path for current recording
local _on_done      = nil  -- callback(text) to call after transcription

-- ── helpers ───────────────────────────────────────────────────────────────────

---Read a specific key from the .env file at the plugin root.
---@param key string
---@return string|nil
local function read_dotenv(key)
  if not _plugin_root then return nil end
  local path = _plugin_root .. "/.env"
  local f = io.open(path, "r")
  if not f then return nil end
  for line in f:lines() do
    local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if k == key then
      f:close()
      v = v:match('^"(.*)"$') or v:match("^'(.*)'$") or v
      return v ~= "" and v or nil
    end
  end
  f:close()
  return nil
end

---Build the ffmpeg command for recording from the default microphone.
---Uses PulseAudio on Linux/WSL2 (covers PipeWire-pulse), avfoundation on macOS.
---@param wav_path string  output file
---@return string[]
local function _record_cmd(wav_path)
  local uname = (vim.uv or vim.loop).os_uname()
  if uname.sysname == "Darwin" then
    -- macOS: CoreAudio via avfoundation; ":0" = default audio input, no video
    return {
      "ffmpeg", "-y",
      "-f", "avfoundation", "-i", ":0",
      "-ar", "16000", "-ac", "1", "-acodec", "pcm_s16le",
      wav_path,
    }
  else
    -- Linux / WSL2: PulseAudio (also works with PipeWire-pulse)
    return {
      "ffmpeg", "-y",
      "-f", "pulse", "-i", "default",
      "-ar", "16000", "-ac", "1", "-acodec", "pcm_s16le",
      wav_path,
    }
  end
end

-- ── transcription ─────────────────────────────────────────────────────────────

---POST the WAV file to the Whisper transcriptions endpoint, then call on_done.
---@param wav_path string
function M._transcribe(wav_path)
  local api_key = _cfg.openai_key
    or os.getenv("OPENAI_API_KEY")
    or read_dotenv("OPENAI_API_KEY")

  if not api_key then
    vim.schedule(function()
      vim.notify("[waifu] No API key for Whisper transcription.", vim.log.levels.ERROR)
      if _on_done then _on_done("") end
      _transcribing = false
      _on_done      = nil
    end)
    return
  end

  local base_url = _cfg.openai_base_url or "https://api.openai.com/v1"
  local model    = _cfg.whisper_model   or "whisper-1"
  local endpoint = base_url .. "/audio/transcriptions"

  local stdout_buf = {}

  local cmd = {
    "curl", "-s",
    endpoint,
    "-H", "Authorization: Bearer " .. api_key,
    "-F", "model=" .. model,
    "-F", "file=@" .. wav_path .. ";type=audio/wav",
    "-F", "response_format=json",
  }

  vim.fn.jobstart(cmd, {
    on_stdout = function(_, data, _)
      for _, line in ipairs(data) do
        if line ~= "" then
          table.insert(stdout_buf, line)
        end
      end
    end,

    on_stderr = function() end,

    on_exit = function(_, exit_code, _)
      pcall(os.remove, wav_path)
      _transcribing = false

      local raw = table.concat(stdout_buf, "")
      local cb  = _on_done
      _on_done  = nil

      vim.schedule(function()
        if exit_code ~= 0 then
          vim.notify(
            ("[waifu] Whisper curl failed (exit %d)"):format(exit_code),
            vim.log.levels.ERROR
          )
          if cb then cb("") end
          return
        end

        local ok, decoded = pcall(vim.fn.json_decode, raw)
        if not ok or type(decoded) ~= "table" then
          vim.notify("[waifu] Failed to parse Whisper response.", vim.log.levels.ERROR)
          if cb then cb("") end
          return
        end

        local text = decoded.text or ""
        text = vim.trim(text)
        if cb then cb(text) end
      end)
    end,
  })
end

-- ── public API ────────────────────────────────────────────────────────────────

---Store config.
---@param cfg table
function M.setup(cfg)
  _cfg = cfg
end

---Whether recording is currently active.
---@return boolean
function M.is_recording()
  return _recording
end

---Whether transcription is in flight.
---@return boolean
function M.is_transcribing()
  return _transcribing
end

---Start recording.  on_done(text) is called once transcription completes.
---@param on_done fun(text: string)
function M.start(on_done)
  if _recording or _transcribing then return end

  if vim.fn.executable("ffmpeg") == 0 then
    vim.notify(
      "[waifu] ffmpeg not found. Install it: pacman -S ffmpeg  |  apt install ffmpeg  |  brew install ffmpeg",
      vim.log.levels.ERROR
    )
    return
  end

  _wav_path = vim.fn.tempname() .. ".wav"
  _on_done  = on_done

  local job_id = vim.fn.jobstart(
    _record_cmd(_wav_path),
    {
      -- ffmpeg writes progress to stderr; suppress it to avoid notification spam
      on_stderr = function() end,

      on_exit = function(_, exit_code, _)
        _recording = false
        -- ffmpeg exits 255 when killed by SIGTERM — that is the normal stop path
        if exit_code ~= 0 and exit_code ~= 255 then
          vim.schedule(function()
            vim.notify(
              ("[waifu] Recorder exited with code %d. "
               .. "Is a microphone available? Check :messages for details."):format(exit_code),
              vim.log.levels.ERROR
            )
            local cb = _on_done
            _on_done = nil
            if cb then cb("") end
          end)
          return
        end

        -- WAV is fully written — kick off transcription
        _transcribing = true
        M._transcribe(_wav_path)
      end,
    }
  )

  if job_id <= 0 then
    vim.notify("[waifu] Failed to start ffmpeg recorder.", vim.log.levels.ERROR)
    _on_done = nil
    return
  end

  _job_id    = job_id
  _recording = true
end

---Stop recording (sends SIGTERM to ffmpeg; it flushes and writes the WAV).
---on_exit fires asynchronously, then _transcribe is called.
function M.stop()
  if not _recording then return end
  if _job_id then
    vim.fn.jobstop(_job_id)
    _job_id = nil
  end
  -- _recording is cleared inside on_exit
end

return M
