#!/bin/sh
set -eu

repo="${BOTIFIED_RELEASES_REPO:-lzjever/botified-releases}"
version="${BOTIFIED_VERSION:-latest}"
prefix="${BOTIFIED_PREFIX:-$HOME/.local}"
asset=botified-claw-gateway-companion.tar.gz

log() {
	printf '%s\n' "$*"
}

fail() {
	printf 'botified gateway install: %s\n' "$*" >&2
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

need_tar() {
	command -v tar >/dev/null 2>&1 || fail "tar is required"
}

need_node() {
	command -v node >/dev/null 2>&1 || fail "Node >=22.19 is required"
	if ! node -e 'const [major, minor] = process.versions.node.split(".").map(Number); process.exit(major > 22 || (major === 22 && minor >= 19) ? 0 : 1);'; then
		found=$(node -p 'process.versions.node' 2>/dev/null || printf unknown)
		fail "Node >=22.19 is required; found $found"
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

need_downloader
need_tar
need_node

tmpdir=$(mktemp -d 2>/dev/null || mktemp -d -t botified-gateway-install)
trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM

if [ "$version" = latest ]; then
	base_url="https://github.com/$repo/releases/latest/download"
else
	base_url="https://github.com/$repo/releases/download/$version"
fi

log "Installing botified-claw-gateway from $repo ($version)"
log "Install prefix: $prefix"

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

mkdir -p "$prefix"
tar -xzf "$tmpdir/$asset" -C "$prefix"

wrapper="$prefix/bin/botified-claw-gateway"
[ -x "$wrapper" ] || fail "bundle missing $wrapper"
"$wrapper" self-check

log ""
log "Installed: $wrapper"
case ":$PATH:" in
	*":$prefix/bin:"*) log "PATH already contains $prefix/bin." ;;
	*)
		log ""
		log "Add this to your shell startup file so your shell can find botified-claw-gateway:"
		log "  export PATH=\"$prefix/bin:\$PATH\""
		;;
esac

log ""
log "Try:"
log "  botified-claw-gateway setup --channel weixin --botified-base-url http://127.0.0.1:17777 --service-key <key>"
log "  botified-claw-gateway login"
log "  botified-claw-gateway serve"
