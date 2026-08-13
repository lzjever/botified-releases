#!/bin/sh
set -eu

repo="${BOTIFIED_RELEASES_REPO:-lzjever/botified-releases}"
version="${BOTIFIED_VERSION:-latest}"
install_dir_is_set=${BOTIFIED_INSTALL_DIR+x}
share_dir_is_set=${BOTIFIED_SHARE_DIR+x}
doc_dir_is_set=${BOTIFIED_DOC_DIR+x}
prefix_is_set=${BOTIFIED_PREFIX+x}

log() {
	printf '%s\n' "$*"
}

warn() {
	printf 'botified install: warning: %s\n' "$*" >&2
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

download() {
	url=$1
	out=$2
	if [ "$downloader" = curl ]; then
		curl -fL --retry 3 --retry-all-errors --connect-timeout 15 --silent --show-error -o "$out" "$url"
	else
		wget -q --tries=4 --timeout=30 -O "$out" "$url"
	fi
}

is_decimal() {
	case "$1" in
		''|*[!0-9]*) return 1 ;;
		*) return 0 ;;
	esac
}

scoped_fs_path() {
	printf '%s%s\n' "$install_test_root" "$1"
}

scoped_systemctl() {
	if [ "$managed_scope" = user ]; then
		systemctl --user "$@"
	else
		systemctl "$@"
	fi
}

has_managed_unit_marker() {
	managed_unit_path=$1
	[ -f "$managed_unit_path" ] && [ ! -L "$managed_unit_path" ] || return 1
	IFS= read -r managed_unit_first_line < "$managed_unit_path" || return 1
	[ "$managed_unit_first_line" = '# Managed by the Botified installer. Inspect and operate with systemd tools.' ]
}

