{ lib }:
{
  tag,
  hostPath,
  readOnly,
  binary,
}:
''
  <filesystem type="mount" accessmode="passthrough">
    <driver type="virtiofs"/>
    <binary path="${binary}"/>
    <source dir="${hostPath}"/>
    <target dir="${tag}"/>
    ${lib.optionalString readOnly "<readonly/>"}
  </filesystem>
''
