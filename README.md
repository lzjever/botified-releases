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

The managed installer supports Linux x86_64 and aarch64 with systemd. Download
and inspect the installer before choosing exactly one scope on a host:

```sh
installer=$(mktemp)
trap 'rm -f "$installer"' EXIT
curl -fL --retry 3 --retry-all-errors --connect-timeout 15 --silent --show-error \
  -o "$installer" \
  https://raw.githubusercontent.com/lzjever/botified-releases/main/install.sh
less "$installer"
```

### Managed User Service

User scope installs for the current non-root NSS user. It requires that the
administrator has already enabled systemd lingering for that user. Check it
before installation:

```sh
loginctl show-user "$USER" -p Linger --value
```

If the result is not exactly `yes`, an administrator may choose to enable it:

```sh
sudo loginctl enable-linger "$USER"
```

The installer never enables or changes Linger. Once the prerequisite is in
place, run:

```sh
sh "$installer" --scope user
```

### Managed System Service

System scope installs a system service running as the fixed non-root
`botified` account. Run the already downloaded and reviewed script with
explicit elevation:

```sh
sudo sh "$installer" --scope system
```

The installer does not call `sudo` itself.

### Managed Scope Behavior

Both scopes download and verify the matching Core bundle:

- `botified-core-linux-x86_64-musl.tar.gz`, a static-musl build for x86_64 Linux PCs and servers.
- `botified-core-linux-aarch64-gnu.tar.gz` for ARM64 Linux devices.

Core does not support macOS. On Darwin or any other unsupported platform, the
installer exits before downloading release assets.

Managed paths are fixed:

| Asset | User scope | System scope |
| --- | --- | --- |
| Binaries | `$HOME/.local/bin` | `/usr/local/bin` |
| Core skills and bundled units | `$HOME/.local/share/botified` | `/usr/local/share/botified` |
| Docs | `$HOME/.local/share/doc/botified` | `/usr/local/share/doc/botified` |
| Config | `$HOME/.config/botified/botified.yaml` | `/etc/botified/botified.yaml` |
| Process environment | `$HOME/.config/botified/botified.env` | `/etc/botified/botified.env` |
| Workspace and runtime data | `$HOME/.local/share/botified/workspace` | `/var/lib/botified/workspace` |
| Agent root | `$HOME/.agents` | `/var/lib/botified/.agents` |
| Canonical unit | `$HOME/.config/systemd/user/botified.service` | `/etc/systemd/system/botified.service` |
| Service identity | Current NSS user | `botified` user and group |

On first install, Core creates and validates a provider-neutral config. It does
not ask for provider, model, base URL, capability, service key, or API key.
Existing config, environment, workspace, runtime data, and unknown skill
siblings are preserved during repeat installation and upgrades.

Every successful managed run places the selected release and canonical unit,
then runs `daemon-reload`, `enable`, and `restart` in that order. It does this
even when reinstalling the same version; it does not compare file contents.
Before reporting success it verifies exact `enabled` and `active` states, a
non-zero stable `MainPID`, the running executable path, one Core-owned health
check bound to that `MainPID`, and the expected service identity. Core verifies
that the health responder belongs to the observed service process; the
installer independently confirms that the same PID still points to the scope's
target binary before and after health. User scope also rechecks Linger. These
identity-binding details are internal to managed installation; normal operator
health checks remain the simple commands below.

Use standard systemd and Core commands after installation:

```sh
# User scope
systemctl --user status botified.service
journalctl --user -u botified.service -n 100 --no-pager
$HOME/.local/bin/botified config check --config "$HOME/.config/botified/botified.yaml"
$HOME/.local/bin/botified health check --config "$HOME/.config/botified/botified.yaml"

# System scope
sudo systemctl status botified.service
sudo journalctl -u botified.service -n 100 --no-pager
/usr/local/bin/botified config check --config /etc/botified/botified.yaml
/usr/local/bin/botified health check --config /etc/botified/botified.yaml
```

Do not install both managed scopes on the same host. The installer only operates
the explicitly selected systemd manager and does not stop, disable, or repair
the other one.

### Manual Removal Of Managed Release Files

There is no installer-owned removal command. Before operating on a canonical
unit, verify that it is a regular file, is not a symlink, and that its first
line exactly equals:

```text
# Managed by the Botified installer. Inspect and operate with systemd tools.
```

If any check fails, treat the deployment as administrator-owned: do not stop,
disable, or delete the custom unit using managed-install instructions. For the
exact per-scope precheck, removal commands, and preserved-data boundary, follow
the canonical Core guide: [Transparent Manual Removal](https://github.com/lzjever/botified/blob/master/docs/install-upgrade.md#8-transparent-manual-removal).

## Files-Only Core Install

The no-argument command remains available as a legacy files-only leaf:

```sh
sh "$installer"
```

It downloads and verifies Core, then installs binaries, Core docs, and bundled
skills under the current user's `~/.local` directories. It does not create a
config or systemd unit, enable or start a service, or manage an existing
process. Use this leaf when an administrator or another supervisor owns the
lifecycle.

Only the no-argument files-only leaf accepts Core destination overrides:

```sh
env \
  BOTIFIED_INSTALL_DIR=/usr/local/bin \
  BOTIFIED_DOC_DIR=/usr/local/share/doc/botified \
  BOTIFIED_SHARE_DIR=/usr/local/share/botified \
  sh "$installer"
```

Managed `--scope user|system` uses its fixed layout and rejects these variables
and `BOTIFIED_PREFIX` before downloading.

## Install Gateway

Gateway is a separate companion install. The Core installer does not install,
configure, start, stop, or upgrade it; choose its service lifecycle separately.

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
# Keep the Core scope used for the original managed install:
BOTIFIED_VERSION="$VERSION" sh ./install.sh --scope user
# Or, for a system-scope host:
# sudo env BOTIFIED_VERSION="$VERSION" sh ./install.sh --scope system

# Upgrade Gateway independently:
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
BOTIFIED_VERSION=vX.Y.Z sh "$installer_dir/install.sh" --scope user
# For system scope instead:
# sudo env BOTIFIED_VERSION=vX.Y.Z sh "$installer_dir/install.sh" --scope system
BOTIFIED_VERSION=vX.Y.Z sh "$installer_dir/install-gateway.sh"
BOTIFIED_VERSION=vX.Y.Z sh "$installer_dir/install-playground.sh"
```

Replace `vX.Y.Z` with a published release tag. Versioned downloads use URLs
such as `https://github.com/lzjever/botified-releases/releases/download/vX.Y.Z/<asset>`.

## Companion Default Paths and PATH

Gateway, Playground, and files-only Core default to the user-writable
`~/.local` prefix. Managed Core uses the fixed scope paths documented above.

Add the command directory to your shell startup file if it is not already on
`PATH`:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

## Custom Companion Install Locations

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

- `botified-core-linux-x86_64-musl.tar.gz`
- `botified-core-linux-aarch64-gnu.tar.gz`
- `botified-claw-gateway-companion.tar.gz`
- `botified-playground.tar.gz`
- `SHA256SUMS`
