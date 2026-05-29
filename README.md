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

The installer also installs two curl-based helper tools:

```sh
~/.local/bin/botified-chat
~/.local/bin/botified-monitor
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
curl -fsSL https://raw.githubusercontent.com/lzjever/botified-releases/main/install.sh | BOTIFIED_VERSION=v0.2.2 sh
```

## Custom Install Directory

```sh
curl -fsSL https://raw.githubusercontent.com/lzjever/botified-releases/main/install.sh | BOTIFIED_INSTALL_DIR=/usr/local/bin sh
```

Use a directory that your user can write to, or run with the required permissions.

## Verify

```sh
botified --help
botified-chat --help
botified-monitor --help
```

Checksums are published in each release as `SHA256SUMS`. The installer verifies checksums automatically when `sha256sum` is available.

## Quick Service Testing

Both helper tools use the same environment:

```sh
export BOTIFIED_BASE_URL=http://127.0.0.1:17777
export BOTIFIED_SERVICE_KEY=dev
```

If your Botified service has no service key configured, leave
`BOTIFIED_SERVICE_KEY` unset.

Interactive message loop:

```sh
botified-chat
```

Continuous public event monitor:

```sh
botified-monitor
```

Both tools write public Botified NDJSON events to stdout and status/errors to
stderr, so the output can be parsed by other clients.

## Current Assets

Each release publishes:

- `botified-linux-x86_64-gnu`
- `botified-linux-aarch64-gnu`
- `botified-chat`
- `botified-monitor`
- `SHA256SUMS`
