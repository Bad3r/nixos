-- Resolve which browser yt-dlp should read cookies from.
-- Priority: MPV_YTDLP_BROWSER env var > $BROWSER env var.
-- Set MPV_YTDLP_BROWSER="" to disable cookie passthrough entirely.
-- Skips silently if cookies-from-browser is already in ytdl-raw-options (CLI flag).

local function resolve_browser()
  local override = os.getenv("MPV_YTDLP_BROWSER")
  if override ~= nil then
    return override
  end
  local xdg = os.getenv("BROWSER")
  if xdg and xdg ~= "" then
    return (xdg:match("^(%S+)") or xdg)
  end
  return ""
end

local existing = mp.get_property("ytdl-raw-options") or ""
if not existing:find("cookies%-from%-browser") then
  local browser = resolve_browser()
  if browser ~= "" then
    mp.msg.info("ytdlp-cookies: cookies-from-browser=" .. browser)
    mp.set_property("ytdl-raw-options-append", "cookies-from-browser=" .. browser)
  else
    mp.msg.verbose("ytdlp-cookies: no browser resolved, skipping cookie passthrough")
  end
end
