#!/usr/bin/env nix-shell
#! nix-shell -i bash -p nodePackages.node2nix -p wget

tag="v3.0.1"
u="https://github.com/netdata/dashboard/raw/$tag"
wget $u/package.json $u/package-lock.json

node2nix \
  --nodejs-14 \
  --node-env ../../../../development/node-packages/node-env.nix \
  --input package.json \
  --lock package-lock.json \
  --development \
  --output node-packages.nix \
  --composition node-composition.nix \
  --registry https://registry.npmjs.org

sed -i 's|<nixpkgs>|../../../../..|' node-composition.nix

rm package.json package-lock.json
