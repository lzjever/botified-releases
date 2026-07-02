#!/bin/sh
set -eu

repo="${BOTIFIED_RELEASES_REPO:-lzjever/botified-releases}"
version="${BOTIFIED_VERSION:-latest}"
install_dir="${BOTIFIED_INSTALL_DIR:-$HOME/.local/bin}"
share_dir="${BOTIFIED_SHARE_DIR:-$HOME/.local/share/botified}"
doc_dir="${BOTIFIED_DOC_DIR:-$HOME/.local/share/doc/botified}"

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

need_tar() {
	if ! command -v tar >/dev/null 2>&1; then
		fail "tar is required"
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
		asset=botified-core-linux-x86_64-gnu.tar.gz
		;;
	aarch64|arm64)
		asset=botified-core-linux-aarch64-gnu.tar.gz
		;;
	*)
		fail "unsupported CPU architecture: ${arch:-unknown}; supported: x86_64, aarch64"
		;;
esac

need_downloader
need_tar

tmpdir=$(mktemp -d 2>/dev/null || mktemp -d -t botified-install)
trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM

if [ "$version" = latest ]; then
	base_url="https://github.com/$repo/releases/latest/download"
else
	base_url="https://github.com/$repo/releases/download/$version"
fi

log "Installing botified from $repo ($version)"
log "Detected core bundle: $asset"

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

bundle_dir="$tmpdir/bundle"
mkdir -p "$bundle_dir"
tar -xzf "$tmpdir/$asset" -C "$bundle_dir"

[ -f "$bundle_dir/bin/botified" ] || fail "bundle missing bin/botified"
[ -f "$bundle_dir/bin/botified-tui" ] || fail "bundle missing bin/botified-tui"
[ -d "$bundle_dir/share/botified/skills" ] || fail "bundle missing share/botified/skills"
[ -d "$bundle_dir/share/doc/botified" ] || fail "bundle missing share/doc/botified"

mkdir -p "$install_dir"
for name in botified botified-tui; do
	if command -v install >/dev/null 2>&1; then
		install -m 0755 "$bundle_dir/bin/$name" "$install_dir/$name"
	else
		cp "$bundle_dir/bin/$name" "$install_dir/$name"
		chmod 0755 "$install_dir/$name"
	fi
done

skill_dir="$share_dir/skills"
mkdir -p "$skill_dir"
(
	cd "$bundle_dir/share/botified/skills"
	tar -cf - .
) | (
	cd "$skill_dir"
	tar -xf -
)

mkdir -p "$doc_dir"
(
	cd "$bundle_dir/share/doc/botified"
	tar -cf - .
) | (
	cd "$doc_dir"
	tar -xf -
)

log "Installed: $install_dir/botified"
log "Installed: $install_dir/botified-tui"
log "Installed skills: $skill_dir"
log "Installed docs: $doc_dir"

case ":$PATH:" in
	*":$install_dir:"*)
		log "PATH already contains $install_dir."
		;;
	*)
		log ""
		log "Add this to your shell startup file so your shell can find botified and botified-tui:"
		log "  export PATH=\"$install_dir:\$PATH\""
		log ""
		log "For bash, you can run:"
		log "  printf '\\nexport PATH=\"$install_dir:\\\$PATH\"\\n' >> ~/.bashrc"
		log "  . ~/.bashrc"
		;;
esac

log ""
log "Try:"
log "  botified serve --config botified.yaml  # creates missing config, then exits"
log "  export BOTIFIED_SERVICE_KEY=dev"
log "  botified serve --mock-provider --config botified.yaml"
log "  botified-tui --base-url http://127.0.0.1:17777"
