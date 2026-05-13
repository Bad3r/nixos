{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

let
  pin = lib.importJSON ./hashes.json;
in
rustPlatform.buildRustPackage rec {
  pname = "searchfox-cli";
  inherit (pin) version;

  src = fetchFromGitHub {
    owner = "padenot";
    repo = "searchfox-cli";
    rev = "v${version}";
    hash = pin.srcHash;
  };

  inherit (pin) cargoHash;

  # These integration tests query live searchfox.org endpoints. Keep the
  # offline unit tests and query-construction integration tests enabled.
  checkFlags = [
    "--skip=calls_from_returns_results"
    "--skip=can_gc_fully_qualified_can_gc"
    "--skip=can_gc_fully_qualified_cannot_gc"
    "--skip=can_gc_partial_name_resolves"
    "--skip=can_gc_unknown_symbol_returns_empty"
    "--skip=find_definition_c_function_without_namespace"
    "--skip=find_definition_returns_result"
    "--skip=find_definition_unknown_symbol_returns_empty"
    "--skip=get_file_nonexistent_returns_error"
    "--skip=get_file_returns_content"
    "--skip=get_head_hash_returns_valid_hash"
    "--skip=search_category_filter_excludes_tests"
    "--skip=search_id_returns_results"
    "--skip=search_path_only_returns_files"
    "--skip=search_text_returns_results"
  ];

  passthru.updateScript = ./update.py;

  meta = {
    description = "CLI for https://searchfox.org";
    homepage = "https://github.com/padenot/searchfox-cli";
    changelog = "https://github.com/padenot/searchfox-cli/releases/tag/v${version}";
    license = with lib.licenses; [
      asl20
      mit
    ];
    mainProgram = "searchfox-cli";
    platforms = lib.platforms.unix;
  };
}
