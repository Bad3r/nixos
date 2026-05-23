#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="${SCRIPT_DIR}/../../scripts/check-maintained-inputs.sh"
export CHECK_MAINTAINED_INPUTS_NIX_EVAL_FLAGS="--override-input example path:./example --override-input nixpkgs path:./nixpkgs"

if [[ ! -x ${SUT} ]]; then
  printf 'run.sh: SUT not executable at %s\n' "${SUT}" >&2
  exit 2
fi

if ! command -v nix >/dev/null; then
  printf 'run.sh: nix is required to evaluate the inventory module\n' >&2
  exit 2
fi

tmpdir="$(mktemp -d)"
cleanup() {
  if [[ -d ${tmpdir} ]]; then
    chmod -R u+w "${tmpdir}"
    rm -r "${tmpdir}"
  fi
}
trap cleanup EXIT

LOCK_BASE='{
  "nodes": {
    "root": {
      "inputs": {
        "example": "example",
        "nixpkgs": "nixpkgs"
      }
    },
    "example": {
      "inputs": {
        "nixpkgs": ["nixpkgs"]
      },
      "locked": {
        "rev": "0000000000000000000000000000000000000000",
        "type": "github",
        "owner": "example",
        "repo": "example"
      },
      "original": {
        "owner": "example",
        "repo": "example",
        "type": "github"
      }
    },
    "nixpkgs": {
      "locked": {
        "rev": "0000000000000000000000000000000000000000",
        "type": "github",
        "owner": "NixOS",
        "repo": "nixpkgs"
      },
      "original": {
        "owner": "NixOS",
        "repo": "nixpkgs",
        "type": "github"
      }
    }
  },
  "root": "root",
  "version": 7
}'

INVENTORY_FULL='_: {
  flake.lib.meta.maintainedInputs = {
    example = {
      flakeInput = "example";
      upstream = {
        url = "https://example.invalid/example.git";
        ref = "main";
      };
      sourceMode = "local-override";
      local.pathEnv = "EXAMPLE_CHECKOUT";
      follows.nixpkgs = "nixpkgs";
      lockGraph.inputNames = [ "nixpkgs" ];
      checks = [
        "clean-checkout"
        "no-local-url"
        "follows-preserved"
        "lock-graph"
      ];
    };
  };
}'

INVENTORY_EMPTY='_: {
  flake.lib.meta.maintainedInputs = { };
}'

FLAKE_NIX_CLEAN='{
  inputs = {
    example.url = "github:example/example";
    nixpkgs.url = "github:NixOS/nixpkgs";
  };
  outputs = _: { lib = (import ./modules/meta/maintained-inputs.nix {}).flake.lib; };
}'

init_fixture() {
  local name fixture
  name="$1"
  fixture="${tmpdir}/${name}"
  mkdir -p "${fixture}/modules/meta"
  mkdir -p "${fixture}/example" "${fixture}/nixpkgs"
  echo "{ outputs = _: {}; }" >"${fixture}/example/flake.nix"
  echo "{ outputs = _: {}; }" >"${fixture}/nixpkgs/flake.nix"
  git init -q "${fixture}"
  git -C "${fixture}" config user.email "tests@example.invalid"
  git -C "${fixture}" config user.name "check-maintained-inputs tests"
  git -C "${fixture}" commit --allow-empty -q -m init
  printf '%s' "${fixture}"
}

write_file() {
  printf '%s' "$2" >"$1"
}

run_sut() {
  local fixture exit_code
  fixture="$1"
  shift
  git -C "${fixture}" add flake.nix flake.lock modules/meta/maintained-inputs.nix example/flake.nix nixpkgs/flake.nix
  set +e
  (cd "${fixture}" && "${SUT}" "$@") >"${fixture}/stdout" 2>"${fixture}/stderr"
  exit_code=$?
  set -e
  printf '%s' "${exit_code}"
}

dump_stderr() {
  local label fixture
  label="$1"
  fixture="$2"
  printf '  %s stderr:\n' "${label}" >&2
  sed 's/^/    /' "${fixture}/stderr" >&2
}

