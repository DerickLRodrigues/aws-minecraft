#!/bin/bash
set -euo pipefail
umask 027
cd /srv/minecraft
exec 9>.install.lock
flock -x 9
if [[ -d server ]]; then
  [[ -f server/.installed-v4.1.7 ]] || { echo "Diretório existente sem marcador; revise via SSM." >&2; exit 1; }
  exit 0
fi
stage=$(mktemp -d .stage.XXXXXXXX)
trap 'rm -rf -- "$stage"' EXIT
fetch() {
  curl --fail --silent --show-error --proto '=https' --tlsv1.2 --retry 4 --connect-timeout 20 --max-time 1800 -o "$2" "$1"
  echo "$3  $2" | sha256sum --check --strict
}
fetch 'https://mediafilez.forgecdn.net/files/9455/984/Server-Pack-for-v4.1.7.zip' "$stage/pack.zip" b818b01520327f440b0924f16a36eea7045171a54da0a62efa48374ac678af36
unzip -p "$stage/pack.zip" '*.zip' >"$stage/inner.zip"
unzip -q "$stage/inner.zip" -d "$stage/server"
target="$stage/server"
grep -qx 'MODLOADER_VERSION=0.19.3' "$target/variables.txt"
fetch 'https://meta.fabricmc.net/v2/versions/loader/1.20.1/0.19.3/1.1.2/server/jar' "$target/fabric.jar" 0e4e87619d281f2f31d54a208a2ee5e68395cb3f332450ff2b8f7514249997d2
cp /etc/prominence-players.json "$target/whitelist.json"
echo 'eula=true' >"$target/eula.txt"
cat >"$target/server.properties" <<'PROPERTIES'
server-port=25565
online-mode=true
white-list=true
enforce-whitelist=true
enable-rcon=false
enable-query=false
max-players=5
view-distance=8
simulation-distance=6
level-name=world
PROPERTIES
touch "$target/.installed-v4.1.7"
mv -T "$target" server
