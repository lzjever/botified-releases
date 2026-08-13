#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
fixture_dir=${1:-${BOTIFIED_INSTALLER_FIXTURES:-}}
version=v9.8.7
asr_version=v1.2.3
default_asr_version=v4.5.6
asr_asset=botified-asr-skill.tar.gz
generated_fixtures=false

pass_count=0

say_ok() {
	pass_count=$((pass_count + 1))
	printf 'ok %d - %s\n' "$pass_count" "$1"
}

die() {
	printf 'installers test: %s\n' "$*" >&2
	exit 1
}

host_command() {
	command -v "$1" 2>/dev/null || die "$1 is required to run installer tests"
}

host_sh=$(host_command sh)
host_tar=$(host_command tar)
host_python=$(host_command python3)
host_readlink=$(host_command readlink)
host_realpath=$(host_command realpath)
host_stat=$(host_command stat)
host_hash=
host_hash_kind=
if command -v sha256sum >/dev/null 2>&1; then
	host_hash=$(command -v sha256sum)
	host_hash_kind=sha256sum
elif command -v shasum >/dev/null 2>&1; then
	host_hash=$(command -v shasum)
	host_hash_kind=shasum
else
	die "sha256sum or shasum is required to prepare installer fixtures"
fi

tmp_root=$(mktemp -d 2>/dev/null || mktemp -d -t botified-installers-test)
trap 'rm -rf "$tmp_root"' EXIT HUP INT TERM

digest_file() {
	if [ "$host_hash_kind" = sha256sum ]; then
		result=$($host_hash "$1")
	else
		result=$($host_hash -a 256 "$1")
	fi
	printf '%s\n' "${result%% *}"
}

write_checksums() {
	dir=$1
	: > "$dir/SHA256SUMS"
	for asset in \
		botified-asr-skill.tar.gz \
		botified-claw-gateway-companion.tar.gz \
		botified-core-linux-aarch64-gnu.tar.gz \
		botified-core-linux-x86_64-musl.tar.gz \
		botified-playground.tar.gz
	do
		printf '%s  %s\n' "$(digest_file "$dir/$asset")" "$asset" >> "$dir/SHA256SUMS"
	done
}

make_generated_fixtures() {
	dir=$1
	stage="$tmp_root/stage"
	mkdir -p "$dir" \
		"$stage/core/bin" \
		"$stage/core/share/botified/skills/botified-agent-guide" \
		"$stage/core/share/botified/skills/botified-skill-creator" \
		"$stage/core/share/botified/systemd" \
		"$stage/core/share/doc/botified" \
		"$stage/gateway/bin" \
		"$stage/gateway/share/botified/gateway/dist/src" \
		"$stage/gateway/share/doc/botified-claw-gateway" \
		"$stage/gateway/share/botified-claw-gateway/examples" \
		"$stage/playground/bin" \
		"$stage/playground/share/botified/skills/robot-playground" \
		"$stage/asr-skill/botified-asr/agents" \
		"$stage/asr-skill/botified-asr/references" \
		"$stage/asr-skill/botified-asr/scripts"

	cat > "$stage/core/bin/botified" <<'EOF'
#!/bin/sh
# fixture core release v9.8.7
set -eu
printf 'core %s :: %s\n' "$0" "$*" >> "${SHIM_ACTION_LOG:?}"

command_name=${1:-}
subcommand=${2:-}
mapped_path() {
	printf '%s%s\n' "${SHIM_TEST_ROOT:-}" "$1"
}
case "$command_name:$subcommand" in
	setup:--help|config:--help|health:--help) exit 0 ;;
	setup:--neutral)
		[ "${SHIM_SETUP_FAIL:-false}" != true ] || exit 31
		shift 2
		config=
		workspace=
		while [ "$#" -gt 0 ]; do
			case "$1" in
				--config) config=${2:-}; shift 2 ;;
				--workspace) workspace=${2:-}; shift 2 ;;
				*) exit 64 ;;
			esac
		done
		mapped_config=$(mapped_path "$config")
		mapped_workspace=$(mapped_path "$workspace")
		[ -n "$config" ] && [ -d "$mapped_workspace" ] && [ ! -e "$mapped_config" ] || exit 32
		printf 'providers: []\nruntime:\n  cwd: %s\n' "$workspace" > "$mapped_config"
		;;
	config:check)
		[ "${SHIM_CONFIG_CHECK_FAIL:-false}" != true ] || exit 33
		[ "${3:-}" = --config ] && [ -s "$(mapped_path "${4:-}")" ] || exit 64
		;;
	health:check)
		[ "${3:-}" = --config ] && [ -s "$(mapped_path "${4:-}")" ] || exit 64
		if [ "${7:-}" = --help ]; then
			[ "${5:-}" = --expected-pid ] && [ "${6:-}" = 1 ] && [ "$#" -eq 7 ] || exit 64
		else
			[ "${5:-}" = --expected-pid ] &&
				[ "${6:-}" = "$SHIM_MAIN_PID" ] && [ "$#" -eq 6 ] || exit 64
			[ "$SHIM_HEALTH_PROCESS_ID" = "${6:-}" ] || exit 34
		fi
		printf 'healthy\n'
		;;
	--version:) printf '9.8.7\n' ;;
	*) exit 64 ;;
esac
EOF
	printf '#!/bin/sh\nexit 0\n' > "$stage/core/bin/botified-tui"
	chmod 0755 "$stage/core/bin/botified" "$stage/core/bin/botified-tui"
	printf 'fixture agent guide\n' > "$stage/core/share/botified/skills/botified-agent-guide/SKILL.md"
	printf 'fixture skill creator\n' > "$stage/core/share/botified/skills/botified-skill-creator/SKILL.md"
	printf 'fixture docs\n' > "$stage/core/share/doc/botified/README.md"
	cat > "$stage/core/share/botified/systemd/botified.user.service" <<'EOF'
# Managed by the Botified installer. Inspect and operate with systemd tools.
[Unit]
Description=Botified Core user fixture
EOF
	cat > "$stage/core/share/botified/systemd/botified.system.service" <<'EOF'
# Managed by the Botified installer. Inspect and operate with systemd tools.
[Unit]
Description=Botified Core system fixture
EOF

	printf '#!/bin/sh\n[ "${1:-}" = self-check ]\n' > "$stage/gateway/bin/botified-claw-gateway"
	chmod 0755 "$stage/gateway/bin/botified-claw-gateway"
	printf 'fixture gateway\n' > "$stage/gateway/share/botified/gateway/dist/src/cli.js"
	printf 'fixture gateway docs\n' > "$stage/gateway/share/doc/botified-claw-gateway/README.md"
	printf 'fixture gateway example\n' > "$stage/gateway/share/botified-claw-gateway/examples/botified-claw-gateway.yaml"

	printf '#!/bin/sh\n[ "${1:-}" = self-check ]\n' > "$stage/playground/bin/botified-playground"
	chmod 0755 "$stage/playground/bin/botified-playground"
	printf 'fixture playground skill\n' > "$stage/playground/share/botified/skills/robot-playground/SKILL.md"

	printf 'fixture asr skill\n' > "$stage/asr-skill/botified-asr/SKILL.md"
	printf 'fixture asr metadata\n' > "$stage/asr-skill/botified-asr/agents/openai.yaml"
	printf 'fixture asr reference\n' > "$stage/asr-skill/botified-asr/references/api.md"
	printf '#!/bin/sh\nexit 0\n' > "$stage/asr-skill/botified-asr/scripts/botified-asr"
	chmod 0755 "$stage/asr-skill/botified-asr/scripts/botified-asr"

	$host_tar -C "$stage/core" -czf "$dir/botified-core-linux-x86_64-musl.tar.gz" .
	cp "$dir/botified-core-linux-x86_64-musl.tar.gz" "$dir/botified-core-linux-aarch64-gnu.tar.gz"
	$host_tar -C "$stage/gateway" -czf "$dir/botified-claw-gateway-companion.tar.gz" .
	$host_tar -C "$stage/playground" -czf "$dir/botified-playground.tar.gz" .
	$host_python - "$stage/asr-skill" "$dir/$asr_asset" <<'PY'
import sys
import tarfile
from pathlib import Path

source = Path(sys.argv[1])
members = (
    ("botified-asr", 0o755),
    ("botified-asr/SKILL.md", 0o644),
    ("botified-asr/agents", 0o755),
    ("botified-asr/agents/openai.yaml", 0o644),
    ("botified-asr/references", 0o755),
    ("botified-asr/references/api.md", 0o644),
    ("botified-asr/scripts", 0o755),
    ("botified-asr/scripts/botified-asr", 0o755),
)
with tarfile.open(sys.argv[2], "w:gz") as archive:
    for name, mode in members:
        archive.add(
            source / name,
            arcname=name,
            recursive=False,
            filter=lambda info, mode=mode: (
                setattr(info, "mode", mode) or info
            ),
        )
PY
	write_checksums "$dir"
}

if [ -z "$fixture_dir" ]; then
	fixture_dir="$tmp_root/fixtures"
	make_generated_fixtures "$fixture_dir"
	generated_fixtures=true
else
	case "$fixture_dir" in
		/*) ;;
		*) fixture_dir=$(CDPATH= cd -- "$fixture_dir" && pwd) ;;
	esac
fi

for required in \
	botified-asr-skill.tar.gz \
	botified-core-linux-x86_64-musl.tar.gz \
	botified-core-linux-aarch64-gnu.tar.gz \
	botified-claw-gateway-companion.tar.gz \
	botified-playground.tar.gz \
	SHA256SUMS
do
	[ -f "$fixture_dir/$required" ] || die "fixture is missing $required"
done

base_bin="$tmp_root/base-bin"
shim_src="$tmp_root/shim-src"
mkdir -p "$base_bin" "$shim_src"

for command_name in sh env uname mktemp rm mkdir mv tar gzip install cp chmod dirname grep touch cat; do
	command_path=$(host_command "$command_name")
	ln -s "$command_path" "$base_bin/$command_name"
done

cat > "$shim_src/uname" <<'EOF'
#!/bin/sh
case "${1:-}" in
	-s) printf '%s\n' "$SHIM_OS" ;;
	-m) printf '%s\n' "$SHIM_ARCH" ;;
	*) exit 2 ;;
esac
EOF

cat > "$shim_src/download" <<'EOF'
#!/bin/sh
set -eu

tool=${0##*/}
case "$tool" in
	curl)
		[ "$#" -eq 11 ] &&
			[ "$1" = -fL ] &&
			[ "$2" = --retry ] &&
			[ "$3" = 3 ] &&
			[ "$4" = --retry-all-errors ] &&
			[ "$5" = --connect-timeout ] &&
			[ "$6" = 15 ] &&
			[ "$7" = --silent ] &&
			[ "$8" = --show-error ] &&
			[ "$9" = -o ] || exit 90
		out=${10}
		url=${11}
		;;
	wget)
		[ "$#" -eq 6 ] &&
			[ "$1" = -q ] &&
			[ "$2" = --tries=4 ] &&
			[ "$3" = --timeout=30 ] &&
			[ "$4" = -O ] || exit 91
		out=$5
		url=$6
		;;
	*) exit 92 ;;
