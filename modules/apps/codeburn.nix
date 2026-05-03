/*
  Package: codeburn
  Description: Interactive TUI dashboard for AI coding token cost observability across Claude Code, Codex, Cursor, OpenCode, Pi, and Copilot.
  Homepage: https://github.com/getagentseal/codeburn
  Documentation: https://github.com/getagentseal/codeburn#readme
  Repository: https://github.com/getagentseal/codeburn

  Summary:
    * Local-first dashboard that reads provider session transcripts and prices each turn against a bundled LiteLLM snapshot (no proxy, no API keys).
    * Classifies every turn into 13 task categories and tracks one-shot edit success rate, plan overage, and outcome (shipped vs reverted vs abandoned).

  Options:
    report: Interactive usage dashboard with provider, period, and currency toggles.
    today: Single-day usage breakdown.
    month: Current-month usage breakdown.
    status: Compact today plus week plus month line for status bars.
    export: Emit usage data as CSV or JSON for downstream tooling.
    optimize: Scan sessions and Claude Code config for waste patterns and fixes.
    yield: Correlate AI spend with git history to label outcomes (experimental).

  Notes:
    * Custom package built from getagentseal/codeburn via packages/codeburn (buildNpmPackage on Node 22).
    * Upstream build script downloads LiteLLM prices over the network; the derivation patches package.json to skip that step and uses the snapshot already committed at src/data/litellm-snapshot.json.
*/
_:
let
  CodeburnModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.codeburn.extended;
    in
    {
      options.programs.codeburn.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable codeburn.";
        };

        package = lib.mkPackageOption pkgs "codeburn" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.codeburn = CodeburnModule;
}
