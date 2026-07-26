# Botified Releases

Public installable releases for Botified.

## What Should I Install?

| Need | Install | What it gives you |
| --- | --- | --- |
| Run Botified service and terminal UI | Core | `botified`, `botified-tui`, core docs, official built-in skills |
| Connect Weixin, Feishu/Lark, or Matrix direct messages | Gateway | `botified-claw-gateway`; requires an already running Botified service and Node `>=22.19 <23` |
| Try robot-side workflows locally | Playground | `botified-playground` virtual office robot modules and its bundled skill; requires Python `>=3.10` |

Install only what you need. The core installer does not install gateway or
playground.

## Install Core

On Linux x86_64 or aarch64, run:

```sh
installer=$(mktemp)
trap 'rm -f "$installer"' EXIT
curl -fL --retry 3 --retry-all-errors --connect-timeout 15 --silent --show-error \
  -o "$installer" \
  https://raw.githubusercontent.com/lzjever/botified-releases/main/install.sh
sh "$installer"
```

The installer detects the operating system and architecture automatically:

- `botified-core-linux-x86_64-gnu.tar.gz` for normal Linux PCs and servers.
- `botified-core-linux-aarch64-gnu.tar.gz` for ARM64 Linux devices.

Core does not support macOS. On Darwin or any other unsupported platform, the
installer exits before downloading release assets.

By default, commands are installed to:

```sh
~/.local/bin/botified
~/.local/bin/botified-tui
```

Docs and skills are installed to:

```sh
~/.local/share/doc/botified
~/.local/share/botified/skills
```

Make sure `~/.local/bin` is on `PATH`. The installer prints the shell command
to add it when needed. Verify the core install with:

```sh
botified --version
botified-tui --help
```

## Install Gateway

```sh
installer=$(mktemp)
trap 'rm -f "$installer"' EXIT
curl -fL --retry 3 --retry-all-errors --connect-timeout 15 --silent --show-error \
  -o "$installer" \
  https://raw.githubusercontent.com/lzjever/botified-releases/main/install-gateway.sh
sh "$installer"
```

Then configure the channel you need:

```sh
botified-claw-gateway setup \
  --channel weixin \
  --botified-base-url http://127.0.0.1:17777 \
  --service-key <botified-service-key>
botified-claw-gateway login
botified-claw-gateway serve
```

For Feishu/Lark:

```sh
botified-claw-gateway setup \
  --channel feishu \
  --botified-base-url http://127.0.0.1:17777 \
  --service-key <botified-service-key> \
  --feishu-app-id <app-id> \
  --feishu-app-secret <app-secret> \
  --feishu-domain feishu
botified-claw-gateway serve
```

For Matrix, create an unencrypted direct room containing exactly the gateway
account and one trusted user. The gateway account must manually join the room;
the Gateway does not create rooms or accept invitations. Its access token
selects the bot MXID, so there is no separate bot ID setting:

```sh
export MATRIX_ACCESS_TOKEN="<matrix-access-token>"
botified-claw-gateway setup \
  --channel matrix \
  --botified-base-url http://127.0.0.1:17777 \
  --service-key <botified-service-key> \
  --matrix-homeserver https://matrix.walayun.com \
  --matrix-allow-from "@trusted-user:matrix.walayun.com"
unset MATRIX_ACCESS_TOKEN
botified-claw-gateway serve
```

Matrix supports allowlisted text and standard media in manually joined,
unencrypted direct rooms. It does not support groups, encrypted rooms, or
automatic invitation acceptance.

## Upgrade A Core + Gateway Host

Core and Gateway are separate installs. On a host that runs both, pin one
release and rerun both downloaded installers from the directory that contains
them:

```sh
VERSION=vX.Y.Z
BOTIFIED_VERSION="$VERSION" sh ./install.sh
BOTIFIED_VERSION="$VERSION" sh ./install-gateway.sh

botified --version
botified-claw-gateway --version
botified-claw-gateway self-check
```

The two version commands must report `${VERSION#v}`. The Core installer does
not upgrade an existing Gateway; it prints a warning when it detects one.

## Install Playground

```sh
installer=$(mktemp)
trap 'rm -f "$installer"' EXIT
curl -fL --retry 3 --retry-all-errors --connect-timeout 15 --silent --show-error \
  -o "$installer" \
  https://raw.githubusercontent.com/lzjever/botified-releases/main/install-playground.sh
sh "$installer"
```

