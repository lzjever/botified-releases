# Botified Releases

Public installable releases for Botified.

## What Should I Install?

| Entry | Command | For |
| --- | --- | --- |
| Core quick start | `install.sh` | Try Botified without systemd |
| Core managed service | `install.sh --scope user\|system` | Resident service with systemd |
| Gateway managed channels | `install-gateway.sh --scope user\|system [--channel …]` | Weixin/Feishu/Matrix bridging (needs Core + Node `>=22.19 <23`) |
| Fully offline | download `botified-offline-linux-<arch>.tar.gz`, run `install-offline.sh` | Air-gapped hosts (pre-install Node/Python per entry needs) |

Core quick start installs `botified`, `botified-tui`, core docs, and official
built-in skills under `~/.local` without creating a service. Core managed
service adds a systemd-managed `botified.service` in one fixed scope. Gateway
channels require an already running managed Core service in the same scope.

Install only what you need. The core installer does not install gateway.

## Install Core

The Core installer supports Linux x86_64 and aarch64. Download and inspect the
installer, then pick the entry that matches how Core should run on the host:

```sh
installer=$(mktemp)
trap 'rm -f "$installer"' EXIT
curl -fL --retry 3 --retry-all-errors --connect-timeout 15 --silent --show-error \
  -o "$installer" \
  https://raw.githubusercontent.com/lzjever/botified-releases/main/install.sh
less "$installer"
```

### Quick Start Without systemd

The no-argument command is the fastest way to try Botified. It downloads and
verifies Core, then installs binaries, Core docs, and bundled skills under the
current user's `~/.local` directories:

```sh
sh "$installer"
```

It does not create a config or systemd unit, enable or start a service, or
manage an existing process. Use this entry for a first look at Core, or when
an administrator or another supervisor owns the lifecycle.

Only this no-argument entry accepts Core destination overrides:

```sh
env \
  BOTIFIED_INSTALL_DIR=/usr/local/bin \
  BOTIFIED_DOC_DIR=/usr/local/share/doc/botified \
  BOTIFIED_SHARE_DIR=/usr/local/share/botified \
  sh "$installer"
```

Managed `--scope user|system` uses its fixed layout and rejects these variables
and `BOTIFIED_PREFIX` before downloading.

### Managed Service With systemd

For a resident service under systemd, choose exactly one scope on a host.

#### Managed User Service

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

#### Managed System Service

System scope installs a system service running as the fixed non-root
`botified` account. Run the already downloaded and reviewed script with
explicit elevation:

```sh
sudo sh "$installer" --scope system
```

The installer does not call `sudo` itself.

#### Managed Scope Behavior

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

#### Manual Removal Of Managed Release Files

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

## Install Gateway

Gateway is a separate companion install with its own managed installer. It
requires that Core is already installed as a managed service in the same
scope, and Node `>=22.19 <23`. The Core installer does not install,
configure, start, stop, or upgrade it.

```sh
installer=$(mktemp)
trap 'rm -f "$installer"' EXIT
curl -fL --retry 3 --retry-all-errors --connect-timeout 15 --silent --show-error \
  -o "$installer" \
  https://raw.githubusercontent.com/lzjever/botified-releases/main/install-gateway.sh
sh "$installer" --scope user --channel weixin
# Or, under the fixed system account:
# sudo sh "$installer" --scope system --channel weixin
```

`--channel` accepts `weixin`, `feishu`, or `matrix`, repeated or
comma-separated, and defaults to `weixin`; each channel becomes one
independent `botified-claw-gateway-<channel>.service` instance. With no
arguments at all the installer asks interactively for the scope and channels.

A first install places the wrapper, share trees, per-channel config
skeletons, and units, but does not enable or start anything — the skeleton
holds no credentials. The installer prints the activation steps; for Weixin:

```sh
botified-claw-gateway setup \
  --channel weixin \
  --config ~/.config/botified/gateway/weixin-gateway.yaml
botified-claw-gateway login \
  --config ~/.config/botified/gateway/weixin-gateway.yaml
systemctl --user enable --now botified-claw-gateway-weixin.service
```

