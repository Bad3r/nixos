-- Playlist type filter with three modes, configurable at startup.
--
-- Modes:
--   off          -- no filtering; all files play (default)
--   block-images -- skip image files; play videos and audio
--   images-only  -- skip non-image files; play images only
--
-- Set the startup mode via:
--   mpv --profile=vid ... / mpv -p vid ... (named profile; see mpv.conf)
--   mpv --profile=img ... / mpv -p img ...
--   mpv --script-opts=playlist_filter-mode=block-images ...
--   ~/.config/mpv/script-opts/playlist_filter.conf  (persistent default)
--
-- Runtime keybinding: F3 cycles through all three modes.
-- Override with: F3 script-binding playlist_filter-cycle in input.conf

local options = require("mp.options")

local image_extensions = {
  jpg = true,
  jpeg = true,
  png = true,
  webp = true,
  bmp = true,
  tiff = true,
  tif = true,
  gif = true,
  heic = true,
  heif = true,
  avif = true,
  jxl = true,
  svg = true,
}

local MODE_OFF = 0
local MODE_BLOCK_IMAGES = 1
local MODE_IMAGES_ONLY = 2

local mode_strings = {
  [MODE_OFF] = "off",
  [MODE_BLOCK_IMAGES] = "block-images",
  [MODE_IMAGES_ONLY] = "images-only",
}

local string_to_mode = {
  off = MODE_OFF,
  ["block-images"] = MODE_BLOCK_IMAGES,
  ["images-only"] = MODE_IMAGES_ONLY,
}

local opts = { mode = "off" }
options.read_options(opts, mp.get_script_name())

if not string_to_mode[opts.mode] then
  mp.msg.warn("playlist_filter: unknown mode '" .. opts.mode .. "', falling back to off")
  opts.mode = "off"
end

local mode = string_to_mode[opts.mode]

if mode ~= MODE_OFF then
  mp.msg.info("playlist_filter: starting in mode: " .. opts.mode)
end

mp.add_hook("on_preloaded", 10, function()
  if mode == MODE_OFF then
    return
  end
  local path = mp.get_property("path") or ""
  local ext = (path:match("%.([^%.]+)$") or ""):lower()
  local is_image = image_extensions[ext] == true
  if mode == MODE_BLOCK_IMAGES and is_image then
    mp.msg.info("playlist_filter: Skipping Image: " .. path)
    mp.commandv("playlist-remove", "current")
  elseif mode == MODE_IMAGES_ONLY and not is_image then
    mp.msg.info("playlist_filter: Skipping Video: " .. path)
    mp.commandv("playlist-remove", "current")
  end
end)

local function cycle_mode()
  mode = (mode + 1) % 3
  local label = mode_strings[mode]
  mp.osd_message("playlist filter: " .. label, 2)
  mp.msg.info("playlist_filter: mode -> " .. label)
end

mp.add_key_binding("F3", "playlist_filter-cycle", cycle_mode)