assert_pass() {
  local label fixture exit_code
  label="$1"
  fixture="$2"
  exit_code="$3"
  if [[ ${exit_code} -ne 0 ]]; then
    printf 'FAIL: %s expected exit 0, got %s\n' "${label}" "${exit_code}" >&2
    dump_stderr "${label}" "${fixture}"
    exit 1
  fi
}

assert_fail() {
  local label fixture exit_code pattern
  label="$1"
  fixture="$2"
  exit_code="$3"
  pattern="$4"
  if [[ ${exit_code} -eq 0 ]]; then
    printf 'FAIL: %s expected non-zero exit, got 0\n' "${label}" >&2
    dump_stderr "${label}" "${fixture}"
    exit 1
  fi
  if [[ -n ${pattern} ]] && ! grep -qE "${pattern}" "${fixture}/stderr"; then
    printf 'FAIL: %s stderr did not match %s\n' "${label}" "${pattern}" >&2
    dump_stderr "${label}" "${fixture}"
    exit 1
  fi
}

test_pass_clean_state() {
  local fixture exit_code
  fixture="$(init_fixture pass-clean)"
  write_file "${fixture}/modules/meta/maintained-inputs.nix" "${INVENTORY_FULL}"
  write_file "${fixture}/flake.nix" "${FLAKE_NIX_CLEAN}"
  write_file "${fixture}/flake.lock" "${LOCK_BASE}"
  exit_code=$(run_sut "${fixture}" --no-fetch)
  assert_pass "pass-clean" "${fixture}" "${exit_code}"
}

test_pass_empty_inventory() {
  local fixture exit_code
  fixture="$(init_fixture pass-empty)"
  write_file "${fixture}/modules/meta/maintained-inputs.nix" "${INVENTORY_EMPTY}"
  write_file "${fixture}/flake.nix" "${FLAKE_NIX_CLEAN}"
  write_file "${fixture}/flake.lock" "${LOCK_BASE}"
  exit_code=$(run_sut "${fixture}" --no-fetch)
  assert_pass "pass-empty" "${fixture}" "${exit_code}"
}

test_fail_input_missing_from_flake_nix() {
  local fixture exit_code flake_without_example
  fixture="$(init_fixture fail-missing-flake-input)"
  flake_without_example='{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
  };
  outputs = _: { lib = (import ./modules/meta/maintained-inputs.nix {}).flake.lib; };
}'
  write_file "${fixture}/modules/meta/maintained-inputs.nix" "${INVENTORY_FULL}"
  write_file "${fixture}/flake.nix" "${flake_without_example}"
  write_file "${fixture}/flake.lock" "${LOCK_BASE}"
  exit_code=$(run_sut "${fixture}" --no-fetch)
  assert_fail "fail-missing-flake-input" "${fixture}" "${exit_code}" \
    'flake input example is not in flake\.nix inputs'
}

test_fail_local_url_in_flake_nix_with_empty_inventory() {
  local fixture exit_code flake_with_local
  fixture="$(init_fixture fail-local-url-empty)"
  flake_with_local='{
  inputs = {
    bad.url = "git+file:///tmp/example";
  };
}'
  write_file "${fixture}/modules/meta/maintained-inputs.nix" "${INVENTORY_EMPTY}"
  write_file "${fixture}/flake.nix" "${flake_with_local}"
  write_file "${fixture}/flake.lock" "${LOCK_BASE}"
  exit_code=$(run_sut "${fixture}" --no-fetch)
  assert_fail "fail-local-url-empty" "${fixture}" "${exit_code}" \
    'flake\.nix contains a local input URL'
}

test_pass_local_url_in_comment() {
  local fixture exit_code flake_with_comment
  fixture="$(init_fixture pass-local-url-comment)"
  flake_with_comment='{
  # historical: bad.url = "git+file:///tmp/example";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
  };
  outputs = _: { lib = (import ./modules/meta/maintained-inputs.nix {}).flake.lib; };
}'
  write_file "${fixture}/modules/meta/maintained-inputs.nix" "${INVENTORY_EMPTY}"
  write_file "${fixture}/flake.nix" "${flake_with_comment}"
  write_file "${fixture}/flake.lock" "${LOCK_BASE}"
  exit_code=$(run_sut "${fixture}" --no-fetch)
  assert_pass "pass-local-url-comment" "${fixture}" "${exit_code}"
}