esac

printf '%s %s\n' "$tool" "$url" >> "$SHIM_DOWNLOAD_LOG"
if [ "$url" = "https://raw.githubusercontent.com/lzjever/botified-releases/main/botified-asr-latest" ]; then
	case "${SHIM_POINTER_MODE:-valid}" in
		valid) printf '%s\n' "$SHIM_DEFAULT_ASR_VERSION" > "$out" ;;
		invalid-version) printf 'v1.02.3\n' > "$out" ;;
		missing-newline) printf '%s' "$SHIM_DEFAULT_ASR_VERSION" > "$out" ;;
		double-newline) printf '%s\n\n' "$SHIM_DEFAULT_ASR_VERSION" > "$out" ;;
		*) exit 97 ;;
	esac
else
	prefix="https://github.com/lzjever/botified-releases/releases/download/$SHIM_VERSION"
	case "$url" in
		"$prefix"/*) asset=${url#"$prefix"/} ;;
		*) printf 'unexpected download URL: %s\n' "$url" >&2; exit 93 ;;
	esac
	case "$asset" in
		*/*|'') printf 'unexpected asset URL: %s\n' "$url" >&2; exit 94 ;;
	esac
	if [ "${SHIM_HTTP_404_ASSET:-}" = "$asset" ]; then
		exit 22
	fi
	cp "$SHIM_FIXTURE_DIR/$asset" "$out"
fi
EOF

cat > "$shim_src/sha256sum" <<'EOF'
#!/bin/sh
set -eu
[ "$#" -eq 1 ] || exit 95
printf 'sha256sum\n' >> "$SHIM_CHECKSUM_LOG"
if [ "$SHIM_REAL_HASH_KIND" = sha256sum ]; then
	result=$($SHIM_REAL_HASH "$1")
else
	result=$($SHIM_REAL_HASH -a 256 "$1")
fi
printf '%s  %s\n' "${result%% *}" "$1"
EOF

cat > "$shim_src/shasum" <<'EOF'
#!/bin/sh
set -eu
[ "$#" -eq 3 ] && [ "$1" = -a ] && [ "$2" = 256 ] || exit 96
shift 2
printf 'shasum\n' >> "$SHIM_CHECKSUM_LOG"
if [ "$SHIM_REAL_HASH_KIND" = sha256sum ]; then
	result=$($SHIM_REAL_HASH "$1")
else
	result=$($SHIM_REAL_HASH -a 256 "$1")
fi
printf '%s  %s\n' "${result%% *}" "$1"
EOF

cat > "$shim_src/node" <<'EOF'
#!/bin/sh
case "${1:-}" in
	-p) printf '22.19.0\n' ;;
	*) exit 0 ;;
esac
EOF

cat > "$shim_src/python3" <<'EOF'
#!/bin/sh
exec "$SHIM_REAL_PYTHON" "$@"
EOF

cat > "$shim_src/id" <<'EOF'
#!/bin/sh
set -eu
case "${1:-}" in
	-u)
		if [ "$#" -eq 1 ]; then printf '%s\n' "$SHIM_UID"; else printf '%s\n' "$SHIM_BOTIFIED_UID"; fi
		;;
	-g)
		if [ "$#" -eq 1 ]; then printf '%s\n' "$SHIM_GID"; else printf '%s\n' "$SHIM_BOTIFIED_GID"; fi
		;;
	botified)
		[ "${SHIM_SYSTEM_ACCOUNT:-present}" = present ] || [ -s "$SHIM_ACCOUNT_STATE" ] || exit 1
		printf 'uid=%s(botified) gid=%s(botified) groups=%s(botified)\n' \
			"$SHIM_BOTIFIED_UID" "$SHIM_BOTIFIED_GID" "$SHIM_BOTIFIED_GID"
		;;
	'') printf '%s\n' "$SHIM_UID" ;;
	*) exit 1 ;;
esac
EOF

cat > "$shim_src/getent" <<'EOF'
#!/bin/sh
set -eu
database=${1:-}
key=${2:-}
case "$database:$key" in
	passwd:"$SHIM_UID"|passwd:"$SHIM_USERNAME")
		printf '%s:x:%s:%s::%s:/bin/sh\n' "$SHIM_USERNAME" "$SHIM_UID" "$SHIM_GID" "$SHIM_NSS_HOME"
		;;
	passwd:botified)
		case "${SHIM_SYSTEM_ACCOUNT:-present}" in
			present) printf 'botified:x:%s:%s::/var/lib/botified:/usr/sbin/nologin\n' "$SHIM_BOTIFIED_UID" "$SHIM_BOTIFIED_GID" ;;
			conflict) printf 'botified:x:0:0::/root:/bin/sh\n' ;;
			absent) [ -s "$SHIM_ACCOUNT_STATE" ] || exit 2; printf 'botified:x:%s:%s::/var/lib/botified:/usr/sbin/nologin\n' "$SHIM_BOTIFIED_UID" "$SHIM_BOTIFIED_GID" ;;
			*) exit 2 ;;
		esac
		;;
	group:botified)
		case "${SHIM_SYSTEM_ACCOUNT:-present}" in
			present) printf 'botified:x:%s:\n' "$SHIM_BOTIFIED_GID" ;;
			conflict) printf 'botified:x:0:\n' ;;
			absent) [ -s "$SHIM_ACCOUNT_STATE" ] || exit 2; printf 'botified:x:%s:\n' "$SHIM_BOTIFIED_GID" ;;
			*) exit 2 ;;
		esac
		;;
	*) exit 2 ;;
esac
EOF

cat > "$shim_src/loginctl" <<'EOF'
#!/bin/sh
set -eu
printf 'loginctl %s\n' "$*" >> "$SHIM_ACTION_LOG"
case " $* " in
	*' enable-linger '*) exit 91 ;;
	*' show-user '*) printf '%s\n' "${SHIM_LINGER:-yes}" ;;
	*) exit 64 ;;
esac
EOF

cat > "$shim_src/systemctl" <<'EOF'
#!/bin/sh
set -eu
scope=system
if [ "${1:-}" = --user ]; then
	scope=user
	shift
fi
command_name=${1:-}
shift || :
printf 'systemctl %s %s%s\n' "$scope" "$command_name" "${*:+ $*}" >> "$SHIM_ACTION_LOG"
case "$command_name" in
	--version) exit 0 ;;
	show-environment)
		[ "${SHIM_MANAGER_AVAILABLE:-true}" = true ] || exit 92
		;;
	daemon-reload)
		[ -x "$SHIM_EXPECTED_BINARY_FS" ] || exit 71
		[ -f "$SHIM_EXPECTED_UNIT_FS" ] || exit 72
		grep -F "$SHIM_EXPECTED_RELEASE_MARKER" "$SHIM_EXPECTED_BINARY_FS" >/dev/null || exit 73
		grep -F '# Managed by the Botified installer. Inspect and operate with systemd tools.' \
			"$SHIM_EXPECTED_UNIT_FS" >/dev/null || exit 74
		;;
	enable|restart) ;;
	is-enabled) printf '%s\n' "${SHIM_ENABLED_OUTPUT:-enabled}" ;;
	is-active) printf '%s\n' "${SHIM_ACTIVE_OUTPUT:-active}" ;;
	show)
		if [ "$*" = '--property=Version --value' ]; then
			[ "${SHIM_MANAGER_AVAILABLE:-true}" = true ] || exit 92
			printf '252\n'
			exit 0
		fi
		count=0
		[ ! -s "$SHIM_PID_COUNT" ] || count=$(cat "$SHIM_PID_COUNT")
		count=$((count + 1))
		printf '%s\n' "$count" > "$SHIM_PID_COUNT"
		case "${SHIM_PID_MODE:-stable}:$count" in
			zero:*) printf '0\n' ;;
			changes:1) printf '%s\n' "$SHIM_MAIN_PID" ;;
			changes:*) printf '%s\n' "$SHIM_CHANGED_PID" ;;
			*) printf '%s\n' "$SHIM_MAIN_PID" ;;
		esac
		;;
	*) exit 64 ;;
esac
EOF

cat > "$shim_src/useradd" <<'EOF'
#!/bin/sh
set -eu
printf 'useradd %s\n' "$*" >> "$SHIM_ACTION_LOG"
[ "$*" = '-r -U -d /var/lib/botified -m -s /usr/sbin/nologin botified' ] || exit 64
: > "$SHIM_ACCOUNT_STATE"
EOF

