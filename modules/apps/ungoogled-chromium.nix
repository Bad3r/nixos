/*
  Package: ungoogled-chromium
  Description: Chromium build with Google-integration stripped out, prioritizing privacy and manual control over updates.
  Homepage: https://ungoogled-software.github.io/ungoogled-chromium/
  Documentation: https://github.com/ungoogled-software/ungoogled-chromium
  Repository: https://github.com/ungoogled-software/ungoogled-chromium

  Summary:
    * Ships Chromium without Google web services, binaries, or background request endpoints, reducing unsolicited network traffic.
    * Exposes policy support and flags identical to upstream Chromium so administrators can enforce hardened defaults.

  Options:
    --incognito: Launch directly into an incognito session.
    --ozone-platform-hint=auto: Allow Wayland/X11 negotiation at runtime on Linux.
    --enable-features=VaapiVideoDecoder,VaapiVideoEncoder: Turn on VA-API hardware acceleration where supported.
    --profile-directory=<name>: Use a specific profile directory under `~/.config/chromium`.

  Example Usage:
    * `ungoogled-chromium https://example.com` — Open a URL with the de-Googled Chromium fork.
    * `ungoogled-chromium --incognito --enable-features=VaapiVideoDecoder` — Launch a private session with VA-API decoding.
    * `ungoogled-chromium --user-data-dir ~/.local/share/chromium-alt` — Keep a fully isolated profile tree for testing.
*/
_:
let
  UngoogledChromiumModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."ungoogled-chromium".extended;
    in
    {
      options.programs.ungoogled-chromium.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable ungoogled-chromium.";
        };

        package = lib.mkPackageOption pkgs "ungoogled-chromium" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.ungoogled-chromium = UngoogledChromiumModule;
}