validate_test_root() {
	install_test_root=
	test_mode_is_set=${BOTIFIED_INSTALL_TEST_MODE+x}
	test_root_is_set=${BOTIFIED_INSTALL_TEST_ROOT+x}
	if [ "$test_mode_is_set" != x ] && [ "$test_root_is_set" != x ]; then
		return
	fi
	[ "$test_mode_is_set" = x ] && [ "$test_root_is_set" = x ] ||
		fail "invalid internal test root"
	[ "$BOTIFIED_INSTALL_TEST_MODE" = 1 ] || fail "invalid internal test root"
	case "$BOTIFIED_INSTALL_TEST_ROOT" in
		/*) ;;
		*) fail "invalid internal test root" ;;
	esac
	case "$BOTIFIED_INSTALL_TEST_ROOT" in
		/|*/../*|*/..) fail "invalid internal test root" ;;
	esac
	[ -d "$BOTIFIED_INSTALL_TEST_ROOT" ] && [ ! -L "$BOTIFIED_INSTALL_TEST_ROOT" ] ||
		fail "invalid internal test root"
	command -v realpath >/dev/null 2>&1 || fail "realpath is required"
	install_test_root=$(realpath "$BOTIFIED_INSTALL_TEST_ROOT") || fail "invalid internal test root"
	case "$install_test_root" in
		/|'') fail "invalid internal test root" ;;
		/*) ;;
		*) fail "invalid internal test root" ;;
	esac
	[ -d "$install_test_root" ] && [ ! -L "$install_test_root" ] ||
		fail "invalid internal test root"
}

read_user_identity() {
	[ "${HOME+x}" = x ] && [ -n "$HOME" ] || fail "HOME is required for user scope"
	command -v id >/dev/null 2>&1 || fail "id is required"
	command -v getent >/dev/null 2>&1 || fail "getent is required"
	current_uid=$(id -u) || fail "could not determine current UID"
	is_decimal "$current_uid" || fail "could not determine current UID"
	[ "$current_uid" -ne 0 ] || fail "user scope must not run as root"
	passwd_entry=$(getent passwd "$current_uid") || fail "could not resolve current user through NSS"
	IFS=: read -r current_name passwd_marker passwd_uid current_gid gecos_field nss_home login_shell <<EOF
$passwd_entry
EOF
	[ -n "$current_name" ] && [ "$passwd_uid" = "$current_uid" ] ||
		fail "could not resolve current user through NSS"
	is_decimal "$current_gid" || fail "could not resolve current user through NSS"
	case "$nss_home" in
		/*) ;;
		*) fail "NSS home must be an existing absolute directory" ;;
	esac
	[ -d "$nss_home" ] || fail "NSS home must be an existing absolute directory"
	command -v realpath >/dev/null 2>&1 || fail "realpath is required"
	canonical_nss_home=$(realpath "$nss_home") || fail "could not canonicalize NSS home"
	canonical_ambient_home=$(realpath "$HOME") || fail "could not canonicalize HOME"
	[ "$canonical_nss_home" = "$canonical_ambient_home" ] ||
		fail "HOME does not match the current user's NSS home"
}

set_scoped_layout() {
	if [ "$managed_scope" = user ]; then
		scope_home=$canonical_nss_home
		scope_binary="$scope_home/.local/bin/botified"
		scope_tui="$scope_home/.local/bin/botified-tui"
		scope_share="$scope_home/.local/share/botified"
		scope_docs="$scope_home/.local/share/doc/botified"
		scope_config="$scope_home/.config/botified/botified.yaml"
		scope_env="$scope_home/.config/botified/botified.env"
		scope_workspace="$scope_home/.local/share/botified/workspace"
		scope_unit="$scope_home/.config/systemd/user/botified.service"
		scope_unit_source=botified.user.service
		scope_boot_target=default.target
	else
		scope_home=/var/lib/botified
		scope_binary=/usr/local/bin/botified
		scope_tui=/usr/local/bin/botified-tui
		scope_share=/usr/local/share/botified
		scope_docs=/usr/local/share/doc/botified
		scope_config=/etc/botified/botified.yaml
		scope_env=/etc/botified/botified.env
		scope_workspace=/var/lib/botified/workspace
		scope_unit=/etc/systemd/system/botified.service
		scope_unit_source=botified.system.service
		scope_boot_target=multi-user.target
	fi
	scope_agents="$scope_home/.agents"
	scope_binary_fs=$(scoped_fs_path "$scope_binary")
	scope_tui_fs=$(scoped_fs_path "$scope_tui")
	scope_home_fs=$(scoped_fs_path "$scope_home")
	scope_share_fs=$(scoped_fs_path "$scope_share")
	scope_docs_fs=$(scoped_fs_path "$scope_docs")
	scope_config_fs=$(scoped_fs_path "$scope_config")
	scope_env_fs=$(scoped_fs_path "$scope_env")
	scope_workspace_fs=$(scoped_fs_path "$scope_workspace")
	scope_unit_fs=$(scoped_fs_path "$scope_unit")
}

scoped_preflight() {
	[ "$install_dir_is_set" != x ] && [ "$share_dir_is_set" != x ] &&
		[ "$doc_dir_is_set" != x ] && [ "$prefix_is_set" != x ] ||
		fail "managed scope does not accept install path overrides"
	validate_test_root
	[ -x /usr/bin/env ] && [ -f /usr/bin/env ] || fail "/usr/bin/env is required"
	command -v systemctl >/dev/null 2>&1 || fail "systemctl is required"
	if [ "$managed_scope" = user ]; then
		read_user_identity
		command -v loginctl >/dev/null 2>&1 || fail "loginctl is required"
		scoped_systemctl show-environment >/dev/null 2>&1 || fail "user systemd manager is unavailable"
		linger=$(loginctl show-user "$current_name" -p Linger --value) ||
			fail "could not read Linger for $current_name"
		if [ "$linger" != yes ]; then
			printf '%s\n' "botified install: user scope requires pre-existing Linger=yes" >&2
			printf 'sudo loginctl enable-linger %s\n' "$current_name" >&2
			exit 1
		fi
	else
		command -v id >/dev/null 2>&1 || fail "id is required"
		current_uid=$(id -u) || fail "could not determine current UID"
		[ "$current_uid" = 0 ] || fail "system scope must run as root"
		scoped_systemctl show --property=Version --value >/dev/null 2>&1 ||
			fail "system systemd manager is unavailable"
	fi
	set_scoped_layout
	if [ -e "$scope_unit_fs" ] || [ -L "$scope_unit_fs" ]; then
		has_managed_unit_marker "$scope_unit_fs" ||
			fail "refusing to replace unmanaged canonical unit: $scope_unit"
	fi
}

validate_scoped_bundle() {
	[ -x "$bundle_dir/bin/botified" ] || fail "bundle missing executable bin/botified"
	[ -x "$bundle_dir/bin/botified-tui" ] || fail "bundle missing executable bin/botified-tui"
	[ -d "$bundle_dir/share/doc/botified" ] || fail "bundle missing share/doc/botified"
	for skill_name in botified-agent-guide botified-skill-creator; do
		[ -d "$bundle_dir/share/botified/skills/$skill_name" ] ||
			fail "bundle missing Core skill $skill_name"
	done
	for unit_name in botified.user.service botified.system.service; do
		unit_path="$bundle_dir/share/botified/systemd/$unit_name"
		has_managed_unit_marker "$unit_path" ||
			fail "bundle contains invalid managed systemd unit $unit_name"
	done
	"$bundle_dir/bin/botified" setup --help --neutral --config / --workspace / >/dev/null 2>&1 ||
		fail "bundle does not support neutral setup"
	"$bundle_dir/bin/botified" config check --config / --help >/dev/null 2>&1 ||
		fail "bundle does not support config check"
	"$bundle_dir/bin/botified" health check --config / --expected-pid 1 --help >/dev/null 2>&1 ||
		fail "bundle does not support health check"
}

resolve_system_account() {
	command -v getent >/dev/null 2>&1 || fail "getent is required"
	botified_passwd=$(getent passwd botified 2>/dev/null || true)
	botified_group=$(getent group botified 2>/dev/null || true)
	if [ -z "$botified_passwd" ] && [ -z "$botified_group" ]; then
		command -v useradd >/dev/null 2>&1 || fail "useradd is required to create botified"
		useradd -r -U -d /var/lib/botified -m -s /usr/sbin/nologin botified ||
			fail "could not create system account botified"
		botified_uid=$(id -u botified) || fail "created botified account is not resolvable"
		botified_gid=$(id -g botified) || fail "created botified group is not resolvable"
		is_decimal "$botified_uid" && is_decimal "$botified_gid" ||
			fail "invalid created botified system account"
		[ "$botified_uid" -ne 0 ] && [ "$botified_gid" -ne 0 ] ||
			fail "invalid created botified system account"
		return
	elif [ -z "$botified_passwd" ] || [ -z "$botified_group" ]; then
		fail "botified user/group conflict"
	fi
	IFS=: read -r account_name account_marker botified_uid botified_gid account_gecos account_home account_shell <<EOF
$botified_passwd
EOF
	IFS=: read -r group_name group_marker botified_group_gid group_members <<EOF
$botified_group
EOF
	[ "$account_name" = botified ] && [ "$group_name" = botified ] || fail "invalid botified system account"
	is_decimal "$botified_uid" && is_decimal "$botified_gid" && is_decimal "$botified_group_gid" ||
		fail "invalid botified system account"
	[ "$botified_uid" -ne 0 ] && [ "$botified_gid" -ne 0 ] &&
		[ "$botified_gid" = "$botified_group_gid" ] && [ "$account_home" = /var/lib/botified ] ||
		fail "invalid botified system account"
}

prepare_scoped_config() {
	config_parent_fs=${scope_config_fs%/*}
	env_parent_fs=${scope_env_fs%/*}
	if [ -e "$scope_env_fs" ] || [ -L "$scope_env_fs" ]; then
		[ -f "$scope_env_fs" ] && [ ! -L "$scope_env_fs" ] ||
			fail "existing process environment must be a regular non-symlink file: $scope_env"
	fi
	if [ -e "$scope_config_fs" ] || [ -L "$scope_config_fs" ]; then
		[ -f "$scope_config_fs" ] && [ ! -L "$scope_config_fs" ] ||
			fail "existing config must be a regular non-symlink file: $scope_config"
	fi
	mkdir -p "$config_parent_fs" "$env_parent_fs" "$scope_workspace_fs"
	if [ ! -e "$scope_env_fs" ]; then
		: > "$scope_env_fs"
	fi
	if [ "$managed_scope" = user ]; then
		chmod 0700 "$config_parent_fs"
		chmod 0600 "$scope_env_fs"
	else
		mkdir -p "$scope_home_fs"
		chmod 0750 "$scope_home_fs" "$config_parent_fs" "$scope_workspace_fs"
		chmod 0640 "$scope_env_fs"
		chown root:botified "$config_parent_fs" "$scope_env_fs"
		chown botified:botified "$scope_home_fs"
		chown botified:botified "$scope_workspace_fs"
	fi
	if [ ! -e "$scope_config_fs" ]; then
		"$bundle_dir/bin/botified" setup --neutral --config "$scope_config" \
			--workspace "$scope_workspace" || fail "neutral setup failed"
	fi
	[ -f "$scope_config_fs" ] && [ ! -L "$scope_config_fs" ] ||
		fail "neutral setup did not create a regular non-symlink config: $scope_config"
	"$bundle_dir/bin/botified" config check --config "$scope_config" || fail "config check failed"
	if [ "$managed_scope" = user ]; then
		chmod 0600 "$scope_config_fs"
	else
		chmod 0640 "$scope_config_fs"
		chown root:botified "$scope_config_fs"
	fi
}

place_scoped_file() {
	place_source=$1
	place_target=$2
	place_mode=$3
	place_parent=${place_target%/*}
	place_temp="$place_parent/.${place_target##*/}.new.$$"
	mkdir -p "$place_parent"
	rm -f "$place_temp"
	if command -v install >/dev/null 2>&1; then
		install -m "$place_mode" "$place_source" "$place_temp"
	else
		cp "$place_source" "$place_temp"
		chmod "$place_mode" "$place_temp"
	fi
	mv "$place_temp" "$place_target"
}