cat > "$shim_src/canonical-path" <<'EOF'
#!/bin/sh
set -eu
tool=${0##*/}
last=
for argument in "$@"; do last=$argument; done
case "$last" in
	/proc/*/exe)
		printf '%s proc %s\n' "$tool" "$last" >> "$SHIM_ACTION_LOG"
		printf '%s\n' "$SHIM_PROC_EXE"
		;;
	*)
		if [ "$tool" = realpath ]; then exec "$SHIM_REAL_REALPATH" "$@"; fi
		exec "$SHIM_REAL_READLINK" "$@"
		;;
esac
EOF

cat > "$shim_src/stat" <<'EOF'
#!/bin/sh
set -eu
case " $* " in
	*' /proc/'*)
		printf 'stat proc %s\n' "$*" >> "$SHIM_ACTION_LOG"
		case " $* " in
			*' %u:%g '*) printf '%s:%s\n' "$SHIM_PROC_UID" "$SHIM_PROC_GID" ;;
			*' %u '*) printf '%s\n' "$SHIM_PROC_UID" ;;
			*' %g '*) printf '%s\n' "$SHIM_PROC_GID" ;;
			*) exit 64 ;;
		esac
		;;
	*) exec "$SHIM_REAL_STAT" "$@" ;;
esac
EOF

cat > "$shim_src/chown" <<'EOF'
#!/bin/sh
set -eu
printf 'chown %s\n' "$*" >> "$SHIM_ACTION_LOG"
exit 0
EOF

chmod 0755 "$shim_src"/*
rm "$base_bin/uname"
ln -s "$shim_src/uname" "$base_bin/uname"
ln -s "$shim_src/node" "$base_bin/node"
ln -s "$shim_src/python3" "$base_bin/python3"

make_case_bin() {
	case_bin=$1
	downloader=$2
	checksum_tool=$3
	mkdir -p "$case_bin"
	ln -s "$shim_src/download" "$case_bin/$downloader"
	case "$checksum_tool" in
		sha256sum|shasum) ln -s "$shim_src/$checksum_tool" "$case_bin/$checksum_tool" ;;
		both)
			ln -s "$shim_src/sha256sum" "$case_bin/sha256sum"
			ln -s "$shim_src/shasum" "$case_bin/shasum"
			;;
		none) ;;
		*) die "unknown checksum tool $checksum_tool" ;;
	esac
}

make_scoped_case_bin() {
	case_bin=$1
	make_case_bin "$case_bin" curl sha256sum
	for name in id getent loginctl systemctl useradd stat chown; do
		ln -s "$shim_src/$name" "$case_bin/$name"
	done
	ln -s "$shim_src/canonical-path" "$case_bin/readlink"
	ln -s "$shim_src/canonical-path" "$case_bin/realpath"
}

assert_contains() {
	contains_file=$1
	contains_text=$2
	contains_label=$3
	if ! grep -F "$contains_text" "$contains_file" >/dev/null 2>&1; then
		printf 'not ok - %s: output does not contain: %s\n' "$contains_label" "$contains_text" >&2
		sed -n '1,160p' "$contains_file" >&2
		exit 1
	fi
}

expected_asset() {
	script=$1
	os=$2
	arch=$3
	case "$script" in
		install-gateway.sh) printf '%s\n' botified-claw-gateway-companion.tar.gz ;;
		install-playground.sh) printf '%s\n' botified-playground.tar.gz ;;
		install.sh)
			case "$os:$arch" in
				Linux:x86_64) printf '%s\n' botified-core-linux-x86_64-musl.tar.gz ;;
				Linux:aarch64) printf '%s\n' botified-core-linux-aarch64-gnu.tar.gz ;;
				*) die "unexpected test platform $os:$arch" ;;
			esac
			;;
		*) die "unknown installer $script" ;;
	esac
}

run_case() {
	case_name=$1
	script=$2
	os=$3
	arch=$4
	downloader=$5
	checksum_tool=$6
	case_fixture=$7
	expected_status=$8
	expected_message=$9
	expected_checksum=${10:-auto}
	existing_gateway=${11:-false}

	case_root="$tmp_root/cases/$pass_count-$case_name"
	case_bin="$case_root/bin"
	home="$case_root/home"
	prefix="$case_root/prefix"
	output="$case_root/output"
	download_log="$case_root/downloads"
	checksum_log="$case_root/checksums"
	mkdir -p "$case_root" "$home"
	: > "$download_log"
	: > "$checksum_log"
	make_case_bin "$case_bin" "$downloader" "$checksum_tool"
	asset=$(expected_asset "$script" "$os" "$arch")
	if [ "$expected_status" = success ] && [ "$script" = install-gateway.sh ]; then
		mkdir -p \
			"$prefix/share/botified/gateway" \
			"$prefix/share/doc/botified-claw-gateway" \
			"$prefix/share/botified-claw-gateway/examples"
		printf 'stale\n' > "$prefix/share/botified/gateway/removed-runtime-file"
		printf 'stale\n' > "$prefix/share/doc/botified-claw-gateway/removed-doc-file"
		printf 'stale\n' > "$prefix/share/botified-claw-gateway/examples/removed-example-file"
	fi
	if [ "$existing_gateway" = true ]; then
		mkdir -p "$prefix/bin"
		printf '#!/bin/sh\nexit 0\n' > "$prefix/bin/botified-claw-gateway"
		chmod 0755 "$prefix/bin/botified-claw-gateway"
	fi

	set +e
	PATH="$case_bin:$base_bin" \
	HOME="$home" \
	SHIM_OS="$os" \
	SHIM_ARCH="$arch" \
	SHIM_VERSION="$version" \
	SHIM_FIXTURE_DIR="$case_fixture" \
	SHIM_DOWNLOAD_LOG="$download_log" \
	SHIM_CHECKSUM_LOG="$checksum_log" \
	SHIM_REAL_HASH="$host_hash" \
	SHIM_REAL_HASH_KIND="$host_hash_kind" \
	SHIM_REAL_PYTHON="$host_python" \
	SHIM_HTTP_404_ASSET="${HTTP_404_ASSET:-}" \
	BOTIFIED_VERSION="$version" \
	BOTIFIED_INSTALL_DIR="$prefix/bin" \
	BOTIFIED_SHARE_DIR="$prefix/share/botified" \
	BOTIFIED_DOC_DIR="$prefix/share/doc/botified" \
	BOTIFIED_PREFIX="$prefix" \
	"$host_sh" "$repo_root/$script" > "$output" 2>&1
	status=$?
	set -e

	if [ "$expected_status" = success ]; then
		[ "$status" -eq 0 ] || {
			printf 'not ok - %s: expected success, got %s\n' "$case_name" "$status" >&2
			sed -n '1,160p' "$output" >&2
			exit 1
		}
		assert_contains "$output" "Checksum verified." "$case_name"
		case "$script" in
			install.sh)
				[ -x "$prefix/bin/botified" ] || die "$case_name did not install botified"
				[ -x "$prefix/bin/botified-tui" ] || die "$case_name did not install botified-tui"
				[ -d "$prefix/share/botified/skills" ] || die "$case_name did not install skills"
				[ -d "$prefix/share/doc/botified" ] || die "$case_name did not install docs"
				if [ "$existing_gateway" = true ]; then
					assert_contains "$output" \
						"botified-claw-gateway is installed but was not upgraded; run install-gateway.sh with BOTIFIED_VERSION=$version" \
						"$case_name"
				fi
				;;
			install-gateway.sh)
				[ -x "$prefix/bin/botified-claw-gateway" ] || die "$case_name did not install gateway"
				[ -s "$prefix/share/botified/gateway/dist/src/cli.js" ] ||
					die "$case_name did not install gateway runtime"
				[ -s "$prefix/share/doc/botified-claw-gateway/README.md" ] ||
					die "$case_name did not install gateway docs"
				[ -s "$prefix/share/botified-claw-gateway/examples/botified-claw-gateway.yaml" ] ||
					die "$case_name did not install gateway example"
				if [ "$generated_fixtures" = true ]; then
					assert_contains "$prefix/share/botified/gateway/dist/src/cli.js" "fixture gateway" "$case_name"
					assert_contains "$prefix/share/doc/botified-claw-gateway/README.md" "fixture gateway docs" "$case_name"
					assert_contains "$prefix/share/botified-claw-gateway/examples/botified-claw-gateway.yaml" "fixture gateway example" "$case_name"
				fi
				"$prefix/bin/botified-claw-gateway" self-check ||
					die "$case_name installed gateway failed self-check"
				[ ! -e "$prefix/share/botified/gateway/removed-runtime-file" ] ||
					die "$case_name retained stale runtime files"
				[ ! -e "$prefix/share/doc/botified-claw-gateway/removed-doc-file" ] ||
					die "$case_name retained stale docs"
				[ ! -e "$prefix/share/botified-claw-gateway/examples/removed-example-file" ] ||
					die "$case_name retained stale examples"
				;;
			install-playground.sh) [ -x "$prefix/bin/botified-playground" ] || die "$case_name did not install playground" ;;
		esac
	else
		[ "$status" -ne 0 ] || {
			printf 'not ok - %s: expected failure\n' "$case_name" >&2
			sed -n '1,160p' "$output" >&2
			exit 1
		}
		assert_contains "$output" "$expected_message" "$case_name"
		case "$script" in
			install.sh) [ ! -e "$prefix/bin/botified" ] || die "$case_name installed before validation completed" ;;
			install-gateway.sh) [ ! -e "$prefix/bin/botified-claw-gateway" ] || die "$case_name installed before validation completed" ;;
			install-playground.sh) [ ! -e "$prefix/bin/botified-playground" ] || die "$case_name installed before validation completed" ;;
		esac
	fi

	assert_contains "$download_log" "$downloader https://github.com/lzjever/botified-releases/releases/download/$version/$asset" "$case_name"
	if [ "${HTTP_404_ASSET:-}" != "$asset" ]; then
		assert_contains "$download_log" "$downloader https://github.com/lzjever/botified-releases/releases/download/$version/SHA256SUMS" "$case_name"
	fi
	if [ "$expected_status" = success ]; then
		case "$checksum_tool" in
			sha256sum) assert_contains "$checksum_log" sha256sum "$case_name" ;;
			shasum) assert_contains "$checksum_log" shasum "$case_name" ;;
			both)
				assert_contains "$checksum_log" sha256sum "$case_name"
				[ "$(wc -l < "$checksum_log")" -eq 1 ] || die "$case_name did not prefer sha256sum"
				;;
			none) die "$case_name cannot succeed without a checksum tool" ;;
		esac
	elif [ "$checksum_tool" = none ]; then
		[ ! -s "$checksum_log" ] || die "$case_name unexpectedly ran a checksum tool"
	fi
	if [ "$expected_checksum" = not-called ]; then
		[ ! -s "$checksum_log" ] || die "$case_name ran a checksum tool before rejecting the manifest digest"
	fi
	HTTP_404_ASSET=
	say_ok "$case_name"
}

run_unsupported_core_case() {
	case_name=$1
	os=$2
	arch=$3

	case_root="$tmp_root/cases/$pass_count-$case_name"
	case_bin="$case_root/bin"
	home="$case_root/home"
	prefix="$case_root/prefix"
	output="$case_root/output"
	download_log="$case_root/downloads"
	checksum_log="$case_root/checksums"
	mkdir -p "$case_root" "$home"
	: > "$download_log"
	: > "$checksum_log"
	make_case_bin "$case_bin" curl both

	set +e
	PATH="$case_bin:$base_bin" \
	HOME="$home" \
	SHIM_OS="$os" \
	SHIM_ARCH="$arch" \
	SHIM_VERSION="$version" \
	SHIM_FIXTURE_DIR="$fixture_dir" \
	SHIM_DOWNLOAD_LOG="$download_log" \
	SHIM_CHECKSUM_LOG="$checksum_log" \
	SHIM_REAL_HASH="$host_hash" \
	SHIM_REAL_HASH_KIND="$host_hash_kind" \
	SHIM_REAL_PYTHON="$host_python" \
	BOTIFIED_VERSION="$version" \
	BOTIFIED_INSTALL_DIR="$prefix/bin" \
	BOTIFIED_SHARE_DIR="$prefix/share/botified" \
	BOTIFIED_DOC_DIR="$prefix/share/doc/botified" \
	"$host_sh" "$repo_root/install.sh" > "$output" 2>&1
	status=$?
	set -e

	[ "$status" -ne 0 ] || die "$case_name unexpectedly succeeded"
	assert_contains "$output" "unsupported platform: $os $arch; supported: Linux x86_64/aarch64" "$case_name"
	[ ! -s "$download_log" ] || die "$case_name attempted a download before rejecting the platform"
	[ ! -s "$checksum_log" ] || die "$case_name attempted a checksum before rejecting the platform"
	[ ! -e "$prefix/bin/botified" ] || die "$case_name installed botified before rejecting the platform"
	say_ok "$case_name"
}

make_manifest_fixture() {
	name=$1
	asset=$2
	mode=$3
	dir="$tmp_root/mutations/$name"
	mkdir -p "$dir"
	cp "$fixture_dir/$asset" "$dir/$asset"
	digest=$(digest_file "$fixture_dir/$asset")
	case "$mode" in
		wrong) printf '%064d  %s\n' 0 "$asset" > "$dir/SHA256SUMS" ;;
		uppercase) printf 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA  %s\n' "$asset" > "$dir/SHA256SUMS" ;;
		duplicate) printf '%s  %s\n%s  %s\n' "$digest" "$asset" "$digest" "$asset" > "$dir/SHA256SUMS" ;;
		missing) printf '%064d  botified-playgroundXtarYgz\n' 0 > "$dir/SHA256SUMS" ;;
		*) die "unknown manifest fixture mode $mode" ;;
	esac
	printf '%s\n' "$dir"
}

make_truncated_fixture() {
	asset=$1
	dir="$tmp_root/mutations/truncated"
	mkdir -p "$dir"
	dd if="$fixture_dir/$asset" of="$dir/$asset" bs=1 count=64 2>/dev/null
	printf '%s  %s\n' "$(digest_file "$fixture_dir/$asset")" "$asset" > "$dir/SHA256SUMS"
	printf '%s\n' "$dir"
}

make_invalid_tar_fixture() {
	asset=$1
	dir="$tmp_root/mutations/invalid-tar"
	mkdir -p "$dir"
	printf 'not a tar archive\n' > "$dir/$asset"
	printf '%s  %s\n' "$(digest_file "$dir/$asset")" "$asset" > "$dir/SHA256SUMS"
	printf '%s\n' "$dir"
}

make_invalid_scope_bundle_fixture() {
	invalid_bundle_kind=$1
	dir="$tmp_root/mutations/invalid-scope-bundle-$invalid_bundle_kind"
	stage="$dir/stage"
	mkdir -p "$dir" "$stage"
	for asset in \
		botified-asr-skill.tar.gz \
		botified-claw-gateway-companion.tar.gz \
		botified-core-linux-aarch64-gnu.tar.gz \
		botified-playground.tar.gz
	do
		cp "$fixture_dir/$asset" "$dir/$asset"
	done
	$host_tar -xzf "$fixture_dir/botified-core-linux-x86_64-musl.tar.gz" -C "$stage"
	case "$invalid_bundle_kind" in
		old-health)
			cat > "$stage/bin/botified" <<'EOF'
#!/bin/sh
# fixture Core predating health --expected-pid
set -eu
printf 'core %s :: %s\n' "$0" "$*" >> "${SHIM_ACTION_LOG:?}"
case "$*" in
	'setup --help --neutral --config / --workspace /'|'config check --config / --help') exit 0 ;;
	'health check --config / --help') exit 0 ;;
	*) exit 64 ;;
esac
EOF
			chmod 0755 "$stage/bin/botified"
			;;
		malformed-unit)
			printf '[Unit]\nDescription=missing managed marker\n' > \
				"$stage/share/botified/systemd/botified.system.service"
			;;
		*) die "unknown invalid scoped bundle fixture $invalid_bundle_kind" ;;
	esac
	$host_tar -C "$stage" -czf "$dir/botified-core-linux-x86_64-musl.tar.gz" .
	write_checksums "$dir"
	printf '%s\n' "$dir"
}

make_unsafe_asr_fixture() {
	dir="$tmp_root/mutations/unsafe-asr"
	stage="$dir/stage"
	mkdir -p "$stage"
	$host_tar -xzf "$fixture_dir/$asr_asset" -C "$stage"
	rm "$stage/botified-asr/scripts/botified-asr"
	ln -s ../SKILL.md "$stage/botified-asr/scripts/botified-asr"
	$host_tar -C "$stage" -czf "$dir/$asr_asset" botified-asr
	printf '%s  %s\n' "$(digest_file "$dir/$asr_asset")" "$asr_asset" > "$dir/SHA256SUMS"
	printf '%s\n' "$dir"
}

asr_target_path() {
	case "$1" in
		codex) printf '%s\n' "$2/.codex/skills/botified-asr" ;;
		openclaw) printf '%s\n' "$2/.agents/skills/botified-asr" ;;
		botified) printf '%s\n' "$2/.local/share/botified/skills/botified-asr" ;;
		*) die "unknown ASR target $1" ;;
	esac
}

run_asr_case() {
	case_name=$1
	target_kind=$2
	version_mode=$3
	case_fixture=$4
	expected_status=$5
	expected_message=$6
	existing=${7:-none}
	config_mode=${8:-absent}
	pointer_mode=${9:-valid}
	expect_asset=${10:-yes}

	case_root="$tmp_root/cases/$pass_count-$case_name"
	case_bin="$case_root/bin"
	home="$case_root/home"
	xdg="$case_root/xdg"
	case_tmp="$case_root/tmp"
	output="$case_root/output"
	download_log="$case_root/downloads"
	checksum_log="$case_root/checksums"
	mkdir -p "$home" "$xdg" "$case_tmp"
	: > "$download_log"
	: > "$checksum_log"
	make_case_bin "$case_bin" curl sha256sum
	target=$(asr_target_path "$target_kind" "$home")
	target_parent=${target%/*}
	versions_root="$target_parent/.botified-asr-versions"
	old_link=

	case "$existing" in
		none) ;;
		managed)
			old_name=asr-v0.9.0-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-old
			mkdir -p "$versions_root/$old_name/botified-asr"
			printf 'old skill\n' > "$versions_root/$old_name/botified-asr/SKILL.md"
			mkdir -p "$versions_root/unknown-sentinel"
			printf 'keep unknown\n' > "$versions_root/unknown-sentinel/keep"
			old_link=".botified-asr-versions/$old_name/botified-asr"
			ln -s "$old_link" "$target"
			;;
		directory)
			mkdir -p "$target"
			printf 'keep directory\n' > "$target/sentinel"
			;;
		*) die "unknown ASR existing target mode $existing" ;;
	esac

	case "$config_mode" in
		absent | half | invalid) ;;
		pair)
			mkdir -p "$xdg/botified-asr"
			printf 'preserved service config\n' > "$xdg/botified-asr/service.env"
			chmod 0640 "$xdg/botified-asr/service.env"
			;;
		rollback)
			xdg="$target/agents/openai.yaml"
			;;
		preserve)
			mkdir -p "$xdg/botified-asr"
			chmod 0700 "$xdg/botified-asr"
			printf 'preserved client config\n' > "$xdg/botified-asr/client.env"
			printf 'preserved service config\n' > "$xdg/botified-asr/service.env"
			chmod 0600 "$xdg/botified-asr/client.env" "$xdg/botified-asr/service.env"
			;;
		*) die "unknown ASR config mode $config_mode" ;;
	esac

	case "$version_mode" in
		explicit)
			selected_version=$asr_version
			;;
		default)
			selected_version=$default_asr_version
			;;
		invalid)
			selected_version=v1.02.3
			;;
		*) die "unknown ASR version mode $version_mode" ;;
	esac
	tag=asr-$selected_version

	set +e
	(
		unset BOTIFIED_ASR_VERSION BOTIFIED_ASR_BASE_URL BOTIFIED_ASR_API_KEY
		if [ "$version_mode" != default ]; then
			BOTIFIED_ASR_VERSION=$selected_version
			export BOTIFIED_ASR_VERSION
		fi
		if [ "$config_mode" = pair ] || [ "$config_mode" = rollback ]; then
			BOTIFIED_ASR_BASE_URL=https://asr.example:8443/
			BOTIFIED_ASR_API_KEY='fixture-token+/=='
			export BOTIFIED_ASR_BASE_URL BOTIFIED_ASR_API_KEY
		elif [ "$config_mode" = half ]; then
			BOTIFIED_ASR_BASE_URL=https://asr.example
			export BOTIFIED_ASR_BASE_URL
		elif [ "$config_mode" = invalid ]; then
			BOTIFIED_ASR_BASE_URL=https://asr.example/path
			BOTIFIED_ASR_API_KEY='fixture-token+/=='
			export BOTIFIED_ASR_BASE_URL BOTIFIED_ASR_API_KEY
		fi
		export \
			HOME="$home" \
			XDG_CONFIG_HOME="$xdg" \
			TMPDIR="$case_tmp" \
			PATH="$case_bin:$base_bin" \
			SHIM_VERSION="$tag" \
			SHIM_DEFAULT_ASR_VERSION="$default_asr_version" \
			SHIM_POINTER_MODE="$pointer_mode" \
			SHIM_FIXTURE_DIR="$case_fixture" \
			SHIM_DOWNLOAD_LOG="$download_log" \
			SHIM_CHECKSUM_LOG="$checksum_log" \
			SHIM_REAL_HASH="$host_hash" \
			SHIM_REAL_HASH_KIND="$host_hash_kind" \
			SHIM_REAL_PYTHON="$host_python" \
			BOTIFIED_VERSION=v99.99.99
		"$host_sh" "$repo_root/install-asr-skill.sh" --target "$target_kind"
	) > "$output" 2>&1
	status=$?
	set -e

	if [ "$expected_status" = success ]; then
		[ "$status" -eq 0 ] || {
			printf 'not ok - %s: expected success, got %s\n' "$case_name" "$status" >&2
			sed -n '1,200p' "$output" >&2
			exit 1
		}
		assert_contains "$output" "Checksum verified." "$case_name"
		[ -L "$target" ] || die "$case_name target is not an atomic discovery symlink"
		installed_link=$(readlink "$target")
		case "$installed_link" in
			.botified-asr-versions/"$tag"-*/botified-asr) ;;
			*) die "$case_name installed an unmanaged discovery symlink: $installed_link" ;;
		esac
		"$host_python" - "$target" <<'PY' || die "$case_name installed the wrong Skill shape"
