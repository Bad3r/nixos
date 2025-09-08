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
            # Default platform images (catthehacker) to match GitHub runners
            -P ubuntu-latest=catthehacker/ubuntu:act-latest
            -P ubuntu-24.04=catthehacker/ubuntu:act-24.04
            -P ubuntu-22.04=catthehacker/ubuntu:act-22.04
            -P ubuntu-20.04=catthehacker/ubuntu:act-20.04

            # Default workflows directory
            -W .github/workflows
          '';
        }
      ];
    };
}