replace_scoped_tree() {
	tree_source=$1
	tree_target=$2
	tree_parent=${tree_target%/*}
	tree_name=${tree_target##*/}
	tree_new="$tree_parent/.$tree_name.new.$$"
	tree_old="$tree_parent/.$tree_name.old.$$"
	mkdir -p "$tree_parent"
	rm -rf "$tree_new" "$tree_old"
	mkdir -p "$tree_new"
	cp -R "$tree_source/." "$tree_new/"
	chmod -R a-x,u=rwX,go=rX "$tree_new"
	if [ -e "$tree_target" ] || [ -L "$tree_target" ]; then
		mv "$tree_target" "$tree_old"
	fi
	mv "$tree_new" "$tree_target"
	rm -rf "$tree_old"
}

commit_scoped_release() {
	mkdir -p "$scope_share_fs" "$scope_share_fs/skills" "$scope_share_fs/systemd"
	chmod 0755 "$scope_share_fs" "$scope_share_fs/skills" "$scope_share_fs/systemd"
	place_scoped_file "$bundle_dir/bin/botified" "$scope_binary_fs" 0755
	place_scoped_file "$bundle_dir/bin/botified-tui" "$scope_tui_fs" 0755
	unit_share_fs="$scope_share_fs/systemd"
	place_scoped_file "$bundle_dir/share/botified/systemd/botified.user.service" \
		"$unit_share_fs/botified.user.service" 0644
	place_scoped_file "$bundle_dir/share/botified/systemd/botified.system.service" \
		"$unit_share_fs/botified.system.service" 0644
	place_scoped_file "$bundle_dir/share/botified/systemd/$scope_unit_source" "$scope_unit_fs" 0644
	for skill_name in botified-agent-guide botified-skill-creator; do
		replace_scoped_tree "$bundle_dir/share/botified/skills/$skill_name" \
			"$scope_share_fs/skills/$skill_name"
	done
	replace_scoped_tree "$bundle_dir/share/doc/botified" "$scope_docs_fs"
}