import os
import stat
import sys
from pathlib import Path

root = Path(sys.argv[1])
expected = {
    ".": (stat.S_IFDIR, 0o755),
    "SKILL.md": (stat.S_IFREG, 0o644),
    "agents": (stat.S_IFDIR, 0o755),
    "agents/openai.yaml": (stat.S_IFREG, 0o644),
    "references": (stat.S_IFDIR, 0o755),
    "references/api.md": (stat.S_IFREG, 0o644),
    "scripts": (stat.S_IFDIR, 0o755),
    "scripts/botified-asr": (stat.S_IFREG, 0o755),
}
actual = {"."}
for directory, directories, files in os.walk(root):
    relative = Path(directory).relative_to(root)
    actual.update((relative / name).as_posix() for name in directories + files)
assert actual == set(expected)
for name, (kind, mode) in expected.items():
    status = (root / name).stat()
    assert stat.S_IFMT(status.st_mode) == kind
    assert stat.S_IMODE(status.st_mode) == mode
PY
		if [ "$existing" = managed ]; then
			[ ! -e "$versions_root/$old_name" ] ||
				die "$case_name retained the old managed version"
			[ -f "$versions_root/unknown-sentinel/keep" ] ||
				die "$case_name removed an unknown versions-root entry"
			[ "$(find "$versions_root" -mindepth 1 -maxdepth 1 | wc -l)" -eq 2 ] ||
				die "$case_name did not clean only old managed versions"
		else
			[ "$(find "$versions_root" -mindepth 1 -maxdepth 1 | wc -l)" -eq 1 ] ||
				die "$case_name retained an unexpected managed version"
		fi
	else
		[ "$status" -ne 0 ] || die "$case_name unexpectedly succeeded"
		if [ -n "$expected_message" ]; then
			assert_contains "$output" "$expected_message" "$case_name"
		fi
		case "$existing" in
			managed)
				[ -L "$target" ] || die "$case_name removed the old managed target"
				[ "$(readlink "$target")" = "$old_link" ] ||
					die "$case_name changed the old managed target"
				[ -s "$target/SKILL.md" ] || die "$case_name removed the old Skill"
				[ -f "$versions_root/unknown-sentinel/keep" ] ||
					die "$case_name removed an unknown versions-root entry"
				[ "$(find "$versions_root" -mindepth 1 -maxdepth 1 | wc -l)" -eq 2 ] ||
					die "$case_name retained a failed new version"
				;;
			directory)
				[ -f "$target/sentinel" ] || die "$case_name changed the ordinary target directory"
				;;
			none) [ ! -e "$target" ] || die "$case_name installed after failure" ;;
		esac
	fi

	pointer_url=https://raw.githubusercontent.com/lzjever/botified-releases/main/botified-asr-latest
	asset_url="https://github.com/lzjever/botified-releases/releases/download/$tag/$asr_asset"
	if [ "$version_mode" = default ]; then
		assert_contains "$download_log" "curl $pointer_url" "$case_name"
	elif grep -F "$pointer_url" "$download_log" >/dev/null 2>&1; then
		die "$case_name fetched the version pointer for an explicit version"
	fi
	if [ "$expect_asset" = yes ]; then
		assert_contains "$download_log" "curl $asset_url" "$case_name"
	elif grep -F "$asr_asset" "$download_log" >/dev/null 2>&1; then
		die "$case_name downloaded the asset before validation completed"
	fi
	if grep -F '/releases/latest/download/' "$download_log" >/dev/null 2>&1; then
		die "$case_name used the repository-wide latest release"
	fi

	case "$config_mode:$expected_status" in
		preserve:success)
			[ "$(cat "$xdg/botified-asr/client.env")" = "preserved client config" ] ||
				die "$case_name changed client.env without explicit config"
			[ "$(cat "$xdg/botified-asr/service.env")" = "preserved service config" ] ||
				die "$case_name read or changed service.env"
			;;
		pair:success)
			if ! "$host_python" - "$xdg/botified-asr/client.env" <<'PY'
