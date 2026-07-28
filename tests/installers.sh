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
		"$stage/core/share/botified/skills/example" \
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

	for name in botified botified-tui; do
		printf '#!/bin/sh\nexit 0\n' > "$stage/core/bin/$name"
		chmod 0755 "$stage/core/bin/$name"
	done
	printf 'fixture skill\n' > "$stage/core/share/botified/skills/example/SKILL.md"
	printf 'fixture docs\n' > "$stage/core/share/doc/botified/README.md"

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

for command_name in sh env uname mktemp rm mkdir mv tar gzip install cp chmod dirname; do
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

assert_contains() {
	file=$1
	text=$2
	case_name=$3
	if ! grep -F "$text" "$file" >/dev/null 2>&1; then
		printf 'not ok - %s: output does not contain: %s\n' "$case_name" "$text" >&2
		sed -n '1,160p' "$file" >&2
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

printf '1..%d\n' "$pass_count"
