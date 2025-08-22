# Dive -:
# This tool provides a way to discover and explore the contents of a docker image. Additionally the tool estimates
# the amount of wasted space and identifies the offending files from the image.

# Usage:
#   dive [IMAGE] [flags]
#   dive [command]

# Available Commands:
#   build       Builds and analyzes a docker image from a Dockerfile (this is a thin wrapper for the `docker build` command).
#   completion  Generate the autocompletion script for the specified shell
#   help        Help about any command
#   version     print the version number and exit (also --version)
{
  flake.modules.homeManager.base =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        dive
      ];
    };
}
