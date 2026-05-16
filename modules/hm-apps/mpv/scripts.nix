{ lib, ... }:
let
  luaString = value: builtins.toJSON value;

  luaStringSet = values: ''
    {
    ${lib.concatMapStringsSep "\n" (value: "  [${luaString value}] = true,") values}
    }
  '';

  ytdlpCookies = {
    optionName = "cookies-from-browser";
    overrideEnv = "MPV_YTDLP_BROWSER";
    browserEnv = "BROWSER";
    logPrefix = "ytdlp_cookies";
  };

  playlistFilter = {
    scriptName = "playlist_filter";
    cycleBinding = "F3";
    imageExtensions = [
      "jpg"
      "jpeg"
      "png"
      "webp"
      "bmp"
      "tiff"
      "tif"
      "gif"
      "heic"
      "heif"
      "avif"
      "jxl"
      "svg"
    ];
    modes = [
      {
        id = 0;
        const = "MODE_OFF";
        label = "off";
        description = "no filtering; all files play";
      }
      {
        id = 1;
        const = "MODE_BLOCK_IMAGES";
        label = "block-images";
        description = "skip image files; play videos and audio";
      }
      {
        id = 2;
        const = "MODE_IMAGES_ONLY";
        label = "images-only";
        description = "skip non-image files; play images only";
      }
    ];
  };

  renderModeConstant = mode: "local ${mode.const} = ${toString mode.id}";
  renderModeString = mode: "  [${mode.const}] = ${luaString mode.label},";
  renderStringToMode = mode: "  [${luaString mode.label}] = ${mode.const},";
  modeCycleCount = toString (builtins.length playlistFilter.modes);
  modeDocs = lib.concatMapStringsSep "\n" (
    mode: "--   ${mode.label} -- ${mode.description}"
  ) playlistFilter.modes;

  ytdlpCookiesLua = ''
    -- Resolve which browser yt-dlp should read cookies from.
    -- Priority: ${ytdlpCookies.overrideEnv} env var > ${"$"}${ytdlpCookies.browserEnv} env var.
    -- Set ${ytdlpCookies.overrideEnv}="" to disable cookie passthrough entirely.
    -- Skips silently if ${ytdlpCookies.optionName} is already in ytdl-raw-options (CLI flag).

    local option_name = ${luaString ytdlpCookies.optionName}
    local override_env = ${luaString ytdlpCookies.overrideEnv}
    local browser_env = ${luaString ytdlpCookies.browserEnv}
    local log_prefix = ${luaString ytdlpCookies.logPrefix}

    local function resolve_browser()
      local override = os.getenv(override_env)
      if override ~= nil then
        return override
      end
      local xdg = os.getenv(browser_env)
      if xdg and xdg ~= "" then
        return (xdg:match("^(%S+)") or xdg)
      end
      return ""
    end

    local existing = mp.get_property("ytdl-raw-options") or ""
    if not existing:find(option_name, 1, true) then
      local browser = resolve_browser()
      if browser ~= "" then
        mp.msg.info(log_prefix .. ": " .. option_name .. "=" .. browser)
        mp.set_property("ytdl-raw-options-append", option_name .. "=" .. browser)
      else
        mp.msg.verbose(log_prefix .. ": no browser resolved, skipping cookie passthrough")
      end
    end
  '';

  playlistFilterLua = ''
    -- Playlist type filter with three modes, configurable at startup.
    --
    -- Modes:
    ${modeDocs}
    --
    -- Set the startup mode via:
    --   mpv --profile=vid ... / mpv -p vid ... (named profile; see mpv.conf)
    --   mpv --profile=img ... / mpv -p img ...
    --   mpv --script-opts=${playlistFilter.scriptName}-mode=block-images ...
    --   ~/.config/mpv/script-opts/${playlistFilter.scriptName}.conf  (persistent default)
    --
    -- Runtime keybinding: ${playlistFilter.cycleBinding} cycles through all three modes.
    -- Override with: ${playlistFilter.cycleBinding} script-binding ${playlistFilter.scriptName}-cycle in input.conf

    local options = require("mp.options")

    local image_extensions = ${luaStringSet playlistFilter.imageExtensions}

    ${lib.concatMapStringsSep "\n" renderModeConstant playlistFilter.modes}

    local mode_strings = {
    ${lib.concatMapStringsSep "\n" renderModeString playlistFilter.modes}
    }

    local string_to_mode = {
    ${lib.concatMapStringsSep "\n" renderStringToMode playlistFilter.modes}
    }

    local opts = { mode = ${luaString "off"} }
    options.read_options(opts, mp.get_script_name())

    if not string_to_mode[opts.mode] then
      mp.msg.warn("${playlistFilter.scriptName}: unknown mode '" .. opts.mode .. "', falling back to off")
      opts.mode = ${luaString "off"}
    end

    local mode = string_to_mode[opts.mode]

    if mode ~= MODE_OFF then
      mp.msg.info("${playlistFilter.scriptName}: starting in mode: " .. opts.mode)
    end

    mp.add_hook("on_preloaded", 10, function()
      if mode == MODE_OFF then
        return
      end
      local path = mp.get_property("path") or ""
      local ext = (path:match("%.([^%.]+)$") or ""):lower()
      local is_image = image_extensions[ext] == true
      if mode == MODE_BLOCK_IMAGES and is_image then
        mp.msg.info("${playlistFilter.scriptName}: Skipping Image: " .. path)
        mp.commandv("playlist-remove", "current")
      elseif mode == MODE_IMAGES_ONLY and not is_image then
        mp.msg.info("${playlistFilter.scriptName}: Skipping Video: " .. path)
        mp.commandv("playlist-remove", "current")
      end
    end)

    local function cycle_mode()
      mode = (mode + 1) % ${modeCycleCount}
      local label = mode_strings[mode]
      mp.osd_message("playlist filter: " .. label, 2)
      mp.msg.info("${playlistFilter.scriptName}: mode -> " .. label)
    end

    mp.add_key_binding(${luaString playlistFilter.cycleBinding}, "${playlistFilter.scriptName}-cycle", cycle_mode)
  '';
in
{
  flake.lib.homeManager.mpvScripts =
    { pkgs, ... }:
    let
      mkLuaScript =
        {
          name,
          text,
        }:
        pkgs.runCommand "mpv-${name}"
          {
            passthru.scriptName = "${name}.lua";
          }
          ''
            install -Dm444 ${pkgs.writeText "${name}.lua" text} "$out/share/mpv/scripts/${name}.lua"
          '';
    in
    {
      inherit playlistFilter ytdlpCookies;

      scripts = {
        playlistFilter = mkLuaScript {
          name = playlistFilter.scriptName;
          text = playlistFilterLua;
        };

        ytdlpCookies = mkLuaScript {
          name = "ytdlp_cookies";
          text = ytdlpCookiesLua;
        };
      };
    };
}
