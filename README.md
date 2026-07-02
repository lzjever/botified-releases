# Botified Releases

Public core bundle releases for Botified.

This repository only contains release distribution material. The Botified source repository remains private; installable core bundles are published as GitHub Release assets here.

## Install

Run:

```sh
curl -fsSL https://raw.githubusercontent.com/lzjever/botified-releases/main/install.sh | sh
```

The installer detects Linux x86_64 and Linux aarch64 automatically:

- `botified-core-linux-x86_64-gnu.tar.gz` for normal Linux PCs and servers.
- `botified-core-linux-aarch64-gnu.tar.gz` for ARM64 Linux devices, including Unitree R1-style runtime environments.

By default, the commands are installed to:

```sh
~/.local/bin/botified
~/.local/bin/botified-tui
```

Bundle documentation from `share/doc/botified` is copied to:

```sh
~/.local/share/doc/botified
```

Official bundled skills from `share/botified/skills` are copied to:

```sh
~/.local/share/botified/skills
```

If your shell cannot find `botified` or `botified-tui`, add this to your shell startup file:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

For bash:

```sh
printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> ~/.bashrc
. ~/.bashrc
```

## Install A Specific Version

```sh
curl -fsSL https://raw.githubusercontent.com/lzjever/botified-releases/main/install.sh | BOTIFIED_VERSION=v0.4.3 sh
```

## Custom Install Directory

```sh
curl -fsSL https://raw.githubusercontent.com/lzjever/botified-releases/main/install.sh | BOTIFIED_INSTALL_DIR=/usr/local/bin sh
```

Use a directory that your user can write to, or run with the required permissions.

## Custom Documentation Directory

```sh
curl -fsSL https://raw.githubusercontent.com/lzjever/botified-releases/main/install.sh | BOTIFIED_DOC_DIR=/usr/local/share/doc/botified sh
```

Use a directory that your user can write to, or run with the required permissions.

## Custom Share Directory

```sh
curl -fsSL https://raw.githubusercontent.com/lzjever/botified-releases/main/install.sh | BOTIFIED_SHARE_DIR=/usr/local/share/botified sh
```

Official skills are installed under `$BOTIFIED_SHARE_DIR/skills`.
Default installs do not need this; if you customize the share directory, run Botified with the same install prefix or set `BOTIFIED_SHARE_DIR` so it can find that share root.

## Verify

```sh
botified --help
botified-tui --help
test -f "$HOME/.local/share/botified/skills/botified-module-dev/SKILL.md"
test -f "$HOME/.local/share/botified/skills/botified-skill-creator/SKILL.md"
```

Checksums are published in each release as `SHA256SUMS`. The installer verifies checksums automatically when `sha256sum` is available.

## Quick Service Testing

First generate a default config, set the service key, then start the mock provider service:

```sh
botified serve --config botified.yaml
export BOTIFIED_SERVICE_KEY=dev
botified serve --mock-provider --config botified.yaml
```

In another shell, use curl examples against the HTTP API:

```sh
BASE=http://127.0.0.1:17777
export BOTIFIED_SERVICE_KEY=dev
AUTH="Authorization: Bearer $BOTIFIED_SERVICE_KEY"
curl -s "$BASE/healthz"
curl -s "$BASE/v1/state" -H "$AUTH" \
  | jq '{state, queue_length, tasks, last_error, session_id, timeline_cursor}'
CURSOR=$(curl -s -X POST "$BASE/v1/messages" \
  -H "$AUTH" \
  -H 'Content-Type: application/json' \
  -d '{"client_message_id":"demo-1","text":"Reply in one short sentence."}' \
  | jq -r .timeline_cursor)
curl -s -D headers.txt "$BASE/v1/timeline?cursor=$CURSOR&follow=false" -H "$AUTH"
NEXT=$(awk 'BEGIN { IGNORECASE=1 } /^x-botified-next-cursor:/ { print $2 }' headers.txt | tr -d '\r')
curl -N "$BASE/v1/timeline?cursor=$NEXT&follow=true" -H "$AUTH"
```

If your Botified service has no service key configured, leave
the `Authorization` header out.

## Current Assets

Each release publishes:

- `botified-core-linux-x86_64-gnu.tar.gz`
- `botified-core-linux-aarch64-gnu.tar.gz`
- `SHA256SUMS`

The main public release surface is the core bundle only. OpenClaw gateway and playground artifacts are intentionally not part of this release.
