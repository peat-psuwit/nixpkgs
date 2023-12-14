{ php, fetchFromGitHub, lib }:

php.buildComposerProject (finalAttrs: {
  pname = "kimai";
  version = "2.5.0";

  src = fetchFromGitHub {
    owner = "kimai";
    repo = "kimai";
    rev = finalAttrs.version;
    hash = "sha256-gSlURe2SpubfdD9XJA+ib3wnpTFit7HWGePuNdoh0rM=";
  };

  php = php.buildEnv {
    extensions = ({ enabled, all }: enabled ++ (with all; [
      xsl
      zip
    ]));

    # Asset building process requires a little bit more memory.
    extraConfig = ''
      memory_limit=256M
    '';
  };

  vendorHash = "sha256-AvC++rm5oIW3cUeZbFz06b/HG4VIc4pWHlOhtKri2eU=";

  composerNoPlugins = false;
  composerNoScripts = false;

  postInstall = ''
    # Large number of places assume that var/ directory _inside_ program
    # directory is writable, without a config. Rather than go out and patch all
    # of them, replace the directory with a symlink which points to a directory
    # outside of it. In a similar vein, the location of config/packages/
    # local.yaml is hardcoded.
    rm -rf $out/share/php/kimai/var
    ln -s /var/lib/kimai $out/share/php/kimai/var
    ln -s /etc/kimai/local.yaml $out/share/php/kimai/config/packages/local.yaml

    # Make available the console utility, as Kimai doesn't list this in
    # composer.json.
    mkdir -p "$out"/share/php/kimai "$out"/bin
    makeWrapper "$out"/share/php/kimai/bin/console "$out"/bin/console
  '';

  meta = {
    description = "A web-based multi-user time-tracking application";
    homepage = "https://www.kimai.org/";
    license = lib.licenses.agpl3Plus;
    longDescription = "
      Kimai is a web-based multi-user time-tracking application. Works great for
      everyone: freelancers, companies, organizations - everyone can track their
      times, generate reports, create invoices and do so much more.
    ";
    maintainers = lib.teams.php.members;
    platforms = lib.platforms.all;
  };
})
