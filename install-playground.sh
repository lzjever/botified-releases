#!/bin/sh
set -eu

repo="${BOTIFIED_RELEASES_REPO:-lzjever/botified-releases}"
version="${BOTIFIED_VERSION:-latest}"
prefix="${BOTIFIED_PREFIX:-$HOME/.local}"
asset=botified-playground.tar.gz

log() {
	printf '%s\n' "$*"
}

fail() {
	printf 'botified playground install: %s\n' "$*" >&2
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

need_checksum() {
	if command -v sha256sum >/dev/null 2>&1; then
		checksum_tool=sha256sum
	elif command -v shasum >/dev/null 2>&1; then
		checksum_tool=shasum
	else
		fail "sha256sum or shasum is required"
	fi
}

valid_digest() {
	[ "${#1}" -eq 64 ] || return 1
	case "$1" in
		*[!0123456789abcdef]*) return 1 ;;
	esac
}

file_digest() {
	file=$1
	if [ "$checksum_tool" = sha256sum ]; then
		output=$(sha256sum "$file") || fail "could not checksum $asset"
	else
		output=$(shasum -a 256 "$file") || fail "could not checksum $asset"
	fi
	digest=${output%% *}
	valid_digest "$digest" || fail "checksum tool returned an invalid digest for $asset"
	printf '%s\n' "$digest"
}

verify_checksum() {
	manifest=$1
	file=$2
	target=$3
	expected=
	matches=0
	separator='  '

	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
			*"$separator"*)
				listed_digest=${line%%"$separator"*}
				listed_name=${line#*"$separator"}
				;;
			*) continue ;;
		esac
		if [ "$listed_name" = "$target" ]; then
			matches=$((matches + 1))
			expected=$listed_digest
		fi
	done < "$manifest"

	[ "$matches" -eq 1 ] || fail "checksum for $target must appear exactly once"
	valid_digest "$expected" || fail "invalid checksum for $target; expected 64 lowercase hex characters"
	actual=$(file_digest "$file")
	[ "$actual" = "$expected" ] || fail "checksum mismatch for $target"
}

need_python() {
	command -v python3 >/dev/null 2>&1 || fail "python3 >=3.10 is required"
	if ! python3 - <<'PY' >/dev/null 2>&1
import sys
raise SystemExit(0 if sys.version_info >= (3, 10) else 1)
PY
	then
		found=$(python3 - <<'PY' 2>/dev/null || printf unknown
import sys
print(".".join(map(str, sys.version_info[:3])))
PY
)
		fail "python3 >=3.10 is required; found $found"
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
need_python

tmpdir=$(mktemp -d 2>/dev/null || mktemp -d -t botified-playground-install)
trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM

if [ "$version" = latest ]; then
	base_url="https://github.com/$repo/releases/latest/download"
else
	base_url="https://github.com/$repo/releases/download/$version"
fi

log "Installing botified-playground from $repo ($version)"
log "Install prefix: $prefix"

download "$base_url/$asset" "$tmpdir/$asset"
download "$base_url/SHA256SUMS" "$tmpdir/SHA256SUMS"

need_checksum
verify_checksum "$tmpdir/SHA256SUMS" "$tmpdir/$asset" "$asset"
log "Checksum verified."

mkdir -p "$prefix"
tar -xzf "$tmpdir/$asset" -C "$prefix"

wrapper="$prefix/bin/botified-playground"
[ -x "$wrapper" ] || fail "bundle missing $wrapper"
"$wrapper" self-check

log ""
log "Installed: $wrapper"
log "Installed skill: $prefix/share/botified/skills/robot-playground"
case ":$PATH:" in
	*":$prefix/bin:"*) log "PATH already contains $prefix/bin." ;;
	*)
		log ""
		log "Add this to your shell startup file so your shell can find botified-playground:"
		log "  export PATH=\"$prefix/bin:\$PATH\""
		;;
esac

log ""
log "Try:"
log "  botified-playground launch --agent off --bus-port 18765"
log "  open http://127.0.0.1:18765/ui/"
log "  botified-playground scenario visitor_delivery --bus http://127.0.0.1:18765 --once"
