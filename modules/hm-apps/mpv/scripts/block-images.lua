local blocked_extensions = {
  jpg = true,
  jpeg = true,
  png = true,
  webp = true,
  bmp = true,
  tiff = true,
  gif = true,
}

mp.msg.verbose("block-images: will drop jpg, jpeg, png, webp, bmp, tiff, gif from playlists")

mp.add_hook("on_preloaded", 10, function()
  local path = mp.get_property("path") or ""
  local ext = path:match("%.([^%.]+)$") or ""
  if blocked_extensions[ext:lower()] then
    mp.msg.warn("Blocking image file: " .. path)
    mp.commandv("playlist-remove", "current")
  end
end)