test_fail_local_url_in_flake_lock() {
  local fixture exit_code local_lock
  fixture="$(init_fixture fail-local-url-lock)"
  local_lock='{
  "nodes": {
    "root": {
      "inputs": {
        "example": "example",
        "nixpkgs": "nixpkgs"
      }
    },
    "example": {
      "inputs": {
        "nixpkgs": ["nixpkgs"]
      },
      "locked": {
        "url": "git+file:///tmp/example",
        "type": "git"
      },
      "original": {
        "url": "git+file:///tmp/example",
        "type": "git"
      }
    },
    "nixpkgs": {
      "locked": {
        "rev": "0000000000000000000000000000000000000000",
        "type": "github",
        "owner": "NixOS",
        "repo": "nixpkgs"
      },
      "original": {
        "owner": "NixOS",
        "repo": "nixpkgs",
        "type": "github"
      }
    }
  },
  "root": "root",
  "version": 7
}'
  write_file "${fixture}/modules/meta/maintained-inputs.nix" "${INVENTORY_FULL}"
  write_file "${fixture}/flake.nix" "${FLAKE_NIX_CLEAN}"
  write_file "${fixture}/flake.lock" "${local_lock}"
  exit_code=$(run_sut "${fixture}" --no-fetch)
  assert_fail "fail-local-url-lock" "${fixture}" "${exit_code}" \
    'source for example is a local path'
}

test_fail_lock_graph_drift() {
  local fixture exit_code lock_extra
  fixture="$(init_fixture fail-lock-graph)"
  lock_extra='{
  "nodes": {
    "root": {
      "inputs": {
        "example": "example",
        "nixpkgs": "nixpkgs"
      }
    },
    "example": {
      "inputs": {
        "nixpkgs": ["nixpkgs"],
        "flake-parts": "flake-parts"
      },
      "locked": {
        "rev": "0000000000000000000000000000000000000000",
        "type": "github",
        "owner": "example",
        "repo": "example"
      },
      "original": {
        "owner": "example",
        "repo": "example",
        "type": "github"
      }
    },
    "flake-parts": {
      "locked": {
        "rev": "0000000000000000000000000000000000000000",
        "type": "github",
        "owner": "hercules-ci",
        "repo": "flake-parts"
      },
      "original": {
        "owner": "hercules-ci",
        "repo": "flake-parts",
        "type": "github"
      }
    },
    "nixpkgs": {
      "locked": {
        "rev": "0000000000000000000000000000000000000000",
        "type": "github",
        "owner": "NixOS",
        "repo": "nixpkgs"
      },
      "original": {
        "owner": "NixOS",
        "repo": "nixpkgs",
        "type": "github"
      }
    }
  },
  "root": "root",
  "version": 7
}'
  write_file "${fixture}/modules/meta/maintained-inputs.nix" "${INVENTORY_FULL}"
  write_file "${fixture}/flake.nix" "${FLAKE_NIX_CLEAN}"
  write_file "${fixture}/flake.lock" "${lock_extra}"
  exit_code=$(run_sut "${fixture}" --no-fetch)
  assert_fail "fail-lock-graph" "${fixture}" "${exit_code}" \
    'lock graph input names expected'
}

test_fail_lock_graph_missing_inputnames() {
  local fixture exit_code inventory_without_inputnames
  fixture="$(init_fixture fail-lock-graph-missing)"
  inventory_without_inputnames='_: {
  flake.lib.meta.maintainedInputs = {
    example = {
      flakeInput = "example";
      upstream = {
        url = "https://example.invalid/example.git";
        ref = "main";
      };
      sourceMode = "local-override";
      follows.nixpkgs = "nixpkgs";
      checks = [
        "no-local-url"
        "follows-preserved"
        "lock-graph"
      ];
    };
  };
}'
  write_file "${fixture}/modules/meta/maintained-inputs.nix" "${inventory_without_inputnames}"
  write_file "${fixture}/flake.nix" "${FLAKE_NIX_CLEAN}"
  write_file "${fixture}/flake.lock" "${LOCK_BASE}"
  exit_code=$(run_sut "${fixture}" --no-fetch)
  assert_fail "fail-lock-graph-missing" "${fixture}" "${exit_code}" \
    'lock-graph check declared but lockGraph\.inputNames is empty or missing'
}

