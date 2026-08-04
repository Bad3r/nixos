/*
  Package: jupyter-all
  Description: Jupyter wrapper bundling JupyterLab, the classic notebook server, and a curated set of language kernels.
  Homepage: https://jupyter.org/
  Documentation: https://docs.jupyter.org/
  Repository: https://github.com/jupyter/notebook

  Summary:
    * Provides a single environment with `jupyter`, `jupyter-lab`, `jupyter-notebook`, `jupyter-console`, `jupyter-nbconvert`, and `ipython` entry points.
    * Ships Clojure (Clojupyter), Octave, R (Ark), and Ruby (IRuby) kernels through the nixpkgs override; the Python kernelspec comes from ipykernel in the environment itself, not from the override.

  Options:
    notebook: Launch the classic web-based Jupyter Notebook server.
    lab: Start the JupyterLab next-generation notebook IDE.
    console: Open a terminal-based interactive kernel session.
    nbconvert <input>: Convert notebooks to HTML, PDF, slides, Markdown, scripts, or other formats.
    kernelspec <subcommand>: Manage installed Jupyter kernels (list, install, remove, provision).
    server: Run only the headless Jupyter server backend without a UI.

  Notes:
    * `jupyter-all` is `jupyter.override` from nixpkgs that swaps the default kernel definition set for the Clojure, Octave, R, and Ruby ones.
    * The Wolfram kernel is intentionally excluded upstream because it is unfree.
    * Every kernelspec the wrapper can reach is re-exported on JUPYTER_PATH so external clients such as the VS Code Jupyter extension can launch them.
*/
_:
let
  JupyterAllModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."jupyter-all".extended;

      # The kernels named in the override land in a standalone
      # jupyter-kernel.create output that only the wrapped `jupyter` binary
      # knows about, through its own JUPYTER_PATH. Resolve that directory
      # through the wrapper instead of restating upstream's definition list.
      #
      # python3 is absent from that set: jupyter-all replaces the definitions
      # instead of extending them, so upstream drops jupyter-kernel.default
      # and its absolute interpreter argv. The only surviving Python
      # kernelspec is ipykernel's own, whose argv[0] is the bare string
      # "python". That resolves through PATH, and outside the wrapper PATH
      # yields programs.python.extended's hiPrio python313, which has no
      # ipykernel. Only kernel.json needs rewriting; buildEnv unfolds the
      # python3 directory and links ipykernel's logos next to it.
      kernelspecs =
        pkgs.runCommand "jupyter-all-kernelspecs"
          {
            nativeBuildInputs = [ pkgs.jq ];
          }
          ''
            ${cfg.package}/bin/python -c 'import ipykernel_launcher'

            wrapperData=$(${cfg.package}/bin/jupyter --paths --json | jq -r '.data[0]')

            # jupyter_path() lists JUPYTER_PATH ahead of sys.prefix, so data[0]
            # landing on the environment itself means the injected entry is
            # gone and the copy below would re-export ipykernel's relative-argv
            # spec and nothing else.
            if [ "$wrapperData" = "${cfg.package}/share/jupyter" ]; then
              echo "jupyter --paths resolved data[0] to the environment ($wrapperData), not the wrapper kernel dir" >&2
              exit 1
            fi

            install -d "$out/share/jupyter"
            cp -R "$wrapperData/kernels" "$out/share/jupyter/kernels"
            chmod -R u+w "$out/share/jupyter/kernels"

            install -d "$out/share/jupyter/kernels/python3"
            jq --arg interpreter '${cfg.package}/bin/python' '.argv[0] = $interpreter' \
              ${cfg.package}/share/jupyter/kernels/python3/kernel.json \
              > "$out/share/jupyter/kernels/python3/kernel.json"
          '';
    in
    {
      options.programs."jupyter-all".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable jupyter-all.";
        };

        package = lib.mkPackageOption pkgs "jupyter-all" { };
      };

      config = lib.mkIf cfg.enable {
        environment = {
          # hiPrio so the absolute-argv kernel.json wins the system-path
          # collision against the copy bundled in cfg.package.
          systemPackages = [
            cfg.package
            (lib.hiPrio kernelspecs)
          ];

          # NixOS links no /share/jupyter by default, so kernelspecs stay
          # reachable only through the wrapped `jupyter` binary, which sets
          # JUPYTER_PATH itself. Exported through sessionVariables
          # (PAM-initialised) rather than variables (shell-profile only) so
          # editors started from the desktop inherit it. A singleton list so a
          # second definition merges into the colon-joined value instead of
          # conflicting.
          pathsToLink = [ "/share/jupyter" ];
          sessionVariables.JUPYTER_PATH = [ "/run/current-system/sw/share/jupyter" ];
        };
      };
    };
in
{
  flake.nixosModules.apps.jupyter-all = JupyterAllModule;
}
