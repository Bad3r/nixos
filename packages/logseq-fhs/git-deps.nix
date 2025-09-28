{ fetchFromGitHub }:
let
  fetchGitHub =
    {
      owner,
      repo,
      rev,
      hash,
    }:
    fetchFromGitHub {
      inherit
        owner
        repo
        rev
        hash
        ;
    };
in
{
  bb_tasks_src = fetchGitHub {
    owner = "logseq";
    repo = "bb-tasks";
    rev = "70d3edeb287f5cec7192e642549a401f7d6d4263";
    hash = "sha256-xVJj5XCkqfaNjnhYZkuqTSJN0ry8UVMaN44r9pxggB0=";
  };

  bb_tasks_db_src = fetchGitHub {
    owner = "logseq";
    repo = "bb-tasks";
    rev = "1d429e223baeade426d30a4ed1c8a110173a2402";
    hash = "sha256-CWiRhEWXJ1J+a75IeUbYkcbtpukD9X9/h3ctPVYqroE=";
  };

  rum_src = fetchGitHub {
    owner = "logseq";
    repo = "rum";
    rev = "5d672bf84ed944414b9f61eeb83808ead7be9127";
    hash = "sha256-CG17ijjtcPhRx2T0HC0CtMfWQWrESacVxtj80ns1vJU=";
  };

  datascript_src = fetchGitHub {
    owner = "logseq";
    repo = "datascript";
    rev = "45f6721bf2038c24eb9fe3afb422322ab3f473b5";
    hash = "sha256-v4BYOJaqb9v6iwWG2NvO1I1XuPC7MNQOBET27xHPLYU=";
  };

  cljs_time_src = fetchGitHub {
    owner = "logseq";
    repo = "cljs-time";
    rev = "5704fbf48d3478eedcf24d458c8964b3c2fd59a9";
    hash = "sha256-IApL+SEm7AhbTN7J/1KiAKTx7rd53hchRh3jmPQ412g=";
  };

  cljc_fsrs_src = fetchGitHub {
    owner = "open-spaced-repetition";
    repo = "cljc-fsrs";
    rev = "eeef3520df664e51c3d0ba2031ec2ba071635442";
    hash = "sha256-C/SvcUTC9BS61T3XWJjolZFrYHwhu5vdrGtAsz1qePA=";
  };

  cljs_http_missionary_src = fetchGitHub {
    owner = "RCmerci";
    repo = "cljs-http-missionary";
    rev = "d61ce7e29186de021a2a453a8cee68efb5a88440";
    hash = "sha256-3L6R8LQxhqsm5gjGqMxUtROGg/QV1ikRFEgKYcrcKGM=";
  };

  clj_fractional_indexing_src = fetchGitHub {
    owner = "logseq";
    repo = "clj-fractional-indexing";
    rev = "1087f0fb18aa8e25ee3bbbb0db983b7a29bce270";
    hash = "sha256-H1pdNX+YbIpwd49L7/ku6YeXp0Jv6BmHZRQdRqopQwc=";
  };

  wally_src = fetchGitHub {
    owner = "logseq";
    repo = "wally";
    rev = "8571fae7c51400ac61c8b1026cbfba68279bc461";
    hash = "sha256-Rh8FUwWMtGwqAHYY72BE9HqE5olxEKG0bybUG+ngqJw=";
  };

  nbb_test_runner_src = fetchGitHub {
    owner = "nextjournal";
    repo = "nbb-test-runner";
    rev = "b379325cfa5a3306180649da5de3bf5166414e71";
    hash = "sha256-dXcTkBCWvrypTy2itnAoq92ijkMjS+vhSKbb4h9crno=";
  };

  cognitect_test_runner_src = fetchGitHub {
    owner = "cognitect-labs";
    repo = "test-runner";
    rev = "dfb30dd6605cb6c0efc275e1df1736f6e90d4d73";
    hash = "sha256-PUNd+dHJNPTKno59YI27wpehyULYPvSyCQDjVIadKJ4=";
  };

  electron_node_gyp_src = fetchGitHub {
    owner = "electron";
    repo = "node-gyp";
    rev = "06b29aafb7708acef8b3669835c8a7857ebc92d2";
    hash = "sha256-AzsnndqdhXYXRDj6+4BPKycXNDOl/gNZIyMw/+WjsVU=";
  };

  electron_forge_maker_appimage_src = fetchGitHub {
    owner = "logseq";
    repo = "electron-forge-maker-appimage";
    rev = "4bf4d4eb5925f72945841bd2fa7148322bc44189";
    hash = "sha256-/J+gT210ozmC5CG0wgu7cwNC5JskMvUdBc8qr1IE+qI=";
  };

}
