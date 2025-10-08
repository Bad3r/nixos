/**
  Nix module extraction tests
  Tests the module extraction and type parsing logic
*/

{ pkgs, lib, ... }:
let
  # Import the extraction module
  extractModules = import ../lib/extract-modules.nix { inherit lib pkgs; };

  # Test utilities
  assertEq =
    actual: expected: name:
    if actual == expected then
      true
    else
      throw "Test '${name}' failed: expected ${toString expected}, got ${toString actual}";

  assertType =
    value: expectedType: name:
    if builtins.typeOf value == expectedType then
      true
    else
      throw "Test '${name}' failed: expected type ${expectedType}, got ${builtins.typeOf value}";

  # Test cases
  testResults = {
    # Test 1: Basic type extraction
    testBasicTypeExtraction =
      let
        result = extractModules.extractType lib.types.str;
      in
      {
        assertion = result.type == "option-type" && result.name == "str" && result.description != null;
        message = "Basic type extraction should work for simple types";
      };

    # Test 2: Complex type extraction (attrsOf)
    testAttrsOfExtraction =
      let
        result = extractModules.extractType (lib.types.attrsOf lib.types.int);
      in
      {
        assertion =
          result.type == "option-type"
          && result.name == "attrsOf"
          && result.nestedType != null
          && result.nestedType.name == "int";
        message = "Should extract nested types from attrsOf";
      };

    # Test 3: ListOf type extraction
    testListOfExtraction =
      let
        result = extractModules.extractType (lib.types.listOf lib.types.bool);
      in
      {
        assertion =
          result.type == "option-type" && result.name == "listOf" && result.nestedType.name == "bool";
        message = "Should extract nested types from listOf";
      };

    # Test 4: Submodule extraction
    testSubmoduleExtraction =
      let
        submoduleType = lib.types.submodule {
          options = {
            foo = lib.mkOption {
              type = lib.types.str;
              description = "Foo option";
              default = "bar";
            };
            baz = lib.mkOption {
              type = lib.types.int;
              description = "Baz option";
            };
          };
        };
        result = extractModules.extractType submoduleType;
      in
      {
        assertion =
          result.type == "submodule"
          && result.options ? foo
          && result.options.foo.type.name == "str"
          && result.options.foo.description == "Foo option"
          && result.options.foo.default == "bar"
          && result.options ? baz
          && result.options.baz.type.name == "int";
        message = "Should extract complete submodule structure";
      };

    # Test 5: Either type extraction
    testEitherExtraction =
      let
        result = extractModules.extractType (lib.types.either lib.types.str lib.types.int);
      in
      {
        assertion =
          result.type == "option-type"
          && result.name == "either"
          && result.left != null
          && result.left.name == "str"
          && result.right != null
          && result.right.name == "int";
        message = "Should extract both sides of either type";
      };

    # Test 6: Null or type extraction
    testNullOrExtraction =
      let
        result = extractModules.extractType (lib.types.nullOr lib.types.path);
      in
      {
        assertion =
          result.type == "option-type" && result.name == "nullOr" && result.nestedType.name == "path";
        message = "Should extract nested type from nullOr";
      };

    # Test 7: Option extraction
    testOptionExtraction =
      let
        option = lib.mkOption {
          type = lib.types.str;
          default = "default-value";
          description = "Test option description";
          example = "example-value";
        };
        result = extractModules.extractOption "testOption" option;
      in
      {
        assertion =
          result.name == "testOption"
          && result.type.name == "str"
          && result.default == "default-value"
          && result.description == "Test option description"
          && result.example == "example-value";
        message = "Should extract complete option information";
      };

    # Test 8: Module evaluation
    testModuleEvaluation =
      let
        testModule = {
          options = {
            services.test = {
              enable = lib.mkEnableOption "test service";
              port = lib.mkOption {
                type = lib.types.port;
                default = 8080;
                description = "Port to listen on";
              };
              users = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "List of users";
              };
            };
          };
        };
        evaluated = lib.evalModules {
          modules = [ testModule ];
        };
        result = extractModules.extractModule evaluated;
      in
      {
        assertion =
          result.options ? "services.test.enable"
          && result.options."services.test.enable".type == "bool"
          && result.options."services.test.port".default == 8080
          && result.options."services.test.users".type == "listOf";
        message = "Should evaluate and extract complete module structure";
      };

    # Test 9: Recursive type handling
    testRecursiveTypes =
      let
        recursiveType = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
        result = extractModules.extractType recursiveType;
      in
      {
        assertion =
          result.type == "option-type"
          && result.name == "attrsOf"
          && result.nestedType.name == "attrsOf"
          && result.nestedType.nestedType.name == "str";
        message = "Should handle recursive nested types";
      };

    # Test 10: Enum type extraction
    testEnumExtraction =
      let
        result = extractModules.extractType (
          lib.types.enum [
            "foo"
            "bar"
            "baz"
          ]
        );
      in
      {
        assertion =
          result.type == "option-type"
          && result.name == "enum"
          &&
            result.values == [
              "foo"
              "bar"
              "baz"
            ];
        message = "Should extract enum values";
      };

    # Test 11: Function type handling
    testFunctionType =
      let
        result = extractModules.extractType (lib.types.functionTo lib.types.str);
      in
      {
        assertion =
          result.type == "option-type" && result.name == "functionTo" && result.returnType.name == "str";
        message = "Should handle function types";
      };

    # Test 12: Package type extraction
    testPackageType =
      let
        result = extractModules.extractType lib.types.package;
      in
      {
        assertion = result.type == "option-type" && result.name == "package" && result.check != null;
        message = "Should extract package type information";
      };

    # Test 13: Complex nested submodule
    testComplexNestedSubmodule =
      let
        complexType = lib.types.submodule {
          options = {
            networking = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  interfaces = lib.mkOption {
                    type = lib.types.attrsOf (
                      lib.types.submodule {
                        options = {
                          ipv4 = lib.mkOption {
                            type = lib.types.listOf lib.types.str;
                            default = [ ];
                          };
                          ipv6 = lib.mkOption {
                            type = lib.types.listOf lib.types.str;
                            default = [ ];
                          };
                        };
                      }
                    );
                  };
                };
              };
            };
          };
        };
        result = extractModules.extractType complexType;
      in
      {
        assertion =
          result.type == "submodule"
          && result.options.networking.type.type == "submodule"
          && result.options.networking.type.options.interfaces.type.name == "attrsOf";
        message = "Should handle deeply nested submodules";
      };

    # Test 14: Option with apply function
    testOptionWithApply =
      let
        option = lib.mkOption {
          type = lib.types.str;
          apply = x: lib.toUpper x;
          description = "String that gets uppercased";
        };
        result = extractModules.extractOption "test" option;
      in
      {
        assertion = result.hasApply == true && result.type.name == "str";
        message = "Should detect options with apply functions";
      };

    # Test 15: Read-only options
    testReadOnlyOption =
      let
        option = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          default = "immutable";
        };
        result = extractModules.extractOption "readonly" option;
      in
      {
        assertion = result.readOnly == true && result.default == "immutable";
        message = "Should detect read-only options";
      };

    # Test 16: Internal options
    testInternalOption =
      let
        option = lib.mkOption {
          type = lib.types.bool;
          internal = true;
          default = false;
        };
        result = extractModules.extractOption "internal" option;
      in
      {
        assertion = result.internal == true && result.visible == false;
        message = "Should detect internal options";
      };

    # Test 17: Option declarations
    testOptionDeclarations =
      let
        option = lib.mkOption {
          type = lib.types.int;
          description = "Test with declarations";
          declarations = [
            "${pkgs.path}/nixos/modules/services/test.nix"
          ];
        };
        result = extractModules.extractOption "declared" option;
      in
      {
        assertion =
          result.declarations != [ ] && lib.any (d: lib.hasInfix "test.nix" d.file) result.declarations;
        message = "Should extract option declarations";
      };

    # Test 18: Type with custom check
    testTypeWithCustomCheck =
      let
        customType = lib.types.addCheck lib.types.int (x: x > 0 && x < 100);
        result = extractModules.extractType customType;
      in
      {
        assertion = result.type == "option-type" && result.hasCheck == true;
        message = "Should detect types with custom checks";
      };

    # Test 19: Module imports handling
    testModuleImports =
      let
        moduleWithImports = {
          imports = [
            ./base.nix
            ./extended.nix
          ];
          options = {
            test.enable = lib.mkEnableOption "test";
          };
        };
        result = extractModules.extractModuleInfo moduleWithImports;
      in
      {
        assertion =
          result.imports == [
            "./base.nix"
            "./extended.nix"
          ]
          && result.options ? "test.enable";
        message = "Should extract module imports";
      };

    # Test 20: Batch extraction performance
    testBatchExtraction =
      let
        modules = lib.genList (i: {
          options."test${toString i}" = lib.mkOption {
            type = lib.types.str;
            default = "value${toString i}";
          };
        }) 100;

        startTime = builtins.currentTime;
        results = map extractModules.extractModuleInfo modules;
        endTime = builtins.currentTime;

        duration = endTime - startTime;
      in
      {
        assertion = builtins.length results == 100 && duration < 1000; # Should complete in under 1 second
        message = "Should handle batch extraction efficiently";
      };
  };

  # Run all tests
  runTests = lib.mapAttrs (
    name: test:
    assert test.assertion or (throw "Test ${name} failed: ${test.message}");
    {
      inherit name;
      success = true;
      message = test.message;
    }
  ) testResults;

  # Aggregate test results
  allTestsPassed = lib.all (test: test.success) (lib.attrValues runTests);

in
{
  # Export test results
  inherit runTests allTestsPassed;

  # Create test runner derivation
  checks.moduleExtraction =
    pkgs.runCommand "module-extraction-tests"
      {
        buildInputs = with pkgs; [ nix ];
      }
      ''
        echo "Running NixOS module extraction tests..."

        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: test: ''
            echo "✓ ${name}: ${test.message}"
          '') runTests
        )}

        echo ""
        echo "All ${toString (lib.length (lib.attrNames runTests))} tests passed!"

        touch $out
      '';

  # Export for use in CI
  testSuite = {
    name = "nixos-module-extraction";
    tests = runTests;
    passed = allTestsPassed;
    count = lib.length (lib.attrNames runTests);
  };
}
