# Small fixtures keep CI's evaluation and runtime selection coverage explicit.
let
  planFor = import ../check-compliance.nix;
  host = {
    drvPath = "/nix/store/host.drv";
  };
  ordinary = {
    drvPath = "/nix/store/ordinary.drv";
  };
  runtime = {
    drvPath = "/nix/store/runtime.drv";
    runtimeCheck = true;
  };
  script = {
    drvPath = "/nix/store/script.drv";
    runtimeCheck = false;
  };
  fixtures = {
    "configurations/nixos/example" = host;
    "ordinary" = ordinary;
    "runtime/with-slash" = runtime;
    "script-tests-example" = script;
  };
  plan = planFor fixtures;
  succeeds = value: (builtins.tryEval (builtins.deepSeq value true)).success;
  expect =
    name: condition: if condition then true else throw "compliance plan fixture failed: ${name}";
  targetFor =
    check:
    builtins.head
      (planFor {
        "configurations/nixos/example" = host;
        runtime = runtime // check;
      }).runtimeChecks;
  # Compare derivations independently from the output selection fixtures below.
  runtimePaths = map (target: builtins.head (builtins.split "\\^" target)) plan.runtimeChecks;
  tests = {
    all-checks = expect "all check drvPaths survive serialization" (
      plan.checks == builtins.mapAttrs (_: check: check.drvPath) fixtures
      && succeeds (builtins.toJSON plan)
    );
    host-coverage = expect "host checks are retained" (
      plan.hosts == [ "configurations/nixos/example" ]
    );
    runtime-selection = expect "runtime flags and script prefixes both select checks" (
      runtimePaths == [
        runtime.drvPath
        script.drvPath
      ]
    );
    ordinary-excluded = expect "ordinary and host checks are not built" (
      !(builtins.elem ordinary.drvPath runtimePaths) && !(builtins.elem host.drvPath runtimePaths)
    );
    default-output = expect "runtime checks default to out" (targetFor { } == "${runtime.drvPath}^out");
    selected-output = expect "outputsToInstall is preserved" (
      targetFor { meta.outputsToInstall = [ "dev" ]; } == "${runtime.drvPath}^dev"
    );
    multiple-outputs = expect "multiple outputsToInstall are preserved" (
      targetFor {
        meta.outputsToInstall = [
          "out"
          "dev"
        ];
      } == "${runtime.drvPath}^out,dev"
    );
    explicit-output = expect "an explicitly selected output overrides outputsToInstall" (
      targetFor {
        outputSpecified = true;
        outputName = "doc";
        meta.outputsToInstall = [
          "out"
          "dev"
        ];
      } == "${runtime.drvPath}^doc"
    );
    empty-outputs = expect "an empty output selection fails" (
      !(succeeds (targetFor {
        meta.outputsToInstall = [ ];
      }))
    );
    failing-ordinary = expect "a failing non-runtime drvPath fails evaluation" (
      !(succeeds (
        builtins.toJSON (
          planFor (
            fixtures
            // {
              ordinary.drvPath = throw "broken ordinary check";
            }
          )
        )
      ))
    );
    failing-host = expect "a failing host drvPath fails evaluation" (
      !(succeeds (
        builtins.toJSON (
          planFor (
            fixtures
            // {
              "configurations/nixos/example".drvPath = throw "broken host check";
            }
          )
        )
      ))
    );
    empty-hosts = expect "an empty host list fails" (
      !(succeeds (planFor {
        "runtime/with-slash" = runtime;
      }))
    );
    empty-host-name = expect "a bare host prefix does not count as a host" (
      !(succeeds (planFor {
        "configurations/nixos/" = host;
        "runtime/with-slash" = runtime;
      }))
    );
    empty-runtime = expect "an empty runtime list fails" (
      !(succeeds (planFor {
        "configurations/nixos/example" = host;
        inherit ordinary;
      }))
    );
    empty-checks = expect "an empty check set fails" (!(succeeds (planFor { })));
  };
in
builtins.deepSeq tests true
