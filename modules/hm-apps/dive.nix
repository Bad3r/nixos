/*
  Package: dive
  Description: Tool for exploring each layer in a docker image.
  Homepage: https://github.com/wagoodman/dive
  Documentation: https://github.com/wagoodman/dive#readme
  Repository: https://github.com/wagoodman/dive

  Summary:
    * Analyzes container image layers to show file changes, build inefficiencies, and potential wasted space.
    * Supports CI gating via efficiency scores, layer-by-layer comparisons, and integration with registries or tarballs.

  Options:
    dive <image>: Inspect a locally available image (Docker, Podman, or tarball).
    dive --ci <image>: Run in CI mode and exit non-zero when the efficiency score violates thresholds.
    dive --config <file>: Use an alternate YAML configuration.
    dive --highestWastedBytes: Sort layers by wasted space.
    dive --export <path>: Write layer analysis results to a JSON file.

  Example Usage:
    * `dive nginx:latest` — Explore filesystem changes per layer in an interactive TUI.
    * `dive --ci myapp:sha-92af` — Enforce size budgets within a continuous integration pipeline.
    * `dive --export report.json alpine:3.20` — Save analysis data for sharing or automation.
*/

{
  flake.homeManagerModules.apps.dive =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.dive ];
    };
}
