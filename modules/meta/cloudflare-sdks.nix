{ inputs, config, ... }:
{
  # Expose official Cloudflare language SDK source trees via flake packages
  # so they are discoverable from this repository. These are not built
  # libraries; they are convenient source exports you can import into your
  # language workflows or vendor into projects.
  #
  # SDKs:
  # - Go: https://github.com/cloudflare/cloudflare-go
  # - Rust (API): https://github.com/cloudflare/cloudflare-rs
  # - Rust (Workers): https://github.com/cloudflare/workers-rs
  # - Python: https://github.com/cloudflare/cloudflare-python
  # - Node.js: https://github.com/cloudflare/node-cloudflare
  #
  # Usage hints:
  # - Go:   go get github.com/cloudflare/cloudflare-go
  # - Rust: cargo add cloudflare = "*"   (API client)
  #         cargo add worker-build --build (Workers helper)
  # - Py:   uv add cloudflare   (or pip install cloudflare)
  # - Node: npm i cloudflare
  #
  # These src packages are included in systemPackages for easy discovery;
  # they don’t change your language dependency resolution.
  perSystem =
    { pkgs, ... }:
    let
      mkSrc =
        name: src:
        pkgs.runCommandNoCC name { } ''
          mkdir -p "$out"
          cp -R --no-preserve=mode,ownership,timestamps "${src}" "$out/src"
        '';
    in
    {
      packages = {
        cloudflare-go-src = mkSrc "cloudflare-go-src" inputs.cloudflare-go;
        cloudflare-python-src = mkSrc "cloudflare-python-src" inputs.cloudflare-python;
        cloudflare-rs-src = mkSrc "cloudflare-rs-src" inputs.cloudflare-rs;
        node-cloudflare-src = mkSrc "node-cloudflare-src" inputs.node-cloudflare;
        workers-rs-src = mkSrc "workers-rs-src" inputs.workers-rs;
      };
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        config.flake.packages.${pkgs.system}.cloudflare-go-src
        config.flake.packages.${pkgs.system}.cloudflare-python-src
        config.flake.packages.${pkgs.system}.cloudflare-rs-src
        config.flake.packages.${pkgs.system}.node-cloudflare-src
        config.flake.packages.${pkgs.system}.workers-rs-src
      ];

      # Friendly notice with pointers
      assertions = [
        {
          assertion = true;
          message = ''
            Cloudflare SDK sources are exposed under flake packages.
            See SDK repos for language-specific install instructions.
          '';
        }
      ];
    };
}
