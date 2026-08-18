# The two new branches modules/system76/nvidia-gpu.nix added (the intelBusId ->
# videoDecodeDevice bus/domain arithmetic, and the CHROME_EXTRA_FLAGS quote/append
# encoder) have each regressed twice within this PR, both times with `nix flake
# check` staying green: bus/domain bounds (2a28268d, then 5c3cad05 after review
# found bus > 255 still aborted inside lib.fixedWidthString naming lib instead of
# the option), and the encoder (dba4c22f double quote, 76a4c847 line break). No
# host overrides intelBusId or chromeExtraFlags away from their defaults, so no
# eval has ever exercised either branch beyond its default input. This forces both
# through the already-public option surface via extendModules, the same technique
# modules/configurations/nixos.nix uses for its fleet-key check, so no source
# hoist out of the host module's `let` is needed.
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

  # The CHROME_EXTRA_FLAGS encoder is the other new branch in nvidia-gpu.nix, and it
  # has corrupted /etc/pam/environment twice in this PR (double quote in dba4c22f,
  # then an embedded line break in 76a4c847). Reading the rendered variable back
  # through the same extendModules handle pins the encoding and the append-last
  # ordering (d6007d14) without forcing config.assertions, which is a whole-system
  # list and would drag in unrelated modules' entries.
  chromeExtraFlagsFor =
    flags:
    (system76.extendModules { modules = [ { system76.gpu.chromeExtraFlags = flags; } ]; })
    .config.environment.sessionVariables.CHROME_EXTRA_FLAGS;

  defaultRenderFlag = "--hardware-video-device-path=/dev/dri/by-path/pci-0000:00:02.0-render";

  chromeFlagCases = [
    {
      flags = [ ];
      expected = defaultRenderFlag;
    }
    {
      flags = [ "--ozone-platform-hint=auto" ];
      expected = "--ozone-platform-hint=auto ${defaultRenderFlag}";
    }
    {
      flags = [ "--host-resolver-rules=MAP * 127.0.0.1" ];
      expected = "'--host-resolver-rules=MAP * 127.0.0.1' ${defaultRenderFlag}";
    }
    {
      # The derived flag must still win last-occurrence over a same-named
      # user-supplied entry: the ordering d6007d14 fixed.
      flags = [ "--hardware-video-device-path=/tmp/other" ];
      expected = "--hardware-video-device-path=/tmp/other ${defaultRenderFlag}";
    }
  ];

  chromeFailures = builtins.filter (
    case: chromeExtraFlagsFor case.flags != case.expected
  ) chromeFlagCases;

  chromeFailureLines = map (
    case:
    "  chromeExtraFlags ${builtins.toJSON case.flags}: expected ${case.expected}, got "
    + chromeExtraFlagsFor case.flags
  ) chromeFailures;

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

  failureLines = acceptFailureLines ++ rejectFailureLines ++ chromeFailureLines;
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
            "system76-video-decode-device: system76.gpu derivation regressed "
            + "(videoDecodeDevice boundary table and/or CHROME_EXTRA_FLAGS encoding):\n"
            + lib.concatStringsSep "\n" failureLines
          )
        else
          pkgs.runCommandLocal "system76-video-decode-device-ok" { } ''
            echo "ok: system76.gpu videoDecodeDevice boundary table and CHROME_EXTRA_FLAGS encoding match" > $out
          '';
    };
}