import stat
import sys
from pathlib import Path

path = Path(sys.argv[1])
assert path.read_bytes() == (
    b"BOTIFIED_ASR_BASE_URL=https://asr.example:8443/\n"
    b"BOTIFIED_ASR_API_KEY=fixture-token+/==\n"
)
assert stat.S_IMODE(path.stat().st_mode) == 0o600
assert stat.S_IMODE(path.parent.stat().st_mode) == 0o700
service = path.parent / "service.env"
assert service.read_bytes() == b"preserved service config\n"
assert stat.S_IMODE(service.stat().st_mode) == 0o640
PY
			then
				die "$case_name wrote invalid client.env"
			fi
			if grep -F 'fixture-token+/==' "$output" >/dev/null 2>&1; then
				die "$case_name leaked the API key"
			fi
			;;
		rollback:failure)
			if grep -F 'fixture-token+/==' "$output" >/dev/null 2>&1; then
				die "$case_name leaked the API key during rollback"
			fi
			;;
		absent:success)
			[ ! -e "$xdg/botified-asr/client.env" ] ||
				die "$case_name created client.env without explicit config"
			;;
	esac

	say_ok "$case_name"
}

run_asr_argument_case() {
	case_name=$1
	shift
	case_root="$tmp_root/cases/$pass_count-$case_name"
	case_bin="$case_root/bin"
	home="$case_root/home"
	xdg="$case_root/xdg"
	case_tmp="$case_root/tmp"
	output="$case_root/output"
	download_log="$case_root/downloads"
	checksum_log="$case_root/checksums"
	mkdir -p "$home" "$xdg" "$case_tmp"
	: > "$download_log"
	: > "$checksum_log"
	make_case_bin "$case_bin" curl sha256sum

	set +e
	PATH="$case_bin:$base_bin" \
	HOME="$home" \
	XDG_CONFIG_HOME="$xdg" \
	TMPDIR="$case_tmp" \
	SHIM_VERSION="asr-$asr_version" \
	SHIM_DEFAULT_ASR_VERSION="$default_asr_version" \
	SHIM_FIXTURE_DIR="$fixture_dir" \
	SHIM_DOWNLOAD_LOG="$download_log" \
	SHIM_CHECKSUM_LOG="$checksum_log" \
	SHIM_REAL_HASH="$host_hash" \
	SHIM_REAL_HASH_KIND="$host_hash_kind" \
	SHIM_REAL_PYTHON="$host_python" \
	BOTIFIED_ASR_VERSION="$asr_version" \
	"$host_sh" "$repo_root/install-asr-skill.sh" "$@" > "$output" 2>&1
	status=$?
	set -e

	[ "$status" -eq 64 ] || {
		printf 'not ok - %s: expected status 64, got %s\n' "$case_name" "$status" >&2
		sed -n '1,80p' "$output" >&2
		exit 1
	}
	assert_contains "$output" \
		"usage: install-asr-skill.sh --target codex|openclaw|botified" \
		"$case_name"
	[ ! -s "$download_log" ] || die "$case_name downloaded before rejecting arguments"
	say_ok "$case_name"
}

prepare_scoped_case() {
	scoped_case_label=$1
	requested_scope=$2
	scoped_root="$tmp_root/scoped/$scoped_case_label"
	scoped_bin="$scoped_root/bin"
	scoped_home="$scoped_root/home"
	scoped_test_root="$scoped_root/test-root"
	scoped_output="$scoped_root/output"
	scoped_download_log="$scoped_root/downloads"
	scoped_checksum_log="$scoped_root/checksums"
	scoped_action_log="$scoped_root/actions"
	scoped_pid_count="$scoped_root/pid-count"
	scoped_account_state="$scoped_root/account-state"
	mkdir -p "$scoped_home" "$scoped_test_root"
	: > "$scoped_download_log"
	: > "$scoped_checksum_log"
	: > "$scoped_action_log"
	make_scoped_case_bin "$scoped_bin"

	case "$requested_scope" in
		user)
			scoped_uid=1000
			scoped_gid=1000
			scoped_username=fixtureuser
			scoped_binary="$scoped_home/.local/bin/botified"
			scoped_config="$scoped_home/.config/botified/botified.yaml"
			scoped_env="$scoped_home/.config/botified/botified.env"
			scoped_workspace="$scoped_home/.local/share/botified/workspace"
			scoped_unit="$scoped_home/.config/systemd/user/botified.service"
			scoped_skills="$scoped_home/.local/share/botified/skills"
			scoped_docs="$scoped_home/.local/share/doc/botified"
			;;
		system)
			scoped_uid=0
			scoped_gid=0
			scoped_username=root
			scoped_binary=/usr/local/bin/botified
			scoped_config=/etc/botified/botified.yaml
			scoped_env=/etc/botified/botified.env
			scoped_workspace=/var/lib/botified/workspace
			scoped_unit=/etc/systemd/system/botified.service
			scoped_skills=/usr/local/share/botified/skills
			scoped_docs=/usr/local/share/doc/botified
			;;
		*) die "unknown scoped test scope $requested_scope" ;;
	esac
	scoped_binary_fs="$scoped_test_root$scoped_binary"
	scoped_config_fs="$scoped_test_root$scoped_config"
	scoped_env_fs="$scoped_test_root$scoped_env"
	scoped_workspace_fs="$scoped_test_root$scoped_workspace"
	scoped_unit_fs="$scoped_test_root$scoped_unit"
	scoped_skills_fs="$scoped_test_root$scoped_skills"
	scoped_docs_fs="$scoped_test_root$scoped_docs"

	scoped_fixture=$fixture_dir
	scoped_linger=yes
	scoped_enabled_output=enabled
	scoped_active_output=active
	scoped_pid_mode=stable
	scoped_main_pid=4242
	scoped_changed_pid=4243
	scoped_health_process_id=$scoped_main_pid
	scoped_proc_exe=$scoped_binary
	scoped_manager_available=true
	scoped_system_account=present
	scoped_botified_uid=992
	scoped_botified_gid=992
	scoped_proc_uid=$scoped_uid
	scoped_proc_gid=$scoped_gid
	scoped_nss_home=$scoped_home
	scoped_setup_fail=false
	scoped_config_check_fail=false
	scoped_test_contract=both
	scoped_path_override=none
}

