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

need_node() {
	command -v node >/dev/null 2>&1 || fail "Node >=22.19 <23 is required"
}

download() {
	url=$1
	out=$2
	if [ "$downloader" = curl ]; then
		curl -fL --retry 3 --retry-all-errors --connect-timeout 15 --silent --show-error -o "$out" "$url"
	else
		wget -q --tries=4 --timeout=30 -O "$out" "$url"
	fi
}

replace_tree() {
	source_dir=$1
	destination_dir=$2
	mkdir -p "$(dirname "$destination_dir")"
	rm -rf "$destination_dir"
	mv "$source_dir" "$destination_dir"
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

need_checksum
verify_checksum "$tmpdir/SHA256SUMS" "$tmpdir/$asset" "$asset"
log "Checksum verified."

mkdir -p "$prefix"
bundle_dir="$tmpdir/bundle"
mkdir -p "$bundle_dir"
tar -xzf "$tmpdir/$asset" -C "$bundle_dir"

staged_wrapper="$bundle_dir/bin/botified-claw-gateway"
[ -x "$staged_wrapper" ] || fail "bundle missing bin/botified-claw-gateway"
for staged_tree in \
	"$bundle_dir/share/botified/gateway" \
	"$bundle_dir/share/doc/botified-claw-gateway" \
	"$bundle_dir/share/botified-claw-gateway/examples"
do
	[ -d "$staged_tree" ] || fail "bundle missing ${staged_tree#"$bundle_dir"/}"
done
"$staged_wrapper" self-check

replace_tree "$bundle_dir/share/botified/gateway" "$prefix/share/botified/gateway"
replace_tree "$bundle_dir/share/doc/botified-claw-gateway" "$prefix/share/doc/botified-claw-gateway"
replace_tree "$bundle_dir/share/botified-claw-gateway/examples" "$prefix/share/botified-claw-gateway/examples"
mkdir -p "$prefix/bin"
wrapper="$prefix/bin/botified-claw-gateway"
if command -v install >/dev/null 2>&1; then
	install -m 0755 "$staged_wrapper" "$wrapper"
else
	cp "$staged_wrapper" "$wrapper"
	chmod 0755 "$wrapper"
fi

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
log "  botified-claw-gateway --help"
log "  botified-claw-gateway self-check"