test_fail_follows_drift() {
  local fixture exit_code lock_wrong_follows
  fixture="$(init_fixture fail-follows)"
  lock_wrong_follows='{
  "nodes": {
    "root": {
      "inputs": {
        "example": "example",
        "nixpkgs": "nixpkgs"
      }
    },
    "example": {
      "inputs": {
        "nixpkgs": "alt-nixpkgs"
      },
      "locked": {
        "rev": "0000000000000000000000000000000000000000",
        "type": "github",
        "owner": "example",
        "repo": "example"
      },
      "original": {
        "owner": "example",
        "repo": "example",
        "type": "github"
      }
    },
    "alt-nixpkgs": {
      "locked": {
        "rev": "0000000000000000000000000000000000000000",
        "type": "github",
        "owner": "NixOS",
        "repo": "nixpkgs"
      },
      "original": {
        "owner": "NixOS",
        "repo": "nixpkgs",
        "type": "github"
      }
    },
    "nixpkgs": {
      "locked": {
        "rev": "0000000000000000000000000000000000000000",
        "type": "github",
        "owner": "NixOS",
        "repo": "nixpkgs"
      },
      "original": {
        "owner": "NixOS",
        "repo": "nixpkgs",
        "type": "github"
      }
    }
  },
  "root": "root",
  "version": 7
}'
  write_file "${fixture}/modules/meta/maintained-inputs.nix" "${INVENTORY_FULL}"
  write_file "${fixture}/flake.nix" "${FLAKE_NIX_CLEAN}"
  write_file "${fixture}/flake.lock" "${lock_wrong_follows}"
  exit_code=$(run_sut "${fixture}" --no-fetch)
  assert_fail "fail-follows" "${fixture}" "${exit_code}" \
    'follows\.nixpkgs expected'
}

test_fail_follows_preserved_missing_follows() {
  local fixture exit_code inventory_without_follows
  fixture="$(init_fixture fail-follows-missing)"
  inventory_without_follows='_: {
  flake.lib.meta.maintainedInputs = {
    example = {
      flakeInput = "example";
      upstream = {
        url = "https://example.invalid/example.git";
        ref = "main";
      };
      sourceMode = "local-override";
      lockGraph.inputNames = [ "nixpkgs" ];
      checks = [
        "no-local-url"
        "follows-preserved"
        "lock-graph"
      ];
    };
  };
}'
  write_file "${fixture}/modules/meta/maintained-inputs.nix" "${inventory_without_follows}"
  write_file "${fixture}/flake.nix" "${FLAKE_NIX_CLEAN}"
  write_file "${fixture}/flake.lock" "${LOCK_BASE}"
  exit_code=$(run_sut "${fixture}" --no-fetch)
  assert_fail "fail-follows-missing" "${fixture}" "${exit_code}" \
    'follows-preserved check declared but follows is empty or missing'
}

