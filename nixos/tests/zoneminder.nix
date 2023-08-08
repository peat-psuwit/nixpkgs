import ./make-test-python.nix ({ lib, ...}:

{
  name = "zoneminder";
  meta.maintainers = with lib.maintainers; [ danielfullmer ];

  nodes.machine = { pkgs, ... }:
  {
    services.zoneminder = {
      enable = true;
      database.createLocally = true;
      database.username = "zoneminder";
    };
    time.timeZone = "America/New_York";

    # Allow testing command line utilities.
    environment.systemPackages = with pkgs; [ zoneminder ];
  };

  testScript = ''
    machine.wait_for_unit("zoneminder.service")
    machine.wait_for_unit("nginx.service")
    machine.wait_for_open_port(8095)
    machine.succeed("curl --fail http://localhost:8095/")

    # Test that these Perl scripts can be executed. Some commands are run under
    # 'zoneminder' user as it'll attempt to connect to DB.
    machine.succeed("""
      zmonvif-probe.pl --help
      su --shell /run/current-system/sw/bin/sh zoneminder -c 'zmonvif-trigger.pl'
    """)
  '';
})