invoke_scoped() {
	set +e
	(
		unset BOTIFIED_INSTALL_DIR BOTIFIED_SHARE_DIR BOTIFIED_DOC_DIR BOTIFIED_PREFIX
		unset BOTIFIED_INSTALL_TEST_MODE BOTIFIED_INSTALL_TEST_ROOT
		case "$scoped_test_contract" in
			both)
				BOTIFIED_INSTALL_TEST_MODE=1
				BOTIFIED_INSTALL_TEST_ROOT=$scoped_test_root
				export BOTIFIED_INSTALL_TEST_MODE BOTIFIED_INSTALL_TEST_ROOT
				;;
			mode-only)
				BOTIFIED_INSTALL_TEST_MODE=1
				export BOTIFIED_INSTALL_TEST_MODE
				;;
			root-only)
				BOTIFIED_INSTALL_TEST_ROOT=$scoped_test_root
				export BOTIFIED_INSTALL_TEST_ROOT
				;;
			unsafe-root)
				BOTIFIED_INSTALL_TEST_MODE=1
				BOTIFIED_INSTALL_TEST_ROOT=/
				export BOTIFIED_INSTALL_TEST_MODE BOTIFIED_INSTALL_TEST_ROOT
				;;
			none) ;;
			*) exit 98 ;;
		esac
		case "$scoped_path_override" in
			install)
				BOTIFIED_INSTALL_DIR="$scoped_root/custom-bin"
				export BOTIFIED_INSTALL_DIR
				;;
			none) ;;
			*) exit 98 ;;
		esac
		export \
			PATH="$scoped_bin:$base_bin" \
			HOME="$scoped_home" \
			SHIM_OS=Linux \
			SHIM_ARCH=x86_64 \
			SHIM_UID="$scoped_uid" \
			SHIM_GID="$scoped_gid" \
			SHIM_USERNAME="$scoped_username" \
			SHIM_NSS_HOME="$scoped_nss_home" \
			SHIM_LINGER="$scoped_linger" \
			SHIM_SYSTEM_ACCOUNT="$scoped_system_account" \
			SHIM_ACCOUNT_STATE="$scoped_account_state" \
			SHIM_BOTIFIED_UID="$scoped_botified_uid" \
			SHIM_BOTIFIED_GID="$scoped_botified_gid" \
			SHIM_PROC_UID="$scoped_proc_uid" \
			SHIM_PROC_GID="$scoped_proc_gid" \
			SHIM_ENABLED_OUTPUT="$scoped_enabled_output" \
			SHIM_ACTIVE_OUTPUT="$scoped_active_output" \
			SHIM_PID_MODE="$scoped_pid_mode" \
			SHIM_MAIN_PID="$scoped_main_pid" \
			SHIM_CHANGED_PID="$scoped_changed_pid" \
			SHIM_HEALTH_PROCESS_ID="$scoped_health_process_id" \
			SHIM_PID_COUNT="$scoped_pid_count" \
			SHIM_PROC_EXE="$scoped_proc_exe" \
			SHIM_EXPECTED_BINARY_FS="$scoped_binary_fs" \
			SHIM_EXPECTED_UNIT_FS="$scoped_unit_fs" \
			SHIM_EXPECTED_RELEASE_MARKER='fixture core release v9.8.7' \
			SHIM_SETUP_FAIL="$scoped_setup_fail" \
			SHIM_CONFIG_CHECK_FAIL="$scoped_config_check_fail" \
			SHIM_MANAGER_AVAILABLE="$scoped_manager_available" \
			SHIM_TEST_ROOT="$scoped_test_root" \
			SHIM_ACTION_LOG="$scoped_action_log" \
			SHIM_VERSION="$version" \
			SHIM_FIXTURE_DIR="$scoped_fixture" \
			SHIM_DOWNLOAD_LOG="$scoped_download_log" \
			SHIM_CHECKSUM_LOG="$scoped_checksum_log" \
			SHIM_REAL_HASH="$host_hash" \
			SHIM_REAL_HASH_KIND="$host_hash_kind" \
			SHIM_REAL_PYTHON="$host_python" \
			SHIM_REAL_READLINK="$host_readlink" \
			SHIM_REAL_REALPATH="$host_realpath" \
			SHIM_REAL_STAT="$host_stat" \
			BOTIFIED_VERSION="$version"
		"$host_sh" "$repo_root/install.sh" "$@"
	) > "$scoped_output" 2>&1
	scoped_status=$?
	set -e
}

assert_no_scoped_side_effects() {
	assertion_label=$1
	[ ! -s "$scoped_download_log" ] || die "$assertion_label downloaded before preflight completed"
	[ ! -s "$scoped_action_log" ] || die "$assertion_label invoked a manager or Core command before preflight completed"
}

assert_scoped_paths_absent() {
	absence_label=$1
	shift
	for absence_path in "$@"; do
		[ ! -e "$absence_path" ] && [ ! -L "$absence_path" ] ||
			die "$absence_label unexpectedly wrote $absence_path"
	done
}

assert_mode() {
	mode_label=$1
	mode_path=$2
	expected_mode=$3
	actual_mode=$($host_stat -c %a "$mode_path") || die "$mode_label could not stat $mode_path"
	[ "$actual_mode" = "$expected_mode" ] ||
		die "$mode_label expected mode $expected_mode for $mode_path, got $actual_mode"
}

assert_scoped_lifecycle() {
	lifecycle_label=$1
	lifecycle_scope=$2
	actual=$(grep -E "^systemctl $lifecycle_scope (daemon-reload|enable botified.service|restart botified.service)$" \
		"$scoped_action_log" || true)
	expected=$(printf 'systemctl %s daemon-reload\nsystemctl %s enable botified.service\nsystemctl %s restart botified.service' \
		"$lifecycle_scope" "$lifecycle_scope" "$lifecycle_scope")
	[ "$actual" = "$expected" ] || {
		printf 'not ok - %s: lifecycle was not placement -> reload -> enable -> restart\n' "$lifecycle_label" >&2
		sed -n '1,200p' "$scoped_action_log" >&2
		exit 1
	}
	assert_contains "$scoped_action_log" "systemctl $lifecycle_scope is-enabled botified.service" "$lifecycle_label"
	assert_contains "$scoped_action_log" "systemctl $lifecycle_scope is-active botified.service" "$lifecycle_label"
	[ "$(grep -F -x -c "systemctl $lifecycle_scope show -p MainPID --value botified.service" \
		"$scoped_action_log")" -eq 2 ] ||
		die "$lifecycle_label did not read MainPID exactly twice"
	expected_health_call="core $scoped_binary_fs :: health check --config $scoped_config --expected-pid $scoped_main_pid"
	[ "$(grep -F -x -c "$expected_health_call" "$scoped_action_log")" -eq 1 ] ||
		die "$lifecycle_label did not call target-binary health exactly once"
	[ "$(grep -c ' proc /proc/' "$scoped_action_log")" -eq 2 ] ||
		die "$lifecycle_label did not verify /proc/PID/exe before and after health"
	if [ "$lifecycle_scope" = user ]; then
		[ "$(grep -c '^loginctl show-user ' "$scoped_action_log")" -eq 2 ] ||
			die "$lifecycle_label did not read Linger before install and after health"
		if grep -F 'enable-linger' "$scoped_action_log" >/dev/null 2>&1; then
			die "$lifecycle_label modified Linger"
		fi
	else
		grep -F 'stat proc ' "$scoped_action_log" >/dev/null 2>&1 ||
			die "$lifecycle_label did not verify the system process UID/GID"
	fi
	other_scope=system
	[ "$lifecycle_scope" != system ] || other_scope=user
	if grep -F "systemctl $other_scope " "$scoped_action_log" >/dev/null 2>&1; then
		die "$lifecycle_label operated the other systemd manager"
	fi
}

run_files_only_no_systemd_case() {
	case_name="core files-only leaf never invokes systemd"
	prepare_scoped_case files-only user
	legacy_prefix="$scoped_root/legacy"
	set +e
	PATH="$scoped_bin:$base_bin" \
	HOME="$scoped_home" \
	SHIM_OS=Linux \
	SHIM_ARCH=x86_64 \
	SHIM_VERSION="$version" \
	SHIM_FIXTURE_DIR="$fixture_dir" \
	SHIM_DOWNLOAD_LOG="$scoped_download_log" \
	SHIM_CHECKSUM_LOG="$scoped_checksum_log" \
	SHIM_REAL_HASH="$host_hash" \
	SHIM_REAL_HASH_KIND="$host_hash_kind" \
	SHIM_REAL_PYTHON="$host_python" \
	SHIM_ACTION_LOG="$scoped_action_log" \
	BOTIFIED_VERSION="$version" \
	BOTIFIED_INSTALL_DIR="$legacy_prefix/bin" \
	BOTIFIED_SHARE_DIR="$legacy_prefix/share/botified" \
	BOTIFIED_DOC_DIR="$legacy_prefix/share/doc/botified" \
	"$host_sh" "$repo_root/install.sh" > "$scoped_output" 2>&1
	status=$?
	set -e
	[ "$status" -eq 0 ] || die "$case_name failed"
	[ -x "$legacy_prefix/bin/botified" ] || die "$case_name did not retain legacy file placement"
	[ ! -s "$scoped_action_log" ] || die "$case_name invoked Core/systemd commands"
	say_ok "$case_name"
}

run_scoped_argument_contract() {
	case_name="scoped parser rejects incomplete unknown duplicate and extra arguments before download"
	prepare_scoped_case parser user
	for arguments in '--scope' '--scope unknown' '--scope user --scope system' '--scope user extra'; do
		: > "$scoped_download_log"
		: > "$scoped_action_log"
		# Deliberately split the fixed test inputs into argv.
		# shellcheck disable=SC2086
		invoke_scoped $arguments
		[ "$scoped_status" -ne 0 ] || die "$case_name accepted: $arguments"
		assert_no_scoped_side_effects "$case_name ($arguments)"
	done
	say_ok "$case_name"
}

run_scoped_preflight_contract() {
	case_name="scoped preflight enforces identity NSS HOME Linger and fixed paths"
	prepare_scoped_case preflight user
	scoped_uid=0
	invoke_scoped --scope user
	[ "$scoped_status" -ne 0 ] || die "$case_name accepted root user scope"
	assert_no_scoped_side_effects "$case_name root user"

	prepare_scoped_case preflight-system system
	scoped_uid=1000
	invoke_scoped --scope system
	[ "$scoped_status" -ne 0 ] || die "$case_name accepted non-root system scope"
	assert_no_scoped_side_effects "$case_name non-root system"

	prepare_scoped_case preflight-home user
	scoped_nss_home=$scoped_home
	scoped_home="$scoped_root/ambient-home"
	mkdir -p "$scoped_home"
	invoke_scoped --scope user
	[ "$scoped_status" -ne 0 ] || die "$case_name accepted a HOME that differs from NSS"
	assert_no_scoped_side_effects "$case_name HOME mismatch"

	prepare_scoped_case preflight-linger user
	scoped_linger=no
	invoke_scoped --scope user
	[ "$scoped_status" -ne 0 ] || die "$case_name accepted Linger=no"
	[ ! -s "$scoped_download_log" ] || die "$case_name downloaded before rejecting Linger=no"
	assert_contains "$scoped_output" \
		"sudo loginctl enable-linger $scoped_username" "$case_name Linger=no"
	if grep -F enable-linger "$scoped_action_log" >/dev/null 2>&1; then
		die "$case_name attempted to enable Linger"
	fi
	assert_scoped_paths_absent "$case_name Linger=no" \
		"$scoped_binary_fs" "$scoped_config_fs" "$scoped_env_fs" \
		"$scoped_workspace_fs" "$scoped_unit_fs"

	prepare_scoped_case preflight-manager user
	scoped_manager_available=false
	invoke_scoped --scope user
	[ "$scoped_status" -ne 0 ] || die "$case_name accepted an unavailable user manager"
	[ ! -s "$scoped_download_log" ] || die "$case_name downloaded with an unavailable user manager"
	[ "$(grep -F -x -c 'systemctl user show-environment' "$scoped_action_log")" -eq 1 ] ||
		die "$case_name did not probe the real user manager exactly once"
	if grep -E '^systemctl user (daemon-reload|enable |restart )' \
		"$scoped_action_log" >/dev/null 2>&1
	then
		die "$case_name mutated systemd after manager connection failure"
	fi
	assert_scoped_paths_absent "$case_name unavailable manager" \
		"$scoped_binary_fs" "$scoped_config_fs" "$scoped_env_fs" \
		"$scoped_workspace_fs" "$scoped_unit_fs"

	prepare_scoped_case preflight-system-manager system
	scoped_manager_available=false
	invoke_scoped --scope system
	[ "$scoped_status" -ne 0 ] || die "$case_name accepted an unavailable system manager"
	[ ! -s "$scoped_download_log" ] || die "$case_name downloaded with an unavailable system manager"
	[ "$(grep -F -x -c 'systemctl system show --property=Version --value' \
		"$scoped_action_log")" -eq 1 ] ||
		die "$case_name did not probe the real system manager exactly once"
	if grep -E '^systemctl system (daemon-reload|enable |restart )' \
		"$scoped_action_log" >/dev/null 2>&1
	then
		die "$case_name mutated systemd after system manager connection failure"
	fi
	assert_scoped_paths_absent "$case_name unavailable system manager" \
		"$scoped_binary_fs" "$scoped_config_fs" "$scoped_env_fs" \
		"$scoped_workspace_fs" "$scoped_unit_fs"

	prepare_scoped_case preflight-override user
	scoped_path_override=install
	invoke_scoped --scope user
	[ "$scoped_status" -ne 0 ] || die "$case_name accepted a scoped path override"
	[ ! -s "$scoped_download_log" ] || die "$case_name downloaded before rejecting a path override"
	say_ok "$case_name"
}