`setup` prompts for missing values, including the Botified service key, and
does not echo secrets; the flags remain the automation path
(`setup --help`). For Feishu/Lark there is no login step:

```sh
botified-claw-gateway setup \
  --channel feishu \
  --config ~/.config/botified/gateway/feishu-gateway.yaml \
  --botified-base-url http://127.0.0.1:17777 \
  --feishu-app-id <app-id> \
  --feishu-app-secret <app-secret> \
  --feishu-domain feishu
systemctl --user enable --now botified-claw-gateway-feishu.service
```

For Matrix, create an unencrypted direct room containing exactly the gateway
account and one trusted user. The gateway account must manually join the room;
the Gateway does not create rooms or accept invitations. Its access token
selects the bot MXID, so there is no separate bot ID setting:

```sh
export MATRIX_ACCESS_TOKEN="<matrix-access-token>"
botified-claw-gateway setup \
  --channel matrix \
  --config ~/.config/botified/gateway/matrix-gateway.yaml \
  --botified-base-url http://127.0.0.1:17777 \
  --matrix-homeserver https://matrix.walayun.com \
  --matrix-allow-from "@trusted-user:matrix.walayun.com"
unset MATRIX_ACCESS_TOKEN
systemctl --user enable --now botified-claw-gateway-matrix.service
```

Matrix supports allowlisted text and standard media in manually joined,
unencrypted direct rooms. It does not support groups, encrypted rooms, or
automatic invitation acceptance.