verify_scoped_runtime() {
	enabled_state=$(scoped_systemctl is-enabled botified.service) || fail "botified.service is not enabled"
	[ "$enabled_state" = enabled ] || fail "botified.service is not exactly enabled"
	active_state=$(scoped_systemctl is-active botified.service) || fail "botified.service is not active"
	[ "$active_state" = active ] || fail "botified.service is not exactly active"
	main_pid=$(scoped_systemctl show -p MainPID --value botified.service) ||
		fail "could not read botified.service MainPID"
	is_decimal "$main_pid" && [ "$main_pid" -ne 0 ] || fail "botified.service has no stable MainPID"
	command -v readlink >/dev/null 2>&1 || fail "readlink is required"
	process_binary=$(readlink -f "/proc/$main_pid/exe") || fail "could not resolve botified.service executable"
	[ "$process_binary" = "$scope_binary" ] || fail "botified.service is running the wrong executable"
	"$scope_binary_fs" health check --config "$scope_config" --expected-pid "$main_pid" ||
		fail "botified health check failed"
	after_pid=$(scoped_systemctl show -p MainPID --value botified.service) ||
		fail "could not reread botified.service MainPID"
	[ "$after_pid" = "$main_pid" ] || fail "botified.service restarted during health check"
	process_binary=$(readlink -f "/proc/$after_pid/exe") || fail "could not re-resolve botified.service executable"
	[ "$process_binary" = "$scope_binary" ] || fail "botified.service executable changed during health check"
	if [ "$managed_scope" = user ]; then
		linger=$(loginctl show-user "$current_name" -p Linger --value) ||
			fail "could not reread Linger for $current_name"
		[ "$linger" = yes ] || fail "Linger changed during installation"
	else
		command -v stat >/dev/null 2>&1 || fail "stat is required"
		process_ids=$(stat -c %u:%g "/proc/$after_pid") || fail "could not read botified.service process identity"
		[ "$process_ids" = "$botified_uid:$botified_gid" ] ||
			fail "botified.service is not running as botified"
	fi
}