Start the local virtual office robot stack:

```sh
botified-playground launch --agent off --bus-port 18765
```

Open the UI:

```text
http://127.0.0.1:18765/ui/
```

Trigger a scenario from another shell:

```sh
botified-playground scenario visitor_delivery --bus http://127.0.0.1:18765 --once
```

## Install A Specific Version

The three installers share the same version pin:

```sh
installer_dir=$(mktemp -d)
trap 'rm -rf "$installer_dir"' EXIT
for component in install install-gateway install-playground; do
  curl -fL --retry 3 --retry-all-errors --connect-timeout 15 --silent --show-error \
    -o "$installer_dir/$component.sh" \
    "https://raw.githubusercontent.com/lzjever/botified-releases/main/$component.sh"
done
BOTIFIED_VERSION=vX.Y.Z sh "$installer_dir/install.sh"
BOTIFIED_VERSION=vX.Y.Z sh "$installer_dir/install-gateway.sh"
BOTIFIED_VERSION=vX.Y.Z sh "$installer_dir/install-playground.sh"
```

Replace `vX.Y.Z` with a published release tag. Versioned downloads use URLs
such as `https://github.com/lzjever/botified-releases/releases/download/vX.Y.Z/<asset>`.

## Default Paths and PATH

All installers default to the user-writable `~/.local` prefix. Core installs
its commands in `~/.local/bin`, skills in `~/.local/share/botified/skills`, and
docs in `~/.local/share/doc/botified`. Gateway and playground install their
commands in `~/.local/bin` and their supporting files under `~/.local/share`.

Add the command directory to your shell startup file if it is not already on
`PATH`:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

## Custom Install Locations

Core keeps separate destination variables for commands, docs, and shared files:

```sh
installer=$(mktemp)
trap 'rm -f "$installer"' EXIT
curl -fL --retry 3 --retry-all-errors --connect-timeout 15 --silent --show-error \
  -o "$installer" \
  https://raw.githubusercontent.com/lzjever/botified-releases/main/install.sh
env \
  BOTIFIED_INSTALL_DIR=/usr/local/bin \
  BOTIFIED_DOC_DIR=/usr/local/share/doc/botified \
  BOTIFIED_SHARE_DIR=/usr/local/share/botified \
  sh "$installer"
```

Gateway and playground use one prefix because their wrappers depend on matching
`bin` and `share` directories:

```sh
installer_dir=$(mktemp -d)
trap 'rm -rf "$installer_dir"' EXIT
for component in install-gateway install-playground; do
  curl -fL --retry 3 --retry-all-errors --connect-timeout 15 --silent --show-error \
    -o "$installer_dir/$component.sh" \
    "https://raw.githubusercontent.com/lzjever/botified-releases/main/$component.sh"
done
BOTIFIED_PREFIX=/usr/local sh "$installer_dir/install-gateway.sh"
BOTIFIED_PREFIX=/usr/local sh "$installer_dir/install-playground.sh"
```

Use a directory your user can write to, or run with the required permissions.

## Verify

```sh
botified --help
botified-tui --help
botified-claw-gateway self-check
botified-playground self-check
```

Checksums are published in each release as `SHA256SUMS`. Before extracting or
executing a downloaded bundle, every installer verifies its exact asset entry.
It prefers `sha256sum` and falls back to `shasum -a 256`; installation fails if
neither command is available or if the entry is missing, duplicated, malformed,
or does not match the downloaded file.

## Quick Service Testing

Generate a mock config, set the service key, then start the mock provider
service:

```sh
botified setup --mock --config botified.mock.yaml
export BOTIFIED_SERVICE_KEY=dev
botified serve --mock-provider --config botified.mock.yaml
```

In another shell:

```sh
BASE=http://127.0.0.1:17777
curl -s "$BASE/healthz"
curl -s "$BASE/v1/state" -H "Authorization: Bearer dev"
```

If your Botified service has no service key configured, leave the
`Authorization` header out.

## Release Assets

Each release publishes:

- `botified-core-linux-x86_64-gnu.tar.gz`
- `botified-core-linux-aarch64-gnu.tar.gz`
- `botified-claw-gateway-companion.tar.gz`
- `botified-playground.tar.gz`
- `SHA256SUMS`
