#!/bin/sh
set -eu

repo="${BOTIFIED_RELEASES_REPO:-lzjever/botified-releases}"
version="${BOTIFIED_VERSION:-latest}"
install_dir="${BOTIFIED_INSTALL_DIR:-$HOME/.local/bin}"
bin_name="${BOTIFIED_BIN_NAME:-botified}"

log() {
	printf '%s\n' "$*"
}

fail() {
	printf 'botified install: %s\n' "$*" >&2
	exit 1
}

need_downloader() {
	if command -v curl >/dev/null 2>&1; then
		downloader=curl
	elif command -v wget >/dev/null 2>&1; then
		downloader=wget
	else
		fail "curl or wget is required"
	fi
}

download() {
	url=$1
	out=$2
	if [ "$downloader" = curl ]; then
		curl -fsSL "$url" -o "$out"
	else
		wget -qO "$out" "$url"
	fi
}

os=$(uname -s 2>/dev/null || true)
arch=$(uname -m 2>/dev/null || true)

case "$os" in
	Linux) ;;
	*) fail "unsupported OS: ${os:-unknown}; only Linux binaries are published" ;;
esac

case "$arch" in
	x86_64|amd64)
		asset=botified-linux-x86_64-gnu
		;;
	aarch64|arm64)
		asset=botified-linux-aarch64-gnu
		;;
	*)
		fail "unsupported CPU architecture: ${arch:-unknown}; supported: x86_64, aarch64"
		;;
esac

need_downloader

tmpdir=$(mktemp -d 2>/dev/null || mktemp -d -t botified-install)
trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM

if [ "$version" = latest ]; then
	base_url="https://github.com/$repo/releases/latest/download"
else
	base_url="https://github.com/$repo/releases/download/$version"
fi

log "Installing botified from $repo ($version)"
log "Detected target: $asset"

download "$base_url/$asset" "$tmpdir/$asset"
download "$base_url/SHA256SUMS" "$tmpdir/SHA256SUMS"

if command -v sha256sum >/dev/null 2>&1; then
	(
		cd "$tmpdir"
		grep "  $asset\$" SHA256SUMS > "$asset.sha256" || fail "checksum for $asset not found"
		sha256sum -c "$asset.sha256" >/dev/null
	)
	log "Checksum verified."
else
	log "sha256sum not found; skipping checksum verification."
fi

mkdir -p "$install_dir"
if command -v install >/dev/null 2>&1; then
	install -m 0755 "$tmpdir/$asset" "$install_dir/$bin_name"
else
	cp "$tmpdir/$asset" "$install_dir/$bin_name"
	chmod 0755 "$install_dir/$bin_name"
fi

log "Installed: $install_dir/$bin_name"

case ":$PATH:" in
	*":$install_dir:"*)
		log "PATH already contains $install_dir."
		;;
	*)
		log ""
		log "Add this to your shell startup file so your shell can find botified:"
		log "  export PATH=\"$install_dir:\$PATH\""
		log ""
		log "For bash, you can run:"
		log "  printf '\\nexport PATH=\"$install_dir:\\\$PATH\"\\n' >> ~/.bashrc"
		log "  . ~/.bashrc"
		;;
esac

log ""
log "Try:"
log "  botified serve --config botified.yaml"
