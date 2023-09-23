{ lib, stdenv, fetchFromGitHub, fetchpatch, callPackage, autoreconfHook, pkg-config, makeWrapper
, CoreFoundation, IOKit, libossp_uuid
, nixosTests
, netdata-go-plugins
, bash, curl, jemalloc, libuv, zlib, libyaml
, libcap, libuuid, lm_sensors, protobuf, python3
, withCups ? false, cups
, withDBengine ? true, lz4
, withIpmi ? (!stdenv.isDarwin), freeipmi
, withNetfilter ? (!stdenv.isDarwin), libmnl, libnetfilter_acct
, withCloud ? (!stdenv.isDarwin), json_c
, withConnPubSub ? false, google-cloud-cpp, grpc
, withConnPrometheus ? false, snappy
, withSsl ? true, openssl
, withDebug ? false
}:

let
  dashboardV1 = callPackage ./dashboard/default.nix {};
in stdenv.mkDerivation rec {
  # Don't forget to update go.d.plugin.nix as well
  version = "1.42.2";
  pname = "netdata";

  src = fetchFromGitHub {
    owner = "netdata";
    repo = "netdata";
    rev = "v${version}";
    hash = "sha256-Fwt8TpWQ5pIuSZ4YJTDNppbvmSIXP+PM9b7L4F620fs=";
    fetchSubmodules = true;

    # The v1 dashboard will be replaced with the self-built dashboard.
    postFetch = ''
      rm -rvf $out/web/gui/v1
    '';
  };

  strictDeps = true;

  nativeBuildInputs = [ python3 autoreconfHook pkg-config makeWrapper protobuf ];
  # bash is only used to rewrite shebangs
  buildInputs = [ bash curl jemalloc libuv zlib libyaml ]
    ++ lib.optionals stdenv.isDarwin [ CoreFoundation IOKit libossp_uuid ]
    ++ lib.optionals (!stdenv.isDarwin) [ libcap libuuid ]
    ++ lib.optionals withCups [ cups ]
    ++ lib.optionals withDBengine [ lz4 ]
    ++ lib.optionals withIpmi [ freeipmi ]
    ++ lib.optionals withNetfilter [ libmnl libnetfilter_acct ]
    ++ lib.optionals withCloud [ json_c ]
    ++ lib.optionals withConnPubSub [ google-cloud-cpp grpc ]
    ++ lib.optionals withConnPrometheus [ snappy ]
    ++ lib.optionals (withCloud || withConnPrometheus) [ protobuf ]
    ++ lib.optionals withSsl [ openssl ];

  patches = [
    # required to prevent plugins from relying on /etc
    # and /var
    ./no-files-in-etc-and-var.patch

    # Avoid build-only inputs in closure leaked by configure command:
    #   https://github.com/NixOS/nixpkgs/issues/175693#issuecomment-1143344162
    ./skip-CONFIGURE_COMMAND.patch

    # Allow re-writing the build files for self-built dashboard.
    (fetchpatch {
      url = "https://github.com/peat-psuwit/netdata/commit/71f69dc2f844e1f4ea3751400612b8438d9c635f.patch";
      hash = "sha256-dpA9zODGIR7mXxokFORmPOGytcEkgDJAU3iFDg4Bio8=";
    })
  ];

  # Guard against unused buld-time development inputs in closure. Without
  # the ./skip-CONFIGURE_COMMAND.patch patch the closure retains inputs up
  # to bootstrap tools:
  #   https://github.com/NixOS/nixpkgs/pull/175719
  # We pick zlib.dev as a simple canary package with pkg-config input.
  disallowedReferences = lib.optional (!withDebug) zlib.dev;

  donStrip = withDebug;
  env.NIX_CFLAGS_COMPILE = lib.optionalString withDebug "-O1 -ggdb -DNETDATA_INTERNAL_CHECKS=1";

  postInstall = ''
    ln -s ${netdata-go-plugins}/lib/netdata/conf.d/* $out/lib/netdata/conf.d
    ln -s ${netdata-go-plugins}/bin/godplugin $out/libexec/netdata/plugins.d/go.d.plugin
  '' + lib.optionalString (!stdenv.isDarwin) ''
    # rename this plugin so netdata will look for setuid wrapper
    mv $out/libexec/netdata/plugins.d/apps.plugin \
       $out/libexec/netdata/plugins.d/apps.plugin.org
    mv $out/libexec/netdata/plugins.d/cgroup-network \
       $out/libexec/netdata/plugins.d/cgroup-network.org
    mv $out/libexec/netdata/plugins.d/perf.plugin \
       $out/libexec/netdata/plugins.d/perf.plugin.org
    mv $out/libexec/netdata/plugins.d/slabinfo.plugin \
       $out/libexec/netdata/plugins.d/slabinfo.plugin.org
    ${lib.optionalString withIpmi ''
      mv $out/libexec/netdata/plugins.d/freeipmi.plugin \
         $out/libexec/netdata/plugins.d/freeipmi.plugin.org
    ''}
  '';

  postPatch = ''
    # Copy the self-built dashboard into the tree, then re-write the Makefile.am using the (patched)
    # dashboard bundling script.
    cd web/gui
    cp -rv ${dashboardV1} v1
    chmod -R u+w v1/
    ln -s ../.dashboard-notice.md v1/README.md

    python3 <<EOF
    import bundle_dashboard_v1
    bundle_dashboard_v1.write_makefile()
    EOF

    cd ../..
  '';
  
  preConfigure = lib.optionalString (!stdenv.isDarwin) ''
    substituteInPlace collectors/python.d.plugin/python_modules/third_party/lm_sensors.py \
      --replace 'ctypes.util.find_library("sensors")' '"${lm_sensors.out}/lib/libsensors${stdenv.hostPlatform.extensions.sharedLibrary}"'
  '';

  configureFlags = [
    "--localstatedir=/var"
    "--sysconfdir=/etc"
    "--disable-ebpf"
    "--with-jemalloc=${jemalloc}"
  ] ++ lib.optionals (!withDBengine) [
    "--disable-dbengine"
  ] ++ lib.optionals (!withCloud) [
    "--disable-cloud"
  ];

  postFixup = ''
    wrapProgram $out/bin/netdata-claim.sh --prefix PATH : ${lib.makeBinPath [ openssl ]}
    wrapProgram $out/libexec/netdata/plugins.d/cgroup-network-helper.sh --prefix PATH : ${lib.makeBinPath [ bash ]}
    wrapProgram $out/bin/netdatacli --set NETDATA_PIPENAME /run/netdata/ipc
  '';

  enableParallelBuild = true;

  passthru = {
    inherit withIpmi;
    tests.netdata = nixosTests.netdata;
  };

  meta = with lib; {
    broken = stdenv.isDarwin || stdenv.buildPlatform != stdenv.hostPlatform;
    description = "Real-time performance monitoring tool";
    homepage = "https://www.netdata.cloud/";
    changelog = "https://github.com/netdata/netdata/releases/tag/v${version}";
    license = licenses.gpl3Plus;
    platforms = platforms.unix;
    maintainers = with maintainers; [ raitobezarius ];
  };
}
