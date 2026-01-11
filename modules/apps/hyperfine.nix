/*
  Package: hyperfine
  Description: Command-line benchmarking tool with statistical analysis and warmup runs.
  Homepage: https://github.com/sharkdp/hyperfine
  Documentation: https://github.com/sharkdp/hyperfine#readme
  Repository: https://github.com/sharkdp/hyperfine

  Summary:
    * Benchmarks shell commands with automatic warmups, statistical confidence intervals, and customizable output formats.
    * Supports baseline comparisons, exporting results to JSON/Markdown, and parameterized benchmarks for multiple inputs.

  Options:
    -w, --warmup <n>: Execute warmup runs before timing begins.
    -r, --runs <n>: Specify the number of benchmark runs (default: auto).
    -L <var> <values>: Run benchmarks over parameter lists (e.g. different input sizes).
    -p, --prepare <cmd>: Run a preparation command before each benchmark run.
    --export-json/--export-markdown <file>: Save benchmark results for reporting.

  Example Usage:
    * `hyperfine 'rg foo' 'ack foo'` — Compare ripgrep and ack for a search task.
    * `hyperfine -w 3 -r 10 'make clean {PRESERVED_DOCUMENTATION}{PRESERVED_DOCUMENTATION} make'` — Benchmark a build pipeline with warmup and specific run counts.
    * `hyperfine --export-json results.json 'python script.py'` — Save benchmark metrics for further analysis.
*/
_:
let
  HyperfineModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.hyperfine.extended;
    in
    {
      options.programs.hyperfine.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable hyperfine.";
        };

        package = lib.mkPackageOption pkgs "hyperfine" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.hyperfine = HyperfineModule;
}
