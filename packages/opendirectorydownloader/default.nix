{
  lib,
  stdenvNoCC,
  fetchzip,
  makeWrapper,
}:

let
  version = "3.5.0.6";

  downloads = {
    x86_64-linux = {
      url = "https://github.com/KoalaBear84/OpenDirectoryDownloader/releases/download/v${version}/OpenDirectoryDownloader-${version}-linux-x64-self-contained.zip";
      sha256 = "sha256-dKPes3Dex+k4Rzzw9iHj8rs0YyxZj2kgbvWkBkjVhvE=";
    };

    aarch64-linux = {
      url = "https://github.com/KoalaBear84/OpenDirectoryDownloader/releases/download/v${version}/OpenDirectoryDownloader-${version}-linux-arm64-self-contained.zip";
      sha256 = "sha256-64eibmsHe9DIX1zir/q+NFfQnDnSr3c3JIhltX8q7bw=";
    };
  };

  platform =
    downloads.${stdenvNoCC.hostPlatform.system}
      or (throw "opendirectorydownloader: unsupported system ${stdenvNoCC.hostPlatform.system}");

in
stdenvNoCC.mkDerivation {
  pname = "opendirectorydownloader";
  inherit version;

  src = fetchzip {
    inherit (platform) url sha256;
    stripRoot = false;
  };

  nativeBuildInputs = [ makeWrapper ];

  # Don't use autoPatchelfHook - it corrupts the .NET bundle
  # .NET self-contained binaries include an embedded runtime bundle
  # that gets corrupted when the ELF binary is modified
  dontPatchELF = true;
  dontStrip = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # Install all files from the self-contained .NET application
    mkdir -p $out/lib/opendirectorydownloader
    cp -r $src/* $out/lib/opendirectorydownloader/
    chmod +x $out/lib/opendirectorydownloader/OpenDirectoryDownloader

    # Create wrapper script in bin
    mkdir -p $out/bin
    makeWrapper $out/lib/opendirectorydownloader/OpenDirectoryDownloader \
      $out/bin/opendirectorydownloader

    runHook postInstall
  '';

  meta = {
    description = "Indexes open directories listings in 130+ supported formats";
    longDescription = ''
      OpenDirectoryDownloader indexes open directories listings in 130+ supported formats
      including FTP(S), Google Drive, Bhadoo, GoIndex, Dropbox, Mediafire, GoFile, GitHub,
      and many more. It's a .NET-based tool that provides full directory indexing
      and downloading capabilities.
    '';
    homepage = "https://github.com/KoalaBear84/OpenDirectoryDownloader";
    license = lib.licenses.gpl3Only;
    mainProgram = "opendirectorydownloader";
    platforms = builtins.attrNames downloads;
    maintainers = [ ];
  };
}
