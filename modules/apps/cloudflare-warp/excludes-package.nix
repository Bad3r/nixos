# Split-tunnel entries every WARP device profile excludes, applied with
# `nix run .#cloudflare-warp-excludes -- --apply`. Entries that name a private
# destination live encrypted under <host>.exclude in secrets/cloudflare-warp.yaml.
_:
let
  # Cloudflare's stock list, with 100.64.0.0/10 split around the Mesh
  # allocation so Mesh traffic stays in the tunnel (modules/hosts/common/firewall.nix).
  baseExcludes =
    map (address: { inherit address; }) [
      "10.0.0.0/8"
      "169.254.0.0/16"
      "172.16.0.0/12"
      "192.0.0.0/24"
      "192.168.0.0/16"
      "224.0.0.0/24"
      "240.0.0.0/4"
      "255.255.255.255/32"
      "fc00::/7"
      "fd00::/8"
      "fe80::/10"
      "ff01::/16"
      "ff02::/16"
      "ff03::/16"
      "ff04::/16"
      "ff05::/16"
    ]
    ++ [
      {
        address = "100.64.0.0/11";
        description = "CGNAT below the Cloudflare Mesh range";
      }
      {
        address = "100.112.0.0/12";
        description = "CGNAT above the Cloudflare Mesh range";
      }
      {
        address = "239.255.255.250/32";
        description = "SSDP";
      }
    ]
    ++
      map
        (address: {
          inherit address;
          description = "Apple services";
        })
        [
          "17.57.144.0/22"
          "17.188.20.0/23"
          "17.188.128.0/18"
          "17.249.0.0/16"
          "17.252.0.0/16"
        ];
in
{
  perSystem =
    { pkgs, ... }:
    {
      packages.cloudflare-warp-excludes = pkgs.writeShellApplication {
        name = "cloudflare-warp-excludes";
        runtimeInputs = with pkgs; [
          curl
          jq
          sops
        ];
        runtimeEnv.CLOUDFLARE_WARP_BASE_EXCLUDES = "${pkgs.writeText "cloudflare-warp-base-excludes.json" (
          builtins.toJSON baseExcludes
        )}";
        text = builtins.readFile ../../../scripts/cloudflare-warp-excludes.sh;
      };
    };
}