test_fail_clean_and_tracked_both_fire() {
  local fixture checkout exit_code inventory_with_path
  fixture="$(init_fixture fail-clean-tracked)"
  checkout="${fixture}/external"
  git init -q "${checkout}"
  git -C "${checkout}" config user.email "tests@example.invalid"
  git -C "${checkout}" config user.name "check-maintained-inputs tests"
  printf 'init' >"${checkout}/README"
  git -C "${checkout}" add README
  git -C "${checkout}" commit -q -m init
  printf 'changed' >"${checkout}/README"
  printf 'new' >"${checkout}/UNTRACKED"
  inventory_with_path='_: {
  flake.lib.meta.maintainedInputs = {
    example = {
      flakeInput = "example";
      upstream = {
        url = "https://example.invalid/example.git";
        ref = "main";
      };
      sourceMode = "local-override";
      local.pathEnv = "EXAMPLE_CHECKOUT";
      follows.nixpkgs = "nixpkgs";
      lockGraph.inputNames = [ "nixpkgs" ];
      checks = [
        "clean-checkout"
        "tracked-files"
        "no-local-url"
        "follows-preserved"
        "lock-graph"
      ];
    };
  };
}'
  write_file "${fixture}/modules/meta/maintained-inputs.nix" "${inventory_with_path}"
  write_file "${fixture}/flake.nix" "${FLAKE_NIX_CLEAN}"
  write_file "${fixture}/flake.lock" "${LOCK_BASE}"
  export EXAMPLE_CHECKOUT="${checkout}"
  exit_code=$(run_sut "${fixture}" --no-fetch)
  unset EXAMPLE_CHECKOUT
  assert_fail "fail-clean-tracked" "${fixture}" "${exit_code}" \
    'dirty or has untracked files'
  if ! grep -qE 'has untracked files' "${fixture}/stderr"; then
    printf 'FAIL: fail-clean-tracked stderr did not include the separate tracked-files message\n' >&2
    dump_stderr "fail-clean-tracked" "${fixture}"
    exit 1
  fi
}

test_fail_checkout_check_missing_pathenv() {
  local fixture exit_code inventory_without_pathenv
  fixture="$(init_fixture fail-checkout-missing-pathenv)"
  inventory_without_pathenv='_: {
  flake.lib.meta.maintainedInputs = {
    example = {
      flakeInput = "example";
      upstream = {
        url = "https://example.invalid/example.git";
        ref = "main";
      };
      sourceMode = "local-override";
      follows.nixpkgs = "nixpkgs";
      lockGraph.inputNames = [ "nixpkgs" ];
      checks = [
        "clean-checkout"
        "no-local-url"
        "follows-preserved"
        "lock-graph"
      ];
    };
  };
}'
  write_file "${fixture}/modules/meta/maintained-inputs.nix" "${inventory_without_pathenv}"
  write_file "${fixture}/flake.nix" "${FLAKE_NIX_CLEAN}"
  write_file "${fixture}/flake.lock" "${LOCK_BASE}"
  exit_code=$(run_sut "${fixture}" --no-fetch)
  assert_fail "fail-checkout-missing-pathenv" "${fixture}" "${exit_code}" \
    'checkout check declared but local\.pathEnv is empty or missing'
}

test_fail_unknown_check_name() {
  local fixture exit_code bad_inventory
  fixture="$(init_fixture fail-unknown-check)"
  bad_inventory='_: {
  flake.lib.meta.maintainedInputs = {
    example = {
      flakeInput = "example";
      upstream = {
        url = "https://example.invalid/example.git";
        ref = "main";
      };
      sourceMode = "local-override";
      follows.nixpkgs = "nixpkgs";
      lockGraph.inputNames = [ "nixpkgs" ];
      checks = [ "bogus" ];
    };
  };
}'
  write_file "${fixture}/modules/meta/maintained-inputs.nix" "${bad_inventory}"
  write_file "${fixture}/flake.nix" "${FLAKE_NIX_CLEAN}"
  write_file "${fixture}/flake.lock" "${LOCK_BASE}"
  exit_code=$(run_sut "${fixture}" --no-fetch)
  assert_fail "fail-unknown-check" "${fixture}" "${exit_code}" \
    'unknown check: bogus'
}

test_pass_clean_state
test_pass_empty_inventory
test_fail_input_missing_from_flake_nix
test_fail_local_url_in_flake_nix_with_empty_inventory
test_pass_local_url_in_comment
test_fail_local_url_in_flake_lock
test_fail_lock_graph_drift
test_fail_lock_graph_missing_inputnames
test_fail_follows_drift
test_fail_follows_preserved_missing_follows
test_fail_clean_and_tracked_both_fire
test_fail_checkout_check_missing_pathenv
test_fail_unknown_check_name

printf '13 passed\n'
