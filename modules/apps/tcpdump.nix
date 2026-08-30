/*
  Package: tcpdump
  Description: Network sniffer.
  Homepage: https://www.tcpdump.org/
  Documentation: https://www.tcpdump.org/
  Repository: https://github.com/the-tcpdump-group/tcpdump

  Summary:
    * Captures and decodes packets from live interfaces or saved capture files.
    * Supports Berkeley Packet Filter expressions, capture rotation, and raw pcap output.

  Options:
    -i interface: Capture packets on a specific network interface.
    -c count: Stop after processing a fixed number of packets.
    -r file: Read packets from an existing capture file instead of a live interface.
    -w file: Write raw packets to a capture file for later analysis.
    -s snaplen: Limit how many bytes of each packet are captured.

  Notes:
    * Installs a capability wrapper so `wheel` users can capture without invoking `sudo`.
    * The wrapper source is an argv filter that refuses `-z`: tcpdump.c:3173 `execlp`s the postrotate command and the wrapper's ambient capability set lands in it. Rotate first, then compress as a separate step.
*/
_:
let
  TcpdumpModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.tcpdump.extended;

      # security.wrappers raises cap_net_raw and cap_net_admin into the ambient
      # set (wrapper.c:137), which survives execve into a file without
      # capabilities, so the -z child at tcpdump.c:3173 would inherit both. The
      # filter has to be a compiled binary: cap wrappers are not setuid, so
      # euid == uid, bash never enters privileged mode, and BASH_ENV is absent
      # from glibc's unsecvars.h.
      argvFilter = pkgs.writeCBin "tcpdump-argv-filter" ''
        #include <stdio.h>
        #include <string.h>
        #include <unistd.h>

        static char real_prog[] = "${cfg.package}/bin/tcpdump";

        /* SHORTOPTS (tcpdump.c:696) expanded, restricted to the ":"-suffixed
           entries. `b` is a counter (tcpdump.c:1766); listing it would make
           `-b -z cmd` consume the -z as an argument and let it through. */
        static const char optarg_chars[] = "BcCEFGijmMQrsTVwWyzZ";

        int main(int argc, char **argv)
        {
        	int i;

        	for (i = 1; i < argc; i++) {
        		const char *arg = argv[i];
        		const char *c;

        		/* nixpkgs builds against glibc getopt_long, which permutes, so
        		   an operand does not end option parsing. A lone "-" is an
        		   operand. */
        		if (arg[0] != '-' || arg[1] == '\0')
        			continue;
        		if (arg[1] == '-') {
        			if (arg[2] == '\0')
        				break;
        			/* longopts[] (tcpdump.c:729) has no alias for -z. A long
        			   option never consumes the next element here, because
        			   guessing wrong would hide `--help -z cmd`. */
        			continue;
        		}

        		for (c = arg + 1; *c != '\0'; c++) {
        			if (*c == 'z') {
        				fputs("tcpdump: -z is refused by the capability wrapper\n", stderr);
        				return 1;
        			}
        			if (strchr(optarg_chars, *c) != NULL) {
        				if (c[1] == '\0')
        					i++;
        				break;
        			}
        		}
        	}

        	/* execve(2) permits argc == 0, where argv[0] is the NULL terminator. */
        	if (argc > 0)
        		argv[0] = real_prog;
        	execv(real_prog, argv);
        	perror(real_prog);
        	return 127;
        }
      '';
    in
    {
      options.programs.tcpdump.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable tcpdump.";
        };

        package = lib.mkPackageOption pkgs "tcpdump" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

        security.wrappers.tcpdump = {
          source = "${argvFilter}/bin/tcpdump-argv-filter";
          capabilities = "cap_net_raw,cap_net_admin+ep";
          owner = "root";
          group = "wheel";
          permissions = "u+rx,g+x";
        };
      };
    };
in
{
  flake.nixosModules.apps.tcpdump = TcpdumpModule;
}
