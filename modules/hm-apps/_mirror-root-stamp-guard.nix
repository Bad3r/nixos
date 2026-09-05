# Guard shared by git-mirror.nix and its docs-builder helpers: local-mirrors-root.service
# writes the stamp only while the backing volume is mounted, so testing for it (not the
# root directory or its mode) is what proves the volume is present.
{
  rootRef,
  stampRef,
  logPrefix ? "",
}:
''
  if [ ! -e "${rootRef}/${stampRef}" ]; then
    log "${logPrefix}mirror root ${rootRef} was not provisioned by local-mirrors-root.service, is the volume mounted?"
    exit 1
  fi''
