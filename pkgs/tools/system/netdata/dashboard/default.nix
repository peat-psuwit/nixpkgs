{ pkgs, lib, stdenv, fetchFromGitHub, nodejs_14,
  pkg-config, libjpeg, pixman, cairo, pango }:

let
  version = "3.0.1";
  src = fetchFromGitHub {
    owner = "netdata";
    repo = "dashboard";
    rev = "v${version}";
    hash = "sha256-e30bPf28os3ysh7Ht6x61akwidJApY3dPgSmDYxHfM4=";
  };

  # netdata/dashboard's build system is _ancient_. Most depedencies are out-of-
  # date, and one of its transitive dependency with native module fails to build
  # on NodeJS 18. The upstream GitHub Action config builds this using NodeJS 12.
  # However, since NodeJS 12 is now removed from NixOS, use NodeJS 14.
  #
  # Should be fine though, since the built result doesn't run on NodeJS (it
  # builds a web application).
  nodejs = nodejs_14;
  nodeDependencies = (import ./node-composition.nix {
    inherit pkgs nodejs;
    inherit (stdenv.hostPlatform) system;
  }).nodeDependencies.override {
    inherit src version;

    nativeBuildInputs = [ nodejs.pkgs.node-pre-gyp nodejs.pkgs.node-gyp-build pkg-config ];
    buildInputs = [ libjpeg pixman cairo pango ];
  };
in stdenv.mkDerivation rec {
  inherit version src;
  pname = "netdata-dashboard";

  strictDeps = true;

  nativeBuildInputs = [ nodejs ];

  outputs = [ "out" "debug" ];
  # The output files are intended to be distributed to web browser, and thus
  # cannot have any references to the Nix store. The sourcemap files, however,
  # can. This necessitates different checks per output.
  __structuredAttrs = true;
  outputChecks.out = {
    allowedReferences = [];
  };

  buildPhase = ''
    ln -s ${nodeDependencies}/lib/node_modules ./node_modules
    export PATH="${nodeDependencies}/bin:$PATH"

    # Give NPM a place to write log file and stuffs.
    export HOME="$(mktemp -d)"

    npm run ts-bundle
    npm run build
    cp -r build $out
    # Put the sourcemap files in the debug output, as it contains the
    # references to nodeDependencies derivation.
    mkdir -p $debug/static/js/
    mv $out/static/js/*.map $debug/static/js/
  '';
}
