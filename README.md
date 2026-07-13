# Botified Releases

Public installable releases for Botified.

## What Should I Install?

| Need | Install | What it gives you |
| --- | --- | --- |
| Run Botified service and terminal UI | Core | `botified`, `botified-tui`, core docs, official built-in skills |
| Connect Weixin or Feishu/Lark direct messages | Gateway | `botified-claw-gateway`; requires an already running Botified service and Node `>=22.19` |
| Try robot-side workflows locally | Playground | `botified-playground` virtual office robot modules and its bundled skill; requires Python `>=3.10` |

Install only what you need. The core installer does not install gateway or
playground.

## Install Core

```sh
curl -fsSL https://raw.githubusercontent.com/lzjever/botified-releases/main/install.sh | sh
```

The installer detects Linux x86_64 and Linux aarch64 automatically:

- `botified-core-linux-x86_64-gnu.tar.gz` for normal Linux PCs and servers.
- `botified-core-linux-aarch64-gnu.tar.gz` for ARM64 Linux devices.

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

## Install Gateway

```sh
curl -fsSL https://raw.githubusercontent.com/lzjever/botified-releases/main/install-gateway.sh | sh
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

## Install Playground

```sh
curl -fsSL https://raw.githubusercontent.com/lzjever/botified-releases/main/install-playground.sh | sh
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
curl -fsSL https://raw.githubusercontent.com/lzjever/botified-releases/main/install.sh | BOTIFIED_VERSION=v0.4.16 sh
curl -fsSL https://raw.githubusercontent.com/lzjever/botified-releases/main/install-gateway.sh | BOTIFIED_VERSION=v0.4.16 sh
curl -fsSL https://raw.githubusercontent.com/lzjever/botified-releases/main/install-playground.sh | BOTIFIED_VERSION=v0.4.16 sh
```

## Custom Install Locations

Core keeps separate destination variables for commands, docs, and shared files:

```sh
curl -fsSL https://raw.githubusercontent.com/lzjever/botified-releases/main/install.sh | \
  BOTIFIED_INSTALL_DIR=/usr/local/bin \
  BOTIFIED_DOC_DIR=/usr/local/share/doc/botified \
  BOTIFIED_SHARE_DIR=/usr/local/share/botified \
  sh
```

Gateway and playground use one prefix because their wrappers depend on matching
`bin` and `share` directories:

```sh
curl -fsSL https://raw.githubusercontent.com/lzjever/botified-releases/main/install-gateway.sh | BOTIFIED_PREFIX=/usr/local sh
curl -fsSL https://raw.githubusercontent.com/lzjever/botified-releases/main/install-playground.sh | BOTIFIED_PREFIX=/usr/local sh
```

Use a directory your user can write to, or run with the required permissions.

## Verify

```sh
botified --help
botified-tui --help
botified-claw-gateway self-check
botified-playground self-check
```

Checksums are published in each release as `SHA256SUMS`. Installers verify
checksums automatically when `sha256sum` is available.

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
