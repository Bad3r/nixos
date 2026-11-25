{ inputs, ... }:
{
  flake.lib.agents._internal.skills.packs = {
    cloudflare = {
      src = "${inputs.cloudflare-skills}/skills";
      clients = [
        "antigravity"
        "claude"
        "codex"
      ];
    };

    modern-web-guidance = {
      src = "${inputs.modern-web-guidance}/skills";
      clients = [
        "antigravity"
        "claude"
        "codex"
      ];
    };
  };
}
