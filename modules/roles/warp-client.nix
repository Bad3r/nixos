{
  # Role: Cloudflare WARP client
  #
  # Enables the Cloudflare Zero Trust client daemon (`warp-svc`) and opens the
  # required UDP port in the firewall. Intended to be imported only by selected
  # hosts (e.g., laptops/dev machines) via modules/configurations/nixos.nix.
  #
  # Docs:
  # - WARP on Linux: https://developers.cloudflare.com/warp-client/get-started/linux/
  # - Firewall ports: https://developers.cloudflare.com/cloudflare-one/connections/connect-devices/warp/deployment/firewall/
  flake.nixosModules."warp-client" = _: {
    services.cloudflare-warp = {
      enable = true;
      openFirewall = true; # opens UDP 2408
    };
  };
}