Under system scope the channel configs live in `/etc/botified/gateway/` with
runtime data under `/var/lib/botified/gateway/<channel>/`; run `setup` and
`login` through `sudo` and see the companion README for the ownership steps.
Installer exit codes and upgrade semantics are documented in the Core guide's
[Managed Install And Upgrade Semantics](https://github.com/lzjever/botified/blob/master/docs/install-upgrade.md#4-managed-install-and-upgrade-semantics).

## Upgrade A Core + Gateway Host

Core and Gateway are separate installs. On a host that runs both, pin one
release and rerun both downloaded installers from the directory that contains
them, keeping the original scope and channels:

```sh
VERSION=vX.Y.Z
# Keep the Core scope used for the original managed install:
BOTIFIED_VERSION="$VERSION" sh ./install.sh --scope user
# Or, for a system-scope host:
# sudo env BOTIFIED_VERSION="$VERSION" sh ./install.sh --scope system

# Upgrade Gateway independently, with the same scope and channels:
BOTIFIED_VERSION="$VERSION" sh ./install-gateway.sh --scope user --channel weixin
# Or, for a system-scope host:
# sudo env BOTIFIED_VERSION="$VERSION" sh ./install-gateway.sh --scope system --channel weixin

botified --version
botified-claw-gateway --version
botified-claw-gateway self-check
```

The two version commands must report `${VERSION#v}`. The Core installer does
not upgrade an existing Gateway; it prints a warning when it detects one.

Upgrade Core first: its restart stops every enabled Gateway channel through
`Requires=botified.service` and does not guarantee restarting them. Rerunning
the Gateway installer afterwards recovers each enabled channel — it replaces
the release files, restarts the channel unit, and proves the running
process — or restart each channel unit manually with
`systemctl [--user] restart botified-claw-gateway-<channel>.service`.

## Install A Specific Version

The two installers share the same version pin:

```sh
installer_dir=$(mktemp -d)
trap 'rm -rf "$installer_dir"' EXIT
for component in install install-gateway; do
  curl -fL --retry 3 --retry-all-errors --connect-timeout 15 --silent --show-error \
    -o "$installer_dir/$component.sh" \
    "https://raw.githubusercontent.com/lzjever/botified-releases/main/$component.sh"
done
BOTIFIED_VERSION=vX.Y.Z sh "$installer_dir/install.sh" --scope user
# For system scope instead:
# sudo env BOTIFIED_VERSION=vX.Y.Z sh "$installer_dir/install.sh" --scope system
BOTIFIED_VERSION=vX.Y.Z sh "$installer_dir/install-gateway.sh" --scope user --channel weixin
# For system scope instead:
# sudo env BOTIFIED_VERSION=vX.Y.Z sh "$installer_dir/install-gateway.sh" --scope system --channel weixin
```

Replace `vX.Y.Z` with a published release tag. Versioned downloads use URLs
such as `https://github.com/lzjever/botified-releases/releases/download/vX.Y.Z/<asset>`.

## Install Fully Offline

For an air-gapped host, download the aggregate bundle for its architecture —
`botified-offline-linux-x86_64.tar.gz` or
`botified-offline-linux-aarch64-gnu.tar.gz` — and move it to the host with any
offline medium. The bundle carries `install-offline.sh`, `install.sh`,
`install-gateway.sh`, the matching core and gateway companion tarballs,
`SHA256SUMS`, and `INSTALLER-SOURCE`. The orchestrator checks that every
member is present, then runs the same installers as the online entries —
each installer verifies its asset checksums against the bundled `SHA256SUMS`
before placing anything, and nothing is downloaded:

```sh
mkdir botified-offline
tar -xzf botified-offline-linux-x86_64.tar.gz -C botified-offline
cd botified-offline
sh install-offline.sh --core-only    # Entry 1 offline
sh install-offline.sh --scope user   # Entry 2 offline
# Entry 3 offline (installs Core first, then Gateway):
sh install-offline.sh --scope user --gateway --channel weixin
```

`--gateway` requires `--scope`. With no arguments at all the orchestrator asks
interactively for the form, scope, and channels. Air-gapped hosts must already
provide the runtimes the chosen entry needs at runtime — Node `>=22.19 <23`
for Gateway, Python 3 for Python managed tasks and skills — because the
installers never download or install a runtime.

## Companion Default Paths and PATH

User-scope Gateway and files-only Core use the user-writable `~/.local`
prefix; system-scope Gateway and managed Core use the fixed scope paths
documented above. A manually unpacked companion lives wherever you extracted
it.

Add the command directory to your shell startup file if it is not already on
`PATH`:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

## Custom Companion Install Locations

The Gateway installer is managed-only: it has no files-only form, and it
rejects `BOTIFIED_PREFIX` — and Core's files-only destination overrides —
before downloading. Gateway still uses one prefix because its wrapper depends
on matching `bin` and `share` directories. For a custom prefix, download and
verify the companion tarball from one pinned release and unpack it by hand:

```sh
VERSION=vX.Y.Z
BASE="https://github.com/lzjever/botified-releases/releases/download/$VERSION"
GATEWAY=botified-claw-gateway-companion.tar.gz

curl -fL "$BASE/$GATEWAY" -o "$GATEWAY"
curl -fL "$BASE/SHA256SUMS" -o SHA256SUMS
grep "  $GATEWAY$" SHA256SUMS | sha256sum -c -

mkdir -p /opt/botified-claw-gateway
tar -xzf "$GATEWAY" -C /opt/botified-claw-gateway
export PATH=/opt/botified-claw-gateway/bin:$PATH
botified-claw-gateway self-check
```

Use a directory your user can write to, or run with the required permissions.
Such a deployment owns its own unit and lifecycle; the managed installer
refuses custom units (exit 3).

## Verify

```sh
botified --help
botified-tui --help
botified-claw-gateway self-check
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
- `botified-offline-linux-x86_64.tar.gz`
- `botified-offline-linux-aarch64-gnu.tar.gz`
- `SHA256SUMS`

## Playground For Developers

The playground is a development surface and is no longer offered as a public
install entry. Its source, bundled skill, and tests stay in the Botified
repository:

```sh
git clone https://github.com/lzjever/botified.git
cd botified/botified-playground
```

Run it from the checkout with
`python3 -m botified_playground.launch_local --agent off`; see the
[playground README](https://github.com/lzjever/botified/blob/master/botified-playground/README.md)
for the UI, scenarios, and the optional `make playground-test` checks.
