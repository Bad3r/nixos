{ lib, ... }:
{
  configurations.nixos.tpnix.module = {
    programs = {
      floorp.extended.enable = lib.mkOverride 1100 true;
      firefox.extended.enable = lib.mkOverride 1100 false;
      librewolf.extended.enable = lib.mkOverride 1100 false;

      kitty.extended.enable = lib.mkOverride 1100 true;
      neovim.extended.enable = lib.mkOverride 1100 true;
      codex.extended.enable = lib.mkOverride 1100 true;
      ripgrep.extended.enable = lib.mkOverride 1100 true;
      fzf.extended.enable = lib.mkOverride 1100 true;
      jq.extended.enable = lib.mkOverride 1100 true;
      git.extended.enable = lib.mkOverride 1100 true;
      coreutils.extended.enable = lib.mkOverride 1100 true;
      curl.extended.enable = lib.mkOverride 1100 true;
      wget.extended.enable = lib.mkOverride 1100 true;
      tealdeer.extended.enable = lib.mkOverride 1100 true;
      htop.extended.enable = lib.mkOverride 1100 true;
      bottom.extended.enable = lib.mkOverride 1100 true;
      zip.extended.enable = lib.mkOverride 1100 true;
      unzip.extended.enable = lib.mkOverride 1100 true;
      p7zip.extended.enable = lib.mkOverride 1100 true;

      nemo.extended.enable = lib.mkOverride 1100 true;
      "gnome-file-roller".extended.enable = lib.mkOverride 1100 true;
      xclip.extended.enable = lib.mkOverride 1100 true;
      xsel.extended.enable = lib.mkOverride 1100 true;

      "i3status-rust".extended.enable = lib.mkOverride 1100 true;
      dunst.extended.enable = lib.mkOverride 1100 true;
      rofi.extended.enable = lib.mkOverride 1100 true;
      picom.extended.enable = lib.mkOverride 1100 true;
      greenclip.extended.enable = lib.mkOverride 1100 true;

      networkmanagerapplet.extended.enable = lib.mkOverride 1100 true;
      "networkmanager-openvpn".extended.enable = lib.mkOverride 1100 true;
      openvpn.extended.enable = lib.mkOverride 1100 true;
      tailscale.extended.enable = lib.mkOverride 1100 true;

      obsidian.extended.enable = lib.mkOverride 1100 false;
      logseq.extended.enable = lib.mkOverride 1100 true;
      planify.extended.enable = lib.mkOverride 1100 false;
      pandoc.extended.enable = lib.mkOverride 1100 true;
      zathura.extended.enable = lib.mkOverride 1100 true;
      nsxiv.extended.enable = lib.mkOverride 1100 true;
      mpv.extended.enable = lib.mkOverride 1100 false;

      docker.extended.enable = lib.mkOverride 1100 false;
      steam.extended.enable = lib.mkOverride 1100 false;
      burpsuite.extended.enable = lib.mkOverride 1100 true;
      qemu.extended.enable = lib.mkOverride 1100 false;
      "vmware-workstation".extended.enable = lib.mkOverride 1100 false;
      virtualbox.extended.enable = lib.mkOverride 1100 false;
      "virt-manager".extended.enable = lib.mkOverride 1100 false;
      "cloudflare-warp".extended.enable = lib.mkOverride 1100 false;
      cloudflared.extended.enable = lib.mkOverride 1100 false;
      "vscode-fhs".extended.enable = lib.mkOverride 1100 true;
      "wine-tools".extended.enable = lib.mkOverride 1100 false;
      upscayl.extended.enable = lib.mkOverride 1100 false;
      go.extended.enable = lib.mkOverride 1100 false;
      rustc.extended.enable = lib.mkOverride 1100 false;
      "rust-analyzer".extended.enable = lib.mkOverride 1100 false;
      "rust-clippy".extended.enable = lib.mkOverride 1100 false;
      rustfmt.extended.enable = lib.mkOverride 1100 false;
      "clojure-cli".extended.enable = lib.mkOverride 1100 false;
      "clojure-lsp".extended.enable = lib.mkOverride 1100 false;
      leiningen.extended.enable = lib.mkOverride 1100 false;
      "temurin-bin-25".extended.enable = lib.mkOverride 1100 true;
    };

    services = {
      autorandr.extended.enable = lib.mkOverride 1100 true;
    };
  };
}
