{ lib }:

let
  mkRoot =
    {
      id,
      namespace,
      subroles,
      defaultSubroles ? [ ],
      allowVendor ? false,
      reservedSubroles ? [ ],
      notes ? "",
    }:
    {
      inherit
        id
        namespace
        subroles
        defaultSubroles
        allowVendor
        reservedSubroles
        notes
        ;
    };
in
{
  maxSegments = 3;
  vendorSegment = "vendor";

  canonicalRoots = {
    audio-video = mkRoot {
      id = "AudioVideo";
      namespace = "roles.audio-video";
      subroles = [
        "media"
        "production"
        "streaming"
      ];
      defaultSubroles = [ "media" ];
      notes = "Covers multimedia playback and creation workflows.";
    };

    development = mkRoot {
      id = "Development";
      namespace = "roles.development";
      subroles = [
        "core"
        "python"
        "go"
        "rust"
        "clojure"
        "ai"
      ];
      defaultSubroles = [ "core" ];
      notes = "Language toolchains, debuggers, and shared developer tooling.";
    };

    education = mkRoot {
      id = "Education";
      namespace = "roles.education";
      subroles = [
        "research"
        "learning-tools"
      ];
      notes = "Reserved for future study/learning bundles.";
    };

    game = mkRoot {
      id = "Game";
      namespace = "roles.game";
      subroles = [
        "launchers"
        "tools"
        "emulation"
      ];
      defaultSubroles = [ "launchers" ];
    };

    graphics = mkRoot {
      id = "Graphics";
      namespace = "roles.graphics";
      subroles = [
        "illustration"
        "cad"
        "photography"
      ];
    };

    network = mkRoot {
      id = "Network";
      namespace = "roles.network";
      subroles = [
        "sharing"
        "tools"
        "remote-access"
        "services"
      ];
      allowVendor = true;
      notes = "Networking utilities and integrations (Cloudflare lives under vendor).";
    };

    office = mkRoot {
      id = "Office";
      namespace = "roles.office";
      subroles = [
        "productivity"
        "planning"
      ];
    };

    science = mkRoot {
      id = "Science";
      namespace = "roles.science";
      subroles = [
        "data"
        "visualisation"
      ];
    };

    system = mkRoot {
      id = "System";
      namespace = "roles.system";
      subroles = [
        "base"
        "display.x11"
        "storage"
        "security"
        "prospect"
      ];
      allowVendor = true;
      reservedSubroles = [ "prospect" ];
      notes = "Core OS roles, workstation snapshot, and vendor hardware hooks.";
    };

    utility = mkRoot {
      id = "Utility";
      namespace = "roles.utility";
      subroles = [
        "cli"
        "archive"
        "monitoring"
      ];
    };
  };

  canonicalRootsList = lib.attrValues canonicalRoots;
}
