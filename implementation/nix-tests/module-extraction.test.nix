/**
  Nix module extraction tests
  Tests the module extraction and type parsing logic
*/

{ pkgs, lib, ... }:
let
  moduleDocLib = import ../module-docs/lib { inherit lib; };

  # Test cases
  testResults = {
    # Test 1: Basic type extraction
    testBasicTypeExtraction =
      let
        result = moduleDocLib.extractType lib.types.str;
      in
      {
        assertion = result.type == "option-type" && result.name == "str" && result.description != null;
        message = "Basic type extraction should work for simple types";
      };

    # Test 2: Complex type extraction (attrsOf)
    testAttrsOfExtraction =
      let
        result = moduleDocLib.extractType (lib.types.attrsOf lib.types.int);
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
        result = moduleDocLib.extractType (lib.types.listOf lib.types.bool);
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
        result = moduleDocLib.extractType submoduleType;
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
        result = moduleDocLib.extractType (lib.types.either lib.types.str lib.types.int);
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
        result = moduleDocLib.extractType (lib.types.nullOr lib.types.path);
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
        result = moduleDocLib.extractOption "testOption" option;
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
        result = moduleDocLib.extractModule evaluated;
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
        result = moduleDocLib.extractType recursiveType;
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
        result = moduleDocLib.extractType (
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
        result = moduleDocLib.extractType (lib.types.functionTo lib.types.str);
      in
      {
        assertion =
          result.type == "option-type" && result.name == "functionTo" && result.returnType.name == "str";
        message = "Should handle function types";
      };

    # Test 12: Package type extraction
    testPackageType =
      let
        result = moduleDocLib.extractType lib.types.package;
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
        result = moduleDocLib.extractType complexType;
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
        result = moduleDocLib.extractOption "test" option;
      in
      {
        assertion = result.hasApply && result.type.name == "str";
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
        result = moduleDocLib.extractOption "readonly" option;
      in
      {
        assertion = result.readOnly && result.default == "immutable";
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
        result = moduleDocLib.extractOption "internal" option;
      in
      {
        assertion = result.internal && !result.visible;
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
        result = moduleDocLib.extractOption "declared" option;
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
        result = moduleDocLib.extractType customType;
      in
      {
        assertion = result.type == "option-type" && result.check != null;
        message = "Should detect types with custom checks";
      };

    # Test 21: Extract from evaluated module
    testEvaluatedModuleExtraction =
      let
        sampleModule = {
          options.example = lib.mkOption {
            type = lib.types.str;
            description = "Example option";
            default = "value";
          };
        };
        evaluated = lib.evalModules {
          modules = [ sampleModule ];
          specialArgs = {
            inherit lib pkgs;
          };
        };
        doc = moduleDocLib.extractModule evaluated;
      in
      {
        assertion =
          doc.options ? example
          && doc.options.example.description == "Example option"
          && doc.options.example.default == "value";
        message = "Should extract options from an evaluated module";
      };
  };

  # Run all tests
  runTests = lib.mapAttrs (
    name: test:
    assert test.assertion or (throw "Test ${name} failed: ${test.message}");
    {
      inherit name;
      success = true;
      inherit (test) message;
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
