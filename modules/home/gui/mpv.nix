# modules/video-player.nix

{
  flake.modules.homeManager.gui = { pkgs, config, ... }: {
    programs.mpv = {
      enable = true;
      package = pkgs.mpv;
      config = {
        osc = "yes"; # On Screen Controller
        pause = "no"; # Start the player in paused state
        ytdl = "yes"; # Enable youtube-dl
        ytdl-format = "best"; # Use the best format available
        ytdl-raw-options = "cookies-from-browser=firefox";
        profile = "high-quality"; # gpu-hq is deprecated
        vo = "gpu";
        hwdec = "nvdec-copy"; # copies video back to system RAM
        gpu-context = "x11";
        x11-present = "yes";
        save-position-on-quit = "no";
        video-sync = "display-resample";
        interpolation = "yes";
        tscale = "oversample";

        # Notifications
        osd-playing-msg = "\${media-title}";

        # Subtitles
        sub-auto = "fuzzy";
        sub-font = pkgs.lib.mkDefault "Source Sans Pro";
        sub-font-size = 36;
        sub-color = "#FFFFFFFF";
        sub-border-color = "#FF262626";
        sub-border-size = 2;
        sub-shadow-color = "#33000000";
        sub-shadow-offset = 1;
        sub-use-margins = "no";
        sub-scale-by-window = "yes";
        sub-margin-y = 40;
        
        # Audio
        volume = 50;
        volume-max = 150;
        audio-pitch-correction = "yes";
      };
      
      scripts = with pkgs.mpvScripts; [
        quality-menu
        reload
        # modernx
        # thumbfast
        # sponsorblock
      ];
    };
    
    # TODO: Move to separate folder/file?
    # Add Lua script to block images
    home.file."${config.xdg.configHome}/mpv/scripts/block-images.lua".text = ''
      local blocked_extensions = {
        jpg = true, jpeg = true, png = true,
        webp = true, bmp = true, tiff = true,
        gif = true
      }

      mp.add_hook("on_preloaded", 10, function()
        local path = mp.get_property("path")
        local ext = path:match("%.([^%.]+)$") or ""
        if blocked_extensions[ext:lower()] then
          mp.msg.warn("Blocking image file: " .. path)
          mp.command("stop")
        end
      end)
    '';
  };
}