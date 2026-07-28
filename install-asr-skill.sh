#!/bin/sh
set +x
set -eu

LC_ALL=C
export LC_ALL
umask 077

repo=${BOTIFIED_RELEASES_REPO:-lzjever/botified-releases}
asset=botified-asr-skill.tar.gz
pointer_url=https://raw.githubusercontent.com/$repo/main/botified-asr-latest

log() {
	printf '%s\n' "$*"
}

fail() {
	printf 'botified ASR Skill install: %s\n' "$*" >&2
	exit 1
}

usage() {
	printf '%s\n' \
		'usage: install-asr-skill.sh --target codex|openclaw|botified' >&2
	exit 64
}

validate_version() {
	value=$1
	case "$value" in
		v*.*.*) ;;
		*) return 1 ;;
	esac
	major=${value#v}
	minor=${major#*.}
	patch=${minor#*.}
	major=${major%%.*}
	minor=${minor%%.*}
	[ "$value" = "v$major.$minor.$patch" ] || return 1
	for component in "$major" "$minor" "$patch"; do
		case "$component" in
			0 | [1-9] | [1-9][0-9]*) ;;
			*) return 1 ;;
		esac
		case "$component" in
			*[!0-9]*) return 1 ;;
		esac
	done
}

validate_port() {
	case "$1" in
		"" | *[!0-9]*) return 1 ;;
	esac
	[ "${#1}" -le 5 ] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

validate_client_config() {
	case "$client_base_url" in
		"" | *[[:space:]]* | *[[:cntrl:]]* | *"@"* | *"?"* | *"#"*)
			return 1
			;;
		http://* | https://*) ;;
		*) return 1 ;;
	esac

	case "$client_base_url" in
		*/) origin=${client_base_url%/} ;;
		*) origin=$client_base_url ;;
	esac
	authority=${origin#*://}
	case "$authority" in
		"" | */* | *"["* | *"]"* | *"{"* | *"}"*) return 1 ;;
	esac
	case "$authority" in
		*:*)
			origin_host=${authority%%:*}
			origin_port=${authority#*:}
			case "$origin_port" in
				*:*) return 1 ;;
			esac
			[ -n "$origin_host" ] || return 1
			validate_port "$origin_port" || return 1
			;;
	esac

	key_prefix=${client_api_key%%=*}
	key_padding=${client_api_key#"$key_prefix"}
	case "$key_prefix" in
		"" | *[!A-Za-z0-9._~+/-]*) return 1 ;;
	esac
	case "$key_padding" in
		*[!=]*) return 1 ;;
	esac
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
		output=$(sha256sum "$file") ||
			fail "could not checksum $asset"
	else
		output=$(shasum -a 256 "$file") ||
			fail "could not checksum $asset"
	fi
	digest=${output%% *}
	valid_digest "$digest" ||
		fail "checksum tool returned an invalid digest for $asset"
	printf '%s\n' "$digest"
}

verify_checksum() {
	manifest=$1
	file=$2
	target_name=$3
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
		if [ "$listed_name" = "$target_name" ]; then
			matches=$((matches + 1))
			expected=$listed_digest
		fi
	done < "$manifest"

	[ "$matches" -eq 1 ] ||
		fail "checksum for $target_name must appear exactly once"
	valid_digest "$expected" ||
		fail "invalid checksum for $target_name; expected 64 lowercase hex characters"
	verified_digest=$(file_digest "$file")
	[ "$verified_digest" = "$expected" ] ||
		fail "checksum mismatch for $target_name"
}

download() {
	url=$1
	out=$2
	if [ "$downloader" = curl ]; then
		curl -fL --retry 3 --retry-all-errors --connect-timeout 15 \
			--silent --show-error -o "$out" "$url"
	else
		wget -q --tries=4 --timeout=30 -O "$out" "$url"
	fi
}

[ "$#" -eq 2 ] && [ "$1" = --target ] || usage
target_kind=$2

case "${HOME:-}" in
	/*) ;;
	*) fail "HOME must be an absolute path" ;;
esac
case "$HOME" in
	*[[:cntrl:]]*) fail "HOME must not contain control characters" ;;
esac

case "$target_kind" in
	codex) target=$HOME/.codex/skills/botified-asr ;;
	openclaw) target=$HOME/.agents/skills/botified-asr ;;
	botified) target=$HOME/.local/share/botified/skills/botified-asr ;;
	*) usage ;;
esac

version_is_set=${BOTIFIED_ASR_VERSION+x}
if [ "$version_is_set" = x ]; then
	version=$BOTIFIED_ASR_VERSION
	unset BOTIFIED_ASR_VERSION
	validate_version "$version" ||
		fail "invalid version; expected canonical vMAJOR.MINOR.PATCH"
fi

base_url_is_set=${BOTIFIED_ASR_BASE_URL+x}
api_key_is_set=${BOTIFIED_ASR_API_KEY+x}
if [ "$base_url_is_set" != "$api_key_is_set" ]; then
	unset BOTIFIED_ASR_BASE_URL BOTIFIED_ASR_API_KEY 2>/dev/null || :
	fail "BOTIFIED_ASR_BASE_URL and BOTIFIED_ASR_API_KEY must be provided together"
fi

write_client_config=false
client_base_url=
client_api_key=
config_root=
if [ "$base_url_is_set" = x ]; then
	client_base_url=$BOTIFIED_ASR_BASE_URL
	client_api_key=$BOTIFIED_ASR_API_KEY
	unset BOTIFIED_ASR_BASE_URL BOTIFIED_ASR_API_KEY
	validate_client_config ||
		fail "invalid client configuration"
	write_client_config=true
	config_root=${XDG_CONFIG_HOME:-$HOME/.config}
	case "$config_root" in
		/*) ;;
		*) fail "XDG_CONFIG_HOME must be an absolute path" ;;
	esac
	case "$config_root" in
		*[[:cntrl:]]*) fail "XDG_CONFIG_HOME must not contain control characters" ;;
	esac
fi

command -v python3 >/dev/null 2>&1 || fail "python3 is required"
python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 6) else 1)' ||
	fail "python3 >=3.6 is required"
need_downloader
need_checksum

if ! python3 - "$target" "$write_client_config" "$config_root" <<'PY'
import os
import re
import stat
import sys
from pathlib import Path, PurePosixPath

target = Path(sys.argv[1])
write_config = sys.argv[2] == "true"
config_root = Path(sys.argv[3]) if write_config else None
versions_root = target.parent / ".botified-asr-versions"
managed_name = re.compile(
    r"asr-v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\."
    r"(?:0|[1-9][0-9]*)-[0-9a-f]{64}-.+"
)


def lexists(path: Path) -> bool:
    return os.path.lexists(path)


def managed_link(path: Path) -> bool:
    if not path.is_symlink():
        return False
    raw = os.readlink(path)
    parts = PurePosixPath(raw).parts
    return (
        not PurePosixPath(raw).is_absolute()
        and len(parts) == 3
        and parts[0] == ".botified-asr-versions"
        and managed_name.fullmatch(parts[1]) is not None
        and parts[2] == "botified-asr"
    )


if lexists(target) and not managed_link(target):
    raise SystemExit("target already exists and is not a managed symlink")
if lexists(versions_root):
    status = versions_root.lstat()
    if stat.S_ISLNK(status.st_mode) or not stat.S_ISDIR(status.st_mode):
        raise SystemExit("managed versions root is unsafe")

if write_config:
    config_dir = config_root / "botified-asr"
    config_file = config_dir / "client.env"
    for directory in (config_root, config_dir):
        if lexists(directory):
            status = directory.lstat()
            if stat.S_ISLNK(status.st_mode) or not stat.S_ISDIR(status.st_mode):
                raise SystemExit("client configuration directory is unsafe")
    if lexists(config_file):
        status = config_file.lstat()
        if stat.S_ISLNK(status.st_mode) or not stat.S_ISREG(status.st_mode):
            raise SystemExit("client.env is unsafe")
PY
then
	fail "unsafe installation path"
fi

tmpdir=$(mktemp -d 2>/dev/null || mktemp -d -t botified-asr-skill-install)
trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM

if [ "$version_is_set" != x ]; then
	download "$pointer_url" "$tmpdir/botified-asr-latest"
	if ! version=$(python3 - "$tmpdir/botified-asr-latest" <<'PY'
import sys
from pathlib import Path

contents = Path(sys.argv[1]).read_bytes()
if not contents.endswith(b"\n") or contents.endswith(b"\n\n"):
    raise SystemExit(1)
if contents.count(b"\n") != 1:
    raise SystemExit(1)
try:
    value = contents[:-1].decode("ascii")
except UnicodeDecodeError:
    raise SystemExit(1)
sys.stdout.write(value)
PY
	); then
		fail "invalid version pointer"
	fi
	validate_version "$version" ||
		fail "invalid version pointer"
fi

tag=asr-$version
base_url=https://github.com/$repo/releases/download/$tag

log "Installing Botified ASR Skill from $repo ($tag)"
log "Target: $target"

download "$base_url/$asset" "$tmpdir/$asset"
download "$base_url/SHA256SUMS" "$tmpdir/SHA256SUMS"
verify_checksum "$tmpdir/SHA256SUMS" "$tmpdir/$asset" "$asset"
log "Checksum verified."

python3 -c \
	'import pathlib, sys; pathlib.Path(sys.argv[1]).write_text(sys.stdin.read())' \
	"$tmpdir/install.py" <<'PY'
import os
import re
import shutil
import stat
import sys
import tarfile
import tempfile
from pathlib import Path, PurePosixPath

archive_path = Path(sys.argv[1])
digest = sys.argv[2]
tag = sys.argv[3]
target = Path(sys.argv[4])
write_config = sys.argv[5] == "true"
config_root = Path(sys.argv[6]) if write_config else None
expected = (
    ("botified-asr", tarfile.DIRTYPE, 0o755),
    ("botified-asr/SKILL.md", tarfile.REGTYPE, 0o644),
    ("botified-asr/agents", tarfile.DIRTYPE, 0o755),
    ("botified-asr/agents/openai.yaml", tarfile.REGTYPE, 0o644),
    ("botified-asr/references", tarfile.DIRTYPE, 0o755),
    ("botified-asr/references/api.md", tarfile.REGTYPE, 0o644),
    ("botified-asr/scripts", tarfile.DIRTYPE, 0o755),
    ("botified-asr/scripts/botified-asr", tarfile.REGTYPE, 0o755),
)
managed_name = re.compile(
    r"asr-v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\."
    r"(?:0|[1-9][0-9]*)-[0-9a-f]{64}-.+"
)


def lexists(path: Path) -> bool:
    return os.path.lexists(path)


def read_managed_link(path: Path):
    if not lexists(path):
        return None
    if not path.is_symlink():
        raise RuntimeError("target is no longer a managed symlink")
    raw = os.readlink(path)
    parsed = PurePosixPath(raw)
    parts = parsed.parts
    if (
        parsed.is_absolute()
        or len(parts) != 3
        or parts[0] != ".botified-asr-versions"
        or managed_name.fullmatch(parts[1]) is None
        or parts[2] != "botified-asr"
    ):
        raise RuntimeError("target is no longer a managed symlink")
    return raw


loaded = []
with tarfile.open(archive_path, "r:gz") as archive:
    members = archive.getmembers()
    if len(members) != len(expected):
        raise RuntimeError("unexpected archive member count")
    for member, (name, kind, mode) in zip(members, expected):
        path = PurePosixPath(member.name)
        if (
            member.name != name
            or path.is_absolute()
            or ".." in path.parts
            or member.type != kind
            or member.mode != mode
        ):
            raise RuntimeError("unexpected archive member")
        if kind == tarfile.DIRTYPE:
            loaded.append((name, kind, mode, None))
        else:
            source = archive.extractfile(member)
            if source is None:
                raise RuntimeError("archive member has no contents")
            loaded.append((name, kind, mode, source.read()))

target_parent = target.parent
target_parent.mkdir(parents=True, exist_ok=True)
versions_root = target_parent / ".botified-asr-versions"
if lexists(versions_root):
    status = versions_root.lstat()
    if stat.S_ISLNK(status.st_mode) or not stat.S_ISDIR(status.st_mode):
        raise RuntimeError("managed versions root is unsafe")
else:
    versions_root.mkdir(mode=0o700)

old_link = read_managed_link(target)
version_dir = Path(
    tempfile.mkdtemp(prefix=f"{tag}-{digest}-", dir=versions_root)
)
temporary_link = None
switched = False

try:
    for name, kind, mode, contents in loaded:
        destination = version_dir / name
        if kind == tarfile.DIRTYPE:
            destination.mkdir(mode=mode)
            os.chmod(destination, mode)
        else:
            descriptor = os.open(
                destination,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                mode,
            )
            with os.fdopen(descriptor, "wb") as output:
                output.write(contents)
                output.flush()
                os.fsync(output.fileno())
            os.chmod(destination, mode)

    installed_root = version_dir / "botified-asr"
    relative_target = os.path.relpath(installed_root, target_parent)
    link_descriptor, link_name = tempfile.mkstemp(
        prefix=".botified-asr-link-",
        dir=target_parent,
    )
    os.close(link_descriptor)
    os.unlink(link_name)
    temporary_link = Path(link_name)
    os.symlink(relative_target, temporary_link)
    os.replace(temporary_link, target)
    temporary_link = None
    switched = True

    if write_config:
        secret_input = sys.stdin.buffer.read()
        parts = secret_input.split(b"\n")
        if len(parts) != 3 or parts[2] != b"":
            raise RuntimeError("invalid private configuration input")
        base_url, api_key = parts[:2]
        config_dir = config_root / "botified-asr"
        config_file = config_dir / "client.env"
        if lexists(config_root):
            status = config_root.lstat()
            if stat.S_ISLNK(status.st_mode) or not stat.S_ISDIR(status.st_mode):
                raise RuntimeError("client configuration root is unsafe")
        else:
            config_root.mkdir(parents=True, mode=0o700)
        if lexists(config_dir):
            status = config_dir.lstat()
            if stat.S_ISLNK(status.st_mode) or not stat.S_ISDIR(status.st_mode):
                raise RuntimeError("client configuration directory is unsafe")
        else:
            config_dir.mkdir(mode=0o700)
        os.chmod(config_dir, 0o700)
        if lexists(config_file):
            status = config_file.lstat()
            if stat.S_ISLNK(status.st_mode) or not stat.S_ISREG(status.st_mode):
                raise RuntimeError("client.env is unsafe")

        descriptor, config_name = tempfile.mkstemp(
            prefix=".client.env.",
            dir=config_dir,
        )
        temporary_config = Path(config_name)
        try:
            os.fchmod(descriptor, 0o600)
            with os.fdopen(descriptor, "wb") as output:
                output.write(b"BOTIFIED_ASR_BASE_URL=" + base_url + b"\n")
                output.write(b"BOTIFIED_ASR_API_KEY=" + api_key + b"\n")
                output.flush()
                os.fsync(output.fileno())
            if lexists(config_file) and config_file.is_symlink():
                raise RuntimeError("client.env became unsafe")
            os.replace(temporary_config, config_file)
        except BaseException:
            try:
                temporary_config.unlink()
            except FileNotFoundError:
                pass
            raise

except BaseException:
    if temporary_link is not None:
        try:
            temporary_link.unlink()
        except FileNotFoundError:
            pass
    if switched:
        if old_link is None:
            if target.is_symlink() and os.readlink(target) == relative_target:
                target.unlink()
        else:
            restore_descriptor, restore_name = tempfile.mkstemp(
                prefix=".botified-asr-restore-",
                dir=target_parent,
            )
            os.close(restore_descriptor)
            os.unlink(restore_name)
            restore_link = Path(restore_name)
            try:
                os.symlink(old_link, restore_link)
                os.replace(restore_link, target)
            finally:
                try:
                    restore_link.unlink()
                except FileNotFoundError:
                    pass
    shutil.rmtree(version_dir, ignore_errors=True)
    raise

for old_version in versions_root.iterdir():
    if old_version == version_dir:
        continue
    if (
        old_version.is_dir()
        and not old_version.is_symlink()
        and managed_name.fullmatch(old_version.name) is not None
    ):
        try:
            shutil.rmtree(old_version)
        except OSError as error:
            print(
                f"warning: could not remove old managed version "
                f"{old_version}: {error}",
                file=sys.stderr,
            )
PY

install_skill() {
	python3 "$tmpdir/install.py" \
		"$tmpdir/$asset" \
		"$verified_digest" \
		"$tag" \
		"$target" \
		"$write_client_config" \
		"$config_root"
}

if [ "$write_client_config" = true ]; then
	if ! printf '%s\n%s\n' "$client_base_url" "$client_api_key" |
		install_skill
	then
		fail "invalid Skill archive or installation failed"
	fi
else
	if ! install_skill </dev/null; then
		fail "invalid Skill archive or installation failed"
	fi
fi

log "Installed Botified ASR Skill: $target"
