{ lib, ... }:
let
  system76-ectool =
    {
      lib,
      rustPlatform,
      fetchFromGitHub,
      pkg-config,
      hidapi,
    }:
    rustPlatform.buildRustPackage rec {
      pname = "system76-ectool";
      version = "0.3.8";

      src = fetchFromGitHub {
        owner = "system76";
        repo = "ec";
        rev = "a0b5f938bcf448b148dc5f09d93c55caf2e97a48";
        hash = "sha256-BgocSxVXOJRp3j8dTtkpiKlcfPKrLUi1VkTzqSgmEwE=";
      };

      sourceRoot = "${src.name}/tools/system76_ectool";

      cargoHash = "sha256-X19j9XG/lLAC9jE6/o7xF2forXpZuxvD8d+CxVqLrVA=";

      nativeBuildInputs = [ pkg-config ];
      buildInputs = [ hidapi ];
      buildFeatures = [
        "std"
        "hidapi"
        "clap"
      ];

      meta = {
        description = "System76 EC tool for fan control and firmware operations";
        homepage = "https://github.com/system76/ec";
        license = lib.licenses.mit;
        platforms = lib.platforms.linux;
        mainProgram = "system76_ectool";
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [
    "system76-wallpapers"
    "system76-wallpapers-0-unstable-2024-04-26"
    "nvidia-x11"
    "nvidia-settings"
    "code"
    "vscode"
    "vscode-fhs"
    "p7zip-rar"
    "rar"
    "unrar"
  ];

  configurations.nixos.system76.module =
    { pkgs, ... }:
    {
      environment.systemPackages = lib.mkAfter (
        with pkgs;
        [
          # System76 hardware utilities
          system76-power
          system76-scheduler
          system76-firmware
          system76-wallpapers
          firmware-manager
          system76-keyboard-configurator
          (callPackage system76-ectool { }) # EC tool for fan control

          # PipeWire controls for selecting outputs and adjusting volume
          pavucontrol
          qpwgraph
          helvum

          # Audio production and codecs
          alsa-utils
          ardour
          audacity
          gst_all_1.gstreamer
          gst_all_1.gst-plugins-base
          gst_all_1.gst-plugins-good
          gst_all_1.gst-plugins-bad
          gst_all_1.gst-plugins-ugly

          # Diagnostics and stress testing utilities for crash triage
          lm_sensors
          smartmontools
          nvme-cli
          stress-ng
          memtester
          glmark2
          hwinfo
        ]
      );
    };
}
