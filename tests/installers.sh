#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
fixture_dir=${1:-${BOTIFIED_INSTALLER_FIXTURES:-}}
version=v9.8.7

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
		botified-claw-gateway-companion.tar.gz \
		botified-core-linux-aarch64-gnu.tar.gz \
		botified-core-linux-x86_64-gnu.tar.gz \
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
		"$stage/playground/bin" \
		"$stage/playground/share/botified/skills/robot-playground"

	for name in botified botified-tui; do
		printf '#!/bin/sh\nexit 0\n' > "$stage/core/bin/$name"
		chmod 0755 "$stage/core/bin/$name"
	done
	printf 'fixture skill\n' > "$stage/core/share/botified/skills/example/SKILL.md"
	printf 'fixture docs\n' > "$stage/core/share/doc/botified/README.md"

	printf '#!/bin/sh\n[ "${1:-}" = self-check ]\n' > "$stage/gateway/bin/botified-claw-gateway"
	chmod 0755 "$stage/gateway/bin/botified-claw-gateway"
	printf 'fixture gateway\n' > "$stage/gateway/share/botified/gateway/dist/src/cli.js"

	printf '#!/bin/sh\n[ "${1:-}" = self-check ]\n' > "$stage/playground/bin/botified-playground"
	chmod 0755 "$stage/playground/bin/botified-playground"
	printf 'fixture playground skill\n' > "$stage/playground/share/botified/skills/robot-playground/SKILL.md"

	$host_tar -C "$stage/core" -czf "$dir/botified-core-linux-x86_64-gnu.tar.gz" .
	cp "$dir/botified-core-linux-x86_64-gnu.tar.gz" "$dir/botified-core-linux-aarch64-gnu.tar.gz"
	$host_tar -C "$stage/gateway" -czf "$dir/botified-claw-gateway-companion.tar.gz" .
	$host_tar -C "$stage/playground" -czf "$dir/botified-playground.tar.gz" .
	write_checksums "$dir"
}

if [ -z "$fixture_dir" ]; then
	fixture_dir="$tmp_root/fixtures"
	make_generated_fixtures "$fixture_dir"
else
	case "$fixture_dir" in
		/*) ;;
		*) fixture_dir=$(CDPATH= cd -- "$fixture_dir" && pwd) ;;
	esac
fi

for required in \
	botified-core-linux-x86_64-gnu.tar.gz \
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

for command_name in sh env uname mktemp rm mkdir tar gzip install cp chmod dirname; do
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
		[ "$#" -eq 4 ] && [ "$1" = -fsSL ] && [ "$3" = -o ] || exit 90
		url=$2
		out=$4
		;;
	wget)
		[ "$#" -eq 3 ] && [ "$1" = -qO ] || exit 91
		out=$2
		url=$3
		;;
	*) exit 92 ;;
esac

prefix="https://github.com/lzjever/botified-releases/releases/download/$SHIM_VERSION"
case "$url" in
	"$prefix"/*) asset=${url#"$prefix"/} ;;
	*) printf 'unexpected download URL: %s\n' "$url" >&2; exit 93 ;;
esac
case "$asset" in
	*/*|'') printf 'unexpected asset URL: %s\n' "$url" >&2; exit 94 ;;
esac
printf '%s %s\n' "$tool" "$url" >> "$SHIM_DOWNLOAD_LOG"
if [ "${SHIM_HTTP_404_ASSET:-}" = "$asset" ]; then
	exit 22
fi
cp "$SHIM_FIXTURE_DIR/$asset" "$out"
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
				Linux:x86_64) printf '%s\n' botified-core-linux-x86_64-gnu.tar.gz ;;
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
				;;
			install-gateway.sh) [ -x "$prefix/bin/botified-claw-gateway" ] || die "$case_name did not install gateway" ;;
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

run_case "core Linux x86_64 prefers sha256sum via curl" install.sh Linux x86_64 curl both "$fixture_dir" success ""
run_case "core Linux aarch64 via wget and sha256sum" install.sh Linux aarch64 wget sha256sum "$fixture_dir" success ""
run_unsupported_core_case "core rejects Darwin x86_64 before download" Darwin x86_64
run_unsupported_core_case "core rejects Darwin arm64 before download" Darwin arm64
run_case "gateway normal install" install-gateway.sh Linux x86_64 curl sha256sum "$fixture_dir" success ""
run_case "playground normal install" install-playground.sh Linux x86_64 wget shasum "$fixture_dir" success ""

run_case "checksum tools are mandatory" install-gateway.sh Linux x86_64 curl none "$fixture_dir" failure "sha256sum or shasum is required"
HTTP_404_ASSET=botified-playground.tar.gz
run_case "asset download 404 fails" install-playground.sh Linux x86_64 wget sha256sum "$fixture_dir" failure ""

asset=botified-core-linux-x86_64-gnu.tar.gz
wrong_fixture=$(make_manifest_fixture wrong "$asset" wrong)
run_case "wrong checksum fails" install.sh Linux x86_64 curl sha256sum "$wrong_fixture" failure "checksum mismatch"

asset=botified-core-linux-x86_64-gnu.tar.gz
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

asset=botified-core-linux-x86_64-gnu.tar.gz
truncated_fixture=$(make_truncated_fixture "$asset")
run_case "truncated archive fails checksum before extraction" install.sh Linux x86_64 wget sha256sum "$truncated_fixture" failure "checksum mismatch"

asset=botified-claw-gateway-companion.tar.gz
invalid_tar_fixture=$(make_invalid_tar_fixture "$asset")
run_case "checksum-correct invalid tar fails extraction" install-gateway.sh Linux x86_64 curl shasum "$invalid_tar_fixture" failure ""

printf '1..%d\n' "$pass_count"
