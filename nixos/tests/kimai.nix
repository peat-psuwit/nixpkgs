import ./make-test-python.nix ({ lib, ...}:

{
  name = "kimai";
  meta.maintainers = lib.teams.php.members;

  nodes.machine = { ... }:
  {
    services.kimai.sites."locahost" = {
      database.createLocally = true;
    };
  };

  testScript = ''
    machine.wait_for_unit("phpfpm-kimai-localhost.service")
    machine.wait_for_unit("nginx.service")
    machine.wait_for_open_port(80)
    machine.succeed("curl -V --fail http://localhost/")
  '';
})
