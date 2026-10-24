{
  lib,
  clangStdenv,
  clang,
  makeWrapper,
  coreutils,
  apple-sdk_15,
  darwinMinVersionHook,
  bend,
  bendLib,
  bendLicense,
}:

clangStdenv.mkDerivation {
  pname = "mylsm";
  version = "0.6.0.0-alpha";
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../app
      ../src
      ../LICENSE
    ];
  };
  nativeBuildInputs = [
    bend
    makeWrapper
  ];
  buildInputs = lib.optionals clangStdenv.hostPlatform.isDarwin [
    apple-sdk_15
    (darwinMinVersionHook "15.0")
  ];
  BEND_LIB = bendLib;
  CC = "${clang}/bin/clang";

  buildPhase = ''
    runHook preBuild
    bend app/cli/installed.bend -o mylsm
    bend app/demo/mylsm_demo.bend -o mylsm-demo
    bend app/repl/repl.bend -o mylsm-repl
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 mylsm $out/bin/mylsm
    install -Dm755 mylsm-demo $out/libexec/mylsm/mylsm-demo
    install -Dm755 mylsm-repl $out/libexec/mylsm/mylsm-repl
    install -Dm644 LICENSE $out/share/licenses/mylsm/LICENSE
    install -Dm644 ${bendLicense} $out/share/licenses/mylsm/bend.LICENSE
    for license in $BEND_LIB/*/LICENSE; do
      install -Dm644 "$license" "$out/share/licenses/mylsm/$(basename "$(dirname "$license")").LICENSE"
    done
    wrapProgram $out/bin/mylsm \
      --set MYLSM_PACKAGE_ROOT $out/libexec/mylsm \
      --prefix PATH : ${lib.makeBinPath [ coreutils ]}
    runHook postInstall
  '';

  meta = {
    description = "LSM key-value database with durable writes and an interactive CLI";
    homepage = "https://github.com/FabianVegaA/mylsm";
    license = with lib.licenses; [
      bsd3
      asl20
    ];
    mainProgram = "mylsm";
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
