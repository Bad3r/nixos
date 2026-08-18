# system76.gpu.intelBusId -> videoDecodeDevice (modules/system76/nvidia-gpu.nix) has
# regressed twice within this PR on bus/domain bounds alone, with `nix flake check`
# staying green each time, because no host overrides intelBusId away from its
# default so no eval ever exercised a boundary value. This forces the boundary
# table through the already-public option surface via extendModules, the same
# technique modules/configurations/nixos.nix uses for its fleet-key check, so no
# source hoist out of the host module's `let` is needed.
{ config, lib, ... }:
let
  system76 =
    config.flake.nixosConfigurations.system76
      or (throw "modules/system76/nvidia-gpu-checks.nix: flake.nixosConfigurations.system76 is missing");

  videoDecodeDeviceFor =
    intelBusId:
    (system76.extendModules { modules = [ { system76.gpu.intelBusId = intelBusId; } ]; })
    .config.system76.gpu.videoDecodeDevice;

  # tryEval only where a failure is the expected outcome (the reject rows below):
  # wrapping the accept rows in tryEval would also swallow an unrelated eval error
  # anywhere in the system76 closure, reporting it as "<eval failure>" and making
  # the reject rows pass vacuously instead of surfacing the real break.
  videoDecodeDeviceTryFor = intelBusId: builtins.tryEval (videoDecodeDeviceFor intelBusId);

  # Golden values captured from the current, reviewed derivation: the domain-0
  # default, an explicit non-zero domain, a domain widened past 0xffff, and the
  # three PCI field maxima (bus 255, device 31, function 7).
  acceptCases = {
    "PCI:0:2:0" = "/dev/dri/by-path/pci-0000:00:02.0-render";
    "PCI:2@1:3:4" = "/dev/dri/by-path/pci-0001:02:03.4-render";
    "PCI:0@65536:2:0" = "/dev/dri/by-path/pci-10000:00:02.0-render";
    "PCI:255:2:0" = "/dev/dri/by-path/pci-0000:ff:02.0-render";
    "PCI:0:31:0" = "/dev/dri/by-path/pci-0000:00:1f.0-render";
    "PCI:0:2:7" = "/dev/dri/by-path/pci-0000:00:02.7-render";
  };

  # One past the bus and device maxima, and past the regex's own function digit.
  rejectCases = [
    "PCI:256:2:0"
    "PCI:0:32:0"
    "PCI:0:2:9"
  ];

  acceptFailures = lib.filterAttrs (
    intelBusId: expected: videoDecodeDeviceFor intelBusId != expected
  ) acceptCases;

  rejectFailures = builtins.filter (
    intelBusId: (videoDecodeDeviceTryFor intelBusId).success
  ) rejectCases;

  acceptFailureLines = lib.mapAttrsToList (
    intelBusId: expected:
    "  ${intelBusId}: expected ${expected}, got ${videoDecodeDeviceFor intelBusId}"
  ) acceptFailures;

  rejectFailureLines = map (
    intelBusId: "  ${intelBusId}: expected to fail evaluation but succeeded"
  ) rejectFailures;

  failureLines = acceptFailureLines ++ rejectFailureLines;
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.system76-video-decode-device =
        # throw, not a failing derivation: CI forces this check's drvPath with
        # `nix eval` and never builds checks, so only an eval-time failure gates
        # CI (same rationale as modules/hosts/common/checks.nix).
        if failureLines != [ ] then
          throw (
            "system76-video-decode-device: system76.gpu.intelBusId -> videoDecodeDevice "
            + "boundary table regressed:\n"
            + lib.concatStringsSep "\n" failureLines
          )
        else
          pkgs.runCommandLocal "system76-video-decode-device-ok" { } ''
            echo "ok: system76.gpu.intelBusId -> videoDecodeDevice boundary table matches" > $out
          '';
    };
}
