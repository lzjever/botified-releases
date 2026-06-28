# Botified Releases

Public binary releases for Botified.

This repository only contains release distribution material. The Botified source repository remains private; installable binaries are published as GitHub Release assets here.

## Install

Run:

```sh
curl -fsSL https://raw.githubusercontent.com/lzjever/botified-releases/main/install.sh | sh
```

The installer detects Linux x86_64 and Linux aarch64 automatically:

- `botified-linux-x86_64-gnu` for normal Linux PCs and servers.
- `botified-linux-aarch64-gnu` for ARM64 Linux devices, including Unitree R1-style runtime environments.

By default, the binary is installed to:

```sh
~/.local/bin/botified
```

If your shell cannot find `botified`, add this to your shell startup file:

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
curl -fsSL https://raw.githubusercontent.com/lzjever/botified-releases/main/install.sh | BOTIFIED_VERSION=v0.3.0 sh
```

## Custom Install Directory

```sh
curl -fsSL https://raw.githubusercontent.com/lzjever/botified-releases/main/install.sh | BOTIFIED_INSTALL_DIR=/usr/local/bin sh
```

Use a directory that your user can write to, or run with the required permissions.

## Verify

```sh
botified --help
```

Checksums are published in each release as `SHA256SUMS`. The installer verifies checksums automatically when `sha256sum` is available.

## Quick Service Testing

Use curl examples against the HTTP API:

```sh
BASE=http://127.0.0.1:17777
AUTH='Authorization: Bearer dev'
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

- `botified-linux-x86_64-gnu`
- `botified-linux-aarch64-gnu`
- `SHA256SUMS`