run_test_root_contract() {
	case_name="test-only filesystem root requires both safe variables"
	for contract in mode-only root-only unsafe-root; do
		prepare_scoped_case "test-root-$contract" user
		scoped_test_contract=$contract
		invoke_scoped --scope user
		[ "$scoped_status" -ne 0 ] || die "$case_name accepted $contract"
		[ ! -s "$scoped_download_log" ] || die "$case_name downloaded before rejecting $contract"
		[ ! -e "$scoped_binary_fs" ] && [ ! -e "$scoped_config_fs" ] && [ ! -e "$scoped_unit_fs" ] ||
			die "$case_name wrote a canonical target before rejecting $contract"
		if grep -E '^(useradd |systemctl (user|system) (daemon-reload|enable |restart ))' \
			"$scoped_action_log" >/dev/null 2>&1
		then
			die "$case_name mutated account or systemd before rejecting $contract"
		fi
	done
	say_ok "$case_name"
}

run_unmanaged_unit_case() {
	case_name="scoped install refuses an unmanaged canonical unit before download"
	for unmanaged_kind in marker-after-first-line symlink; do
		prepare_scoped_case "unmanaged-unit-$unmanaged_kind" user
		mkdir -p "${scoped_unit_fs%/*}"
		case "$unmanaged_kind" in
			marker-after-first-line)
				printf '[Unit]\n# Managed by the Botified installer. Inspect and operate with systemd tools.\n' \
					> "$scoped_unit_fs"
				;;
			symlink)
				admin_unit="$scoped_root/administrator-owned.service"
				printf '[Unit]\nDescription=administrator owned\n' > "$admin_unit"
				ln -s "$admin_unit" "$scoped_unit_fs"
				;;
		esac
		invoke_scoped --scope user
		[ "$scoped_status" -ne 0 ] || die "$case_name accepted $unmanaged_kind"
		[ ! -s "$scoped_download_log" ] || die "$case_name downloaded before rejecting $unmanaged_kind"
		case "$unmanaged_kind" in
			marker-after-first-line)
				[ "$(cat "$scoped_unit_fs")" = '[Unit]
# Managed by the Botified installer. Inspect and operate with systemd tools.' ] ||
					die "$case_name changed $unmanaged_kind"
				;;
			symlink)
				[ -L "$scoped_unit_fs" ] &&
					[ "$(cat "$admin_unit")" = '[Unit]
Description=administrator owned' ] || die "$case_name changed $unmanaged_kind"
				;;
		esac
		assert_scoped_paths_absent "$case_name $unmanaged_kind" \
			"$scoped_binary_fs" "$scoped_config_fs" "$scoped_env_fs" "$scoped_workspace_fs"
	done
	say_ok "$case_name"
}

run_bundle_and_config_validation_case() {
	case_name="bundle capability and config validation precede account release placement and systemd"
	for bundle_failure in old-health malformed-unit; do
		prepare_scoped_case "bundle-$bundle_failure" system
		scoped_fixture=$(make_invalid_scope_bundle_fixture "$bundle_failure")
		scoped_system_account=absent
		scoped_proc_uid=$scoped_botified_uid
		scoped_proc_gid=$scoped_botified_gid
		invoke_scoped --scope system
		[ "$scoped_status" -ne 0 ] || die "$case_name accepted $bundle_failure"
		if grep -E '^(useradd |systemctl (user|system) (daemon-reload|enable |restart ))' \
			"$scoped_action_log" >/dev/null 2>&1
		then
			die "$case_name created the account or mutated systemd before $bundle_failure validation"
		fi
		assert_scoped_paths_absent "$case_name $bundle_failure" \
			"$scoped_binary_fs" "$scoped_config_fs" "$scoped_env_fs" \
			"$scoped_workspace_fs" "$scoped_unit_fs"
	done

	prepare_scoped_case account-conflict system
	scoped_system_account=conflict
	invoke_scoped --scope system
	[ "$scoped_status" -ne 0 ] || die "$case_name accepted a conflicting system account"
	if grep -E '^(useradd |systemctl (user|system) (daemon-reload|enable |restart ))' \
		"$scoped_action_log" >/dev/null 2>&1
	then
		die "$case_name mutated the account or systemd after detecting an account conflict"
	fi
	assert_scoped_paths_absent "$case_name account conflict" \
		"$scoped_binary_fs" "$scoped_config_fs" "$scoped_env_fs" \
		"$scoped_workspace_fs" "$scoped_unit_fs"

	prepare_scoped_case config-invalid system
	scoped_config_check_fail=true
	scoped_proc_uid=$scoped_botified_uid
	scoped_proc_gid=$scoped_botified_gid
	mkdir -p "${scoped_config_fs%/*}"
	printf 'preserved invalid config\n' > "$scoped_config_fs"
	invoke_scoped --scope system
	[ "$scoped_status" -ne 0 ] || die "$case_name accepted a config-check failure"
	if grep -E '^systemctl (user|system) (daemon-reload|enable |restart )' \
		"$scoped_action_log" >/dev/null 2>&1
	then
		die "$case_name mutated systemd after config-check failure"
	fi
	[ ! -e "$scoped_binary_fs" ] || die "$case_name placed release files after config-check failure"
	[ "$(cat "$scoped_config_fs")" = 'preserved invalid config' ] || die "$case_name changed existing config"
	say_ok "$case_name"
}

run_user_repeat_success_case() {
	case_name="user scope preserves data and always replaces managed release then restarts"
	prepare_scoped_case user-repeat user
	mkdir -p "${scoped_binary_fs%/*}" "${scoped_unit_fs%/*}" \
		"${scoped_config_fs%/*}" "$scoped_workspace_fs/.botified/state" \
		"$scoped_skills_fs/unknown-sibling" "$scoped_skills_fs/botified-agent-guide" \
		"$scoped_docs_fs"
	printf '# old managed binary\n' > "$scoped_binary_fs"
	chmod 0755 "$scoped_binary_fs"
	printf '# Managed by the Botified installer. Inspect and operate with systemd tools.\nold unit\n' > "$scoped_unit_fs"
	printf 'preserved config\n' > "$scoped_config_fs"
	printf 'preserved env\n' > "$scoped_env_fs"
	printf 'preserved state\n' > "$scoped_workspace_fs/.botified/state/data"
	printf 'preserved sibling\n' > "$scoped_skills_fs/unknown-sibling/data"
	printf 'old owned leaf\n' > "$scoped_skills_fs/botified-agent-guide/old"
	printf 'old docs\n' > "$scoped_docs_fs/old"

	for run_number in 1 2; do
		: > "$scoped_action_log"
		rm -f "$scoped_pid_count"
		invoke_scoped --scope user
		[ "$scoped_status" -eq 0 ] || {
			printf 'not ok - %s: run %s failed\n' "$case_name" "$run_number" >&2
			sed -n '1,200p' "$scoped_output" >&2
			exit 1
		}
		assert_scoped_lifecycle "$case_name run $run_number" user
		grep -F 'fixture core release v9.8.7' "$scoped_binary_fs" >/dev/null ||
			die "$case_name did not replace the binary on run $run_number"
	done
	[ "$(cat "$scoped_config_fs")" = 'preserved config' ] || die "$case_name changed config"
	[ "$(cat "$scoped_env_fs")" = 'preserved env' ] || die "$case_name changed env"
	[ "$(cat "$scoped_workspace_fs/.botified/state/data")" = 'preserved state' ] || die "$case_name changed runtime data"
	[ "$(cat "$scoped_skills_fs/unknown-sibling/data")" = 'preserved sibling' ] || die "$case_name removed an unknown skill sibling"
	[ ! -e "$scoped_skills_fs/botified-agent-guide/old" ] || die "$case_name did not replace the owned skill leaf"
	[ ! -e "$scoped_docs_fs/old" ] || die "$case_name did not replace Core docs"
	assert_mode "$case_name" "$scoped_binary_fs" 755
	assert_mode "$case_name" "$scoped_unit_fs" 644
	assert_mode "$case_name" "$scoped_config_fs" 600
	assert_mode "$case_name" "$scoped_env_fs" 600
	for expected_output in \
		'Installed managed user service: botified.service' \
		"Binary: $scoped_binary" \
		'Boot target: default.target' \
		'Enabled: enabled' \
		'Active: active' \
		'MainPID: 4242' \
		'Linger: yes' \
		'systemctl --user restart botified.service' \
		'journalctl --user -u botified.service -n 100 --no-pager' \
		'Provider configuration is intentionally left for the administrator.'
	do
		assert_contains "$scoped_output" "$expected_output" "$case_name"
	done
	say_ok "$case_name"
}

