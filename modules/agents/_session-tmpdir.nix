# Shell lines for the agent bash wrappers: TMPDIR becomes the root session's
# throwaway dir, which subagents share because they carry the root session ID.
# Commands never fail over it; TMPDIR stays the scratch root when it cannot be set.
{ lib, scratchDir }:
idVar: ''
  sessionId=''${${idVar}:-}
  case "$sessionId" in
    "" | *[!A-Za-z0-9-]*) ;;
    *)
      sessionTmp=${lib.escapeShellArg "${scratchDir}/sessions"}/"$sessionId"
      if mkdir -p -- "$sessionTmp" 2>/dev/null; then
        export TMPDIR="$sessionTmp"
      fi
      ;;
  esac
  unset sessionId sessionTmp
''