install_scoped() {
	scoped_preflight
	os=$(uname -s 2>/dev/null || true)
	arch=$(uname -m 2>/dev/null || true)
	case "$os:$arch" in
		Linux:x86_64) asset=botified-core-linux-x86_64-musl.tar.gz ;;
		Linux:aarch64) asset=botified-core-linux-aarch64-gnu.tar.gz ;;
		*) fail "unsupported platform: ${os:-unknown} ${arch:-unknown}; supported: Linux x86_64/aarch64" ;;
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
	log "Installing botified from $repo ($version) for $managed_scope scope"
	log "Detected core bundle: $asset"
	download "$base_url/$asset" "$tmpdir/$asset"
	download "$base_url/SHA256SUMS" "$tmpdir/SHA256SUMS"
	need_checksum
	verify_checksum "$tmpdir/SHA256SUMS" "$tmpdir/$asset" "$asset"
	log "Checksum verified."
	bundle_dir="$tmpdir/bundle"
	mkdir -p "$bundle_dir"
	tar -xzf "$tmpdir/$asset" -C "$bundle_dir"
	validate_scoped_bundle
	if [ "$managed_scope" = system ]; then
		resolve_system_account
	fi
	prepare_scoped_config
	commit_scoped_release
	scoped_systemctl daemon-reload || fail "systemd daemon-reload failed"
	scoped_systemctl enable botified.service || fail "could not enable botified.service"
	scoped_systemctl restart botified.service || fail "could not restart botified.service"
	verify_scoped_runtime
	log "Installed managed $managed_scope service: botified.service"
	log "Binary: $scope_binary"
	log "Config: $scope_config"
	log "Environment: $scope_env"
	log "Agent root: $scope_agents"
	log "Unit: $scope_unit"
	log "Boot target: $scope_boot_target"
	log "Enabled: $enabled_state"
	log "Active: $active_state"
	log "MainPID: $main_pid"
	log "Health: verified above by $scope_binary health check"
	if [ "$managed_scope" = user ]; then
		log "Linger: $linger"
		log "Inspect with:"
		log "  systemctl --user cat botified.service"
		log "  systemctl --user status botified.service"
		log "  systemctl --user restart botified.service"
		log "  journalctl --user -u botified.service -n 100 --no-pager"
	else
		log "Inspect with:"
		log "  systemctl cat botified.service"
		log "  systemctl status botified.service"
		log "  systemctl restart botified.service"
		log "  journalctl -u botified.service -n 100 --no-pager"
	fi
	log "  $scope_binary config check --config $scope_config"
	log "  $scope_binary health check --config $scope_config"
	log "Provider configuration is intentionally left for the administrator."
}

managed_scope=
case "$#" in
	0) ;;
	2)
		[ "$1" = --scope ] || fail "usage: install.sh [--scope user|system]"
		case "$2" in
			user|system) managed_scope=$2 ;;
			*) fail "usage: install.sh [--scope user|system]" ;;
		esac
		;;
	*) fail "usage: install.sh [--scope user|system]" ;;
esac

if [ -n "$managed_scope" ]; then
	install_scoped
	exit 0
fi

install_dir="${BOTIFIED_INSTALL_DIR:-$HOME/.local/bin}"
share_dir="${BOTIFIED_SHARE_DIR:-$HOME/.local/share/botified}"
doc_dir="${BOTIFIED_DOC_DIR:-$HOME/.local/share/doc/botified}"

os=$(uname -s 2>/dev/null || true)
arch=$(uname -m 2>/dev/null || true)

case "$os:$arch" in
	Linux:x86_64)
		asset=botified-core-linux-x86_64-musl.tar.gz
		;;
	Linux:aarch64)
		asset=botified-core-linux-aarch64-gnu.tar.gz
		;;
	*)
		fail "unsupported platform: ${os:-unknown} ${arch:-unknown}; supported: Linux x86_64/aarch64"
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

need_checksum
verify_checksum "$tmpdir/SHA256SUMS" "$tmpdir/$asset" "$asset"
log "Checksum verified."

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
if [ -x "$install_dir/botified-claw-gateway" ] || command -v botified-claw-gateway >/dev/null 2>&1; then
	warn "botified-claw-gateway is installed but was not upgraded; run install-gateway.sh with BOTIFIED_VERSION=$version"
fi

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
log "  botified setup --mock --config botified.mock.yaml"
log "  export BOTIFIED_SERVICE_KEY=dev"
log "  botified serve --mock-provider --config botified.mock.yaml"
log "  botified-tui --base-url http://127.0.0.1:17777 --service-key-env BOTIFIED_SERVICE_KEY"
log ""
log "For a real config, run: botified setup --config botified.yaml"