run_system_first_install_success_case() {
	case_name="system scope validates capabilities creates account late and proves exact runtime"
	prepare_scoped_case system-first system
	scoped_system_account=absent
	scoped_proc_uid=$scoped_botified_uid
	scoped_proc_gid=$scoped_botified_gid
	invoke_scoped --scope system
	[ "$scoped_status" -eq 0 ] || {
		printf 'not ok - %s: failed\n' "$case_name" >&2
		sed -n '1,200p' "$scoped_output" >&2
		exit 1
	}
	for capability in \
		'setup --help --neutral --config / --workspace /' \
		'config check --config / --help' \
		'health check --config / --expected-pid 1 --help'
	do
		if ! grep -E "^core .*/bundle/bin/botified :: $capability$" "$scoped_action_log" >/dev/null 2>&1; then
			die "$case_name did not run staged capability check: $capability"
		fi
	done
	grep -E '^core .*/bundle/bin/botified :: setup --neutral --config /etc/botified/botified.yaml --workspace /var/lib/botified/workspace$' \
		"$scoped_action_log" >/dev/null 2>&1 || die "$case_name did not run staged neutral setup"
	grep -E '^core .*/bundle/bin/botified :: config check --config /etc/botified/botified.yaml$' \
		"$scoped_action_log" >/dev/null 2>&1 || die "$case_name did not run staged config check"
	assert_contains "$scoped_action_log" 'useradd -r -U -d /var/lib/botified -m -s /usr/sbin/nologin botified' "$case_name"
	capability_line=$(grep -n '^core .*/bundle/bin/botified :: health check --config / --expected-pid 1 --help$' \
		"$scoped_action_log" | cut -d: -f1)
	useradd_line=$(grep -n '^useradd ' "$scoped_action_log" | cut -d: -f1)
	[ -n "$capability_line" ] && [ "$capability_line" -lt "$useradd_line" ] ||
		die "$case_name did not create the account after capability validation"
	assert_scoped_lifecycle "$case_name" system
	[ -s "$scoped_config_fs" ] || die "$case_name did not create neutral config"
	[ -f "$scoped_env_fs" ] || die "$case_name did not create the process env file"
	assert_mode "$case_name" "$scoped_binary_fs" 755
	assert_mode "$case_name" "$scoped_unit_fs" 644
	assert_mode "$case_name" "$scoped_config_fs" 640
	assert_mode "$case_name" "$scoped_env_fs" 640
	assert_mode "$case_name" "$scoped_workspace_fs" 750
	assert_mode "$case_name" "$scoped_test_root/var/lib/botified" 750
	assert_contains "$scoped_action_log" "chown root:botified ${scoped_config_fs%/*} $scoped_env_fs" "$case_name"
	assert_contains "$scoped_action_log" "chown botified:botified $scoped_test_root/var/lib/botified" "$case_name"
	assert_contains "$scoped_action_log" "chown botified:botified $scoped_workspace_fs" "$case_name"
	assert_contains "$scoped_action_log" "chown root:botified $scoped_config_fs" "$case_name"
	for expected_output in \
		'Installed managed system service: botified.service' \
		'Binary: /usr/local/bin/botified' \
		'Boot target: multi-user.target' \
		'Enabled: enabled' \
		'Active: active' \
		'MainPID: 4242' \
		'systemctl restart botified.service' \
		'journalctl -u botified.service -n 100 --no-pager' \
		'Provider configuration is intentionally left for the administrator.'
	do
		assert_contains "$scoped_output" "$expected_output" "$case_name"
	done
	say_ok "$case_name"
}

run_runtime_verification_failures() {
	case_name="scoped runtime proof rejects nonexact state PID proc target health and PID change"
	for failure in enabled active zero-pid wrong-exe health pid-change system-identity; do
		runtime_scope=user
		[ "$failure" != system-identity ] || runtime_scope=system
		prepare_scoped_case "runtime-$failure" "$runtime_scope"
		mkdir -p "${scoped_config_fs%/*}"
		printf 'existing config\n' > "$scoped_config_fs"
		case "$failure" in
			enabled) scoped_enabled_output='enabled-runtime' ;;
			active) scoped_active_output='activating' ;;
			zero-pid) scoped_pid_mode=zero ;;
			wrong-exe) scoped_proc_exe="$scoped_home/.local/bin/not-botified" ;;
			health) scoped_health_process_id=$scoped_changed_pid ;;
			pid-change) scoped_pid_mode=changes ;;
			system-identity) scoped_proc_uid=0; scoped_proc_gid=0 ;;
		esac
		invoke_scoped --scope "$runtime_scope"
		[ "$scoped_status" -ne 0 ] || die "$case_name accepted $failure"
		actual=$(grep -E "^systemctl $runtime_scope (daemon-reload|enable botified.service|restart botified.service)$" \
			"$scoped_action_log" || true)
		expected=$(printf 'systemctl %s daemon-reload\nsystemctl %s enable botified.service\nsystemctl %s restart botified.service' \
			"$runtime_scope" "$runtime_scope" "$runtime_scope")
		[ "$actual" = "$expected" ] || die "$case_name did not reach the common lifecycle for $failure"
	done
	say_ok "$case_name"
}

run_case "core Linux x86_64 prefers sha256sum via curl" install.sh Linux x86_64 curl both "$fixture_dir" success ""
run_case "core Linux aarch64 via wget and sha256sum" install.sh Linux aarch64 wget sha256sum "$fixture_dir" success ""
run_case "core warns when gateway needs a separate upgrade" install.sh Linux x86_64 curl sha256sum "$fixture_dir" success "" auto true
run_unsupported_core_case "core rejects Darwin x86_64 before download" Darwin x86_64
run_unsupported_core_case "core rejects Darwin arm64 before download" Darwin arm64
run_case "gateway normal install" install-gateway.sh Linux x86_64 curl sha256sum "$fixture_dir" success ""
run_case "playground normal install" install-playground.sh Linux x86_64 wget shasum "$fixture_dir" success ""

run_case "checksum tools are mandatory" install-gateway.sh Linux x86_64 curl none "$fixture_dir" failure "sha256sum or shasum is required"
HTTP_404_ASSET=botified-playground.tar.gz
run_case "asset download 404 fails" install-playground.sh Linux x86_64 wget sha256sum "$fixture_dir" failure ""

asset=botified-core-linux-x86_64-musl.tar.gz
wrong_fixture=$(make_manifest_fixture wrong "$asset" wrong)
run_case "wrong checksum fails" install.sh Linux x86_64 curl sha256sum "$wrong_fixture" failure "checksum mismatch"

asset=botified-core-linux-x86_64-musl.tar.gz
uppercase_core_fixture=$(make_manifest_fixture uppercase-core "$asset" uppercase)
run_case "core rejects uppercase checksum before hashing" install.sh Linux x86_64 curl sha256sum "$uppercase_core_fixture" failure "invalid checksum" not-called

asset=botified-claw-gateway-companion.tar.gz
uppercase_gateway_fixture=$(make_manifest_fixture uppercase-gateway "$asset" uppercase)
run_case "gateway rejects uppercase checksum before hashing" install-gateway.sh Linux x86_64 curl shasum "$uppercase_gateway_fixture" failure "invalid checksum" not-called

asset=botified-playground.tar.gz
uppercase_playground_fixture=$(make_manifest_fixture uppercase-playground "$asset" uppercase)
run_case "playground rejects uppercase checksum before hashing" install-playground.sh Linux x86_64 wget sha256sum "$uppercase_playground_fixture" failure "invalid checksum" not-called

asset=botified-claw-gateway-companion.tar.gz
duplicate_fixture=$(make_manifest_fixture duplicate "$asset" duplicate)
run_case "duplicate target checksum fails" install-gateway.sh Linux x86_64 wget sha256sum "$duplicate_fixture" failure "checksum for $asset must appear exactly once"

asset=botified-playground.tar.gz
missing_fixture=$(make_manifest_fixture missing "$asset" missing)
run_case "missing target checksum fails" install-playground.sh Linux x86_64 curl shasum "$missing_fixture" failure "checksum for $asset must appear exactly once"

asset=botified-core-linux-x86_64-musl.tar.gz
truncated_fixture=$(make_truncated_fixture "$asset")
run_case "truncated archive fails checksum before extraction" install.sh Linux x86_64 wget sha256sum "$truncated_fixture" failure "checksum mismatch"

asset=botified-claw-gateway-companion.tar.gz
invalid_tar_fixture=$(make_invalid_tar_fixture "$asset")
run_case "checksum-correct invalid tar fails extraction" install-gateway.sh Linux x86_64 curl shasum "$invalid_tar_fixture" failure ""

run_asr_argument_case "ASR skill requires target arguments"
run_asr_argument_case "ASR skill rejects an unknown target" --target unknown
run_asr_argument_case "ASR skill rejects extra arguments" --target codex extra

run_asr_case "ASR skill installs Codex target and replaces an old managed version" \
	codex explicit "$fixture_dir" success "" managed preserve
run_asr_case "ASR skill installs OpenClaw target and private client config" \
	openclaw explicit "$fixture_dir" success "" none pair
run_asr_case "ASR skill installs Botified target" \
	botified explicit "$fixture_dir" success ""
run_asr_case "ASR skill resolves its default version pointer" \
	codex default "$fixture_dir" success ""

run_asr_case "ASR skill rejects a noncanonical explicit version before download" \
	codex invalid "$fixture_dir" failure "invalid version" none absent valid no
run_asr_case "ASR skill rejects a noncanonical pointer before asset download" \
	codex default "$fixture_dir" failure "invalid version pointer" none absent invalid-version no
run_asr_case "ASR skill requires the pointer final newline before asset download" \
	codex default "$fixture_dir" failure "invalid version pointer" none absent missing-newline no
run_asr_case "ASR skill rejects half configured client credentials before download" \
	codex explicit "$fixture_dir" failure "must be provided together" none half valid no
run_asr_case "ASR skill rejects invalid client origin before download" \
	codex explicit "$fixture_dir" failure "invalid client configuration" none invalid valid no
run_asr_case "ASR skill preserves an ordinary target directory before download" \
	codex explicit "$fixture_dir" failure "target already exists" directory absent valid no

asr_wrong_fixture=$(make_manifest_fixture wrong-asr "$asr_asset" wrong)
run_asr_case "ASR skill wrong checksum preserves the old managed version" \
	codex explicit "$asr_wrong_fixture" failure "checksum mismatch" managed

unsafe_asr_fixture=$(make_unsafe_asr_fixture)
run_asr_case "ASR skill unsafe tar preserves the old managed version" \
	codex explicit "$unsafe_asr_fixture" failure "invalid Skill archive" managed

run_asr_case "ASR skill config commit failure restores the old managed version" \
	codex explicit "$fixture_dir" failure "invalid Skill archive" managed rollback

run_files_only_no_systemd_case
run_scoped_argument_contract
run_scoped_preflight_contract
run_test_root_contract
run_unmanaged_unit_case
run_bundle_and_config_validation_case
run_user_repeat_success_case
run_system_first_install_success_case
run_runtime_verification_failures

printf '1..%d\n' "$pass_count"
