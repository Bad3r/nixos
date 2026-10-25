# Copyright (c) 2026 Bad3r
"""Exercise the installed completion scripts in Bash, Zsh, and Fish."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


@unittest.skipUnless(os.environ.get("SBX_TEST_PACKAGE"), "needs the installed sbx package")
class ShellTest(unittest.TestCase):
    """Shell registration invokes the packaged CLI and returns command candidates."""

    def setUp(self) -> None:
        """Keep shell state and caches in a disposable home."""
        home = tempfile.TemporaryDirectory()
        self.addCleanup(home.cleanup)
        self.package = Path(os.environ["SBX_TEST_PACKAGE"])
        self.environment = {
            **os.environ,
            "HOME": home.name,
            "XDG_DATA_HOME": home.name + "/data",
            "XDG_CONFIG_HOME": home.name + "/config",
            "PATH": str(self.package / "bin") + os.pathsep + os.environ["PATH"],
        }

    def test_bash(self) -> None:
        """Bash's registered function completes through the installed executable."""
        script = r"""
            source "$1"
            COMP_LINE='sbx cr'
            COMP_POINT=6
            COMP_TYPE=9
            COMP_WORDS=(sbx cr)
            COMP_CWORD=1
            _python_argcomplete sbx
            [[ ${#COMPREPLY[@]} == 1 && ${COMPREPLY[0]% } == create ]]
        """
        subprocess.run(
            [
                "bash",
                "--noprofile",
                "--norc",
                "-c",
                script,
                "bash",
                str(self.package / "share/bash-completion/completions/sbx.bash"),
            ],
            env=self.environment,
            check=True,
            capture_output=True,
            text=True,
            timeout=15,
        )

    def test_zsh(self) -> None:
        """Zsh discovers _sbx through fpath and receives described command candidates."""
        script = r"""
            fpath=("$1/share/zsh/site-functions" $fpath)
            autoload -Uz compinit
            compinit -D
            [[ ${_comps[sbx]} == _sbx ]] || exit 1
            _describe() { print -rl -- "${completions[@]}" }
            BUFFER='sbx cr'
            CURSOR=6
            words=(sbx cr)
            _sbx
        """
        result = subprocess.run(
            ["zsh", "-f", "-c", script, "zsh", str(self.package)],
            env=self.environment,
            check=True,
            capture_output=True,
            text=True,
            timeout=15,
        )
        self.assertEqual(result.stdout.strip().split(":", 1)[0], "create")

    def test_fish(self) -> None:
        """Fish completes through the script installed in its vendor directory."""
        result = subprocess.run(
            [
                "fish",
                "--no-config",
                "-c",
                'source $argv[1]; complete -C "sbx cr"',
                str(self.package / "share/fish/vendor_completions.d/sbx.fish"),
            ],
            env=self.environment,
            check=True,
            capture_output=True,
            text=True,
            timeout=15,
        )
        self.assertEqual(
            [line.split("\t", 1)[0] for line in result.stdout.splitlines()], ["create"]
        )
