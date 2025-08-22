## NixOS Tests

**Table of Contents**

[Writing Tests](#sec-writing-nixos-tests)

[Running Tests](#sec-running-nixos-tests)

[Running Tests interactively](#sec-running-nixos-tests-interactively)

[Linking NixOS tests to packages](#sec-linking-nixos-tests-to-packages)

[Testing Hardware Features](#sec-nixos-test-testing-hardware-features)

When you add some feature to NixOS, you should write a test for it. NixOS tests are kept in the directory `nixos/tests`, and are executed (using Nix) by a testing framework that automatically starts one or more virtual machines containing the NixOS system(s) required for the test.
