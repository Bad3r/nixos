_: {
  # Provide default configuration for nektos/act
  # - Install configuration file in repo root via files module
  perSystem =
    { pkgs, ... }:
    {
      files.files = [
        {
          path_ = ".actrc";
          drv = pkgs.writeText ".actrc" ''
            # Map ubuntu-latest to latest LTS (24.04) tag on GHCR
            -P ubuntu-latest=ghcr.io/catthehacker/ubuntu:act-24.04

            # Default workflows directory
            -W .github/workflows
          '';
        }
      ];
    };
}
