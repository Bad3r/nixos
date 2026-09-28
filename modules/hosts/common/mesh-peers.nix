# Non-NixOS Cloudflare WARP Mesh peers: devices with an encrypted
# mesh.hosts.<name> address in secrets/cloudflare-warp.yaml but no
# modules/<host>/policy.nix of their own, so they self-register here
# instead of in modules/hosts/common/registry.nix (shareCommon only).
_: {
  flake.lib.nixos.hosts.iphone.cloudflareWarpMeshAddressReady = true;
}
