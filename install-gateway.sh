#!/bin/sh
set -eu

repo="${BOTIFIED_RELEASES_REPO:-lzjever/botified-releases}"
version="${BOTIFIED_VERSION:-latest}"
asset=botified-claw-gateway-companion.tar.gz
install_dir_is_set=${BOTIFIED_INSTALL_DIR+x}
share_dir_is_set=${BOTIFIED_SHARE_DIR+x}
doc_dir_is_set=${BOTIFIED_DOC_DIR+x}
prefix_is_set=${BOTIFIED_PREFIX+x}
managed_unit_marker='# Managed by the Botified installer. Inspect and operate with systemd tools.'
usage_line='usage: install-gateway.sh --scope user|system [--channel <channel>[,<channel>...]]'

log() {
	printf '%s\n' "$*"
}

fail() {
	printf 'botified gateway install: %s\n' "$*" >&2
	exit 1
}

usage_fail() {
	printf 'botified gateway install: %s\n' "$*" >&2
	printf '%s\n' "$usage_line" >&2
	exit 2
}

refuse() {
	printf 'botified gateway install: %s\n' "$*" >&2
	exit 3
}

proof_fail() {
	printf 'botified gateway install: %s\n' "$*" >&2
	exit 4
}

interactive_fail() {
	printf 'botified gateway install: %s\n' "$*" >&2
	exit 5
}

need_downloader() {
	if [ -n "${BOTIFIED_ASSET_DIR:-}" ]; then
		return
	fi
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

need_node() {
	command -v node >/dev/null 2>&1 || fail "Node >=22.19 <23 is required"
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
	if [ -n "${BOTIFIED_ASSET_DIR:-}" ]; then
		asset_name=${url##*/}
		[ -f "$BOTIFIED_ASSET_DIR/$asset_name" ] ||
			fail "BOTIFIED_ASSET_DIR is set but $asset_name is missing; populate the asset directory or unset BOTIFIED_ASSET_DIR to download"
		cp "$BOTIFIED_ASSET_DIR/$asset_name" "$out"
		return
	fi
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

interactive_ask() {
	ask_prompt=$1
	ask_pattern=$2
	ask_hint=$3
	ask_tty=${BOTIFIED_INSTALL_TEST_TTY:-/dev/tty}
	[ -e "$ask_tty" ] ||
		interactive_fail "interactive input requires $ask_tty; pass --scope explicitly"
	ask_attempt=0
	while :; do
		ask_attempt=$((ask_attempt + 1))
		printf '%s' "$ask_prompt" >&2
		ask_answer=
		if IFS= read -r ask_answer < "$ask_tty" 2>/dev/null &&
			printf '%s\n' "$ask_answer" | grep -Eq -- "$ask_pattern"
		then
			printf '%s\n' "$ask_answer"
			return 0
		fi
		[ "$ask_attempt" -lt 3 ] ||
			interactive_fail "no valid answer after 3 attempts; $ask_hint"
	done
}

channel_list=

add_channel() {
	case ",$channel_list," in
		*",$1,"*) return 0 ;;
	esac
	channel_list="${channel_list:+$channel_list,}$1"
}

parse_channel_spec() {
	remainder=$1
	while [ -n "$remainder" ]; do
		case "$remainder" in
			*,*)
				channel_name=${remainder%%,*}
				remainder=${remainder#*,}
				;;
			*)
				channel_name=$remainder
				remainder=
				;;
		esac
		case "$channel_name" in
			weixin|feishu|matrix) ;;
			'') usage_fail "channel list must not be empty" ;;
			*) usage_fail "unknown channel: $channel_name; valid channels are weixin, feishu, matrix" ;;
		esac
		add_channel "$channel_name"
	done
	[ -n "$channel_list" ] || usage_fail "channel list must not be empty"
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
	[ "$managed_unit_first_line" = "$managed_unit_marker" ]
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

validate_system_account() {
	command -v getent >/dev/null 2>&1 || fail "getent is required"
	botified_passwd=$(getent passwd botified 2>/dev/null || true)
	botified_group=$(getent group botified 2>/dev/null || true)
	[ -n "$botified_passwd" ] && [ -n "$botified_group" ] ||
		fail "botified system account is missing; reinstall the Core system service first"
	IFS=: read -r account_name account_marker botified_uid botified_gid account_gecos account_home account_shell <<EOF
$botified_passwd
EOF
	IFS=: read -r group_name group_marker botified_group_gid group_members <<EOF
$botified_group
EOF
	[ "$account_name" = botified ] && [ "$group_name" = botified ] ||
		fail "invalid botified system account"
	is_decimal "$botified_uid" && is_decimal "$botified_gid" &&
		is_decimal "$botified_group_gid" ||
		fail "invalid botified system account"
	[ "$botified_uid" -ne 0 ] && [ "$botified_gid" -ne 0 ] &&
		[ "$botified_gid" = "$botified_group_gid" ] &&
		[ "$account_home" = /var/lib/botified ] ||
		fail "invalid botified system account"
}

set_scoped_layout() {
	if [ "$managed_scope" = user ]; then
		scope_home=$canonical_nss_home
		gateway_binary="$scope_home/.local/bin/botified-claw-gateway"
		runtime_tree="$scope_home/.local/share/botified/gateway"
		docs_tree="$scope_home/.local/share/doc/botified-claw-gateway"
		examples_tree="$scope_home/.local/share/botified-claw-gateway/examples"
		gateway_config_dir="$scope_home/.config/botified/gateway"
		gateway_unit_dir="$scope_home/.config/systemd/user"
		data_root="$scope_home/.local/state/botified/gateway"
		core_unit="$scope_home/.config/systemd/user/botified.service"
	else
		gateway_binary=/usr/local/bin/botified-claw-gateway
		runtime_tree=/usr/local/share/botified/gateway
		docs_tree=/usr/local/share/doc/botified-claw-gateway
		examples_tree=/usr/local/share/botified-claw-gateway/examples
		gateway_config_dir=/etc/botified/gateway
		gateway_unit_dir=/etc/systemd/system
		data_root=/var/lib/botified/gateway
		core_unit=/etc/systemd/system/botified.service
	fi
	gateway_binary_fs=$(scoped_fs_path "$gateway_binary")
	runtime_tree_fs=$(scoped_fs_path "$runtime_tree")
	docs_tree_fs=$(scoped_fs_path "$docs_tree")
	examples_tree_fs=$(scoped_fs_path "$examples_tree")
	gateway_config_dir_fs=$(scoped_fs_path "$gateway_config_dir")
	gateway_unit_dir_fs=$(scoped_fs_path "$gateway_unit_dir")
	core_unit_fs=$(scoped_fs_path "$core_unit")
}

channel_config_path() {
	printf '%s/%s-gateway.yaml\n' "$gateway_config_dir" "$1"
}

channel_env_path() {
	printf '%s/%s-gateway.env\n' "$gateway_config_dir" "$1"
}

channel_unit_path() {
	printf '%s/botified-claw-gateway-%s.service\n' "$gateway_unit_dir" "$1"
}

channel_unit_fs() {
	printf '%s/botified-claw-gateway-%s.service\n' "$gateway_unit_dir_fs" "$1"
}

channel_data_dir() {
	printf '%s/%s/\n' "$data_root" "$1"
}

channel_log_dir() {
	printf '%s/%s/logs/\n' "$data_root" "$1"
}

channel_cli_js_path() {
	printf '%s/dist/src/cli.js\n' "$runtime_tree"
}

determine_channel_lifecycle() {
	lifecycle_channel=$1
	lifecycle_unit_fs=$(channel_unit_fs "$lifecycle_channel")
	lifecycle_branch=activate
	if [ -e "$lifecycle_unit_fs" ] || [ -L "$lifecycle_unit_fs" ]; then
		has_managed_unit_marker "$lifecycle_unit_fs" ||
			refuse "refusing to replace unmanaged gateway unit: $(channel_unit_path "$lifecycle_channel")"
		enabled_state=$(scoped_systemctl is-enabled "botified-claw-gateway-$lifecycle_channel.service") ||
			enabled_state=
		if [ "$enabled_state" = enabled ]; then
			lifecycle_branch=upgrade
		else
			active_state=$(scoped_systemctl is-active "botified-claw-gateway-$lifecycle_channel.service") ||
				active_state=
			if [ "$active_state" = active ]; then
				refuse "refusing to take over an active but not enabled gateway unit: $(channel_unit_path "$lifecycle_channel"); stop it or enable it before installing"
			fi
		fi
	fi
	case ",$lifecycle_channels," in
		*",$lifecycle_channel"*) ;;
		*) lifecycle_channels="${lifecycle_channels:+$lifecycle_channels,}$lifecycle_channel" ;;
	esac
	lifecycle_branches="${lifecycle_branches:+$lifecycle_branches,}$lifecycle_branch"
}

branch_for_channel() {
	branch_for_channel_name=$1
	branch_for_channel_position=0
	branch_for_channel_index=0
	IFS=,
	for branch_for_channel_entry in $lifecycle_channels; do
		branch_for_channel_index=$((branch_for_channel_index + 1))
		if [ "$branch_for_channel_entry" = "$branch_for_channel_name" ]; then
			branch_for_channel_position=$branch_for_channel_index
		fi
	done
	branch_for_channel_count=0
	IFS=,
	for branch_for_channel_entry in $lifecycle_branches; do
		branch_for_channel_count=$((branch_for_channel_count + 1))
		if [ "$branch_for_channel_count" = "$branch_for_channel_position" ]; then
			printf '%s\n' "$branch_for_channel_entry"
			return 0
		fi
	done
	return 1
}

scoped_preflight() {
	[ "$install_dir_is_set" != x ] && [ "$share_dir_is_set" != x ] &&
		[ "$doc_dir_is_set" != x ] && [ "$prefix_is_set" != x ] ||
		fail "managed scope does not accept install path overrides"
	validate_test_root
	[ -x /usr/bin/env ] && [ -f /usr/bin/env ] || fail "/usr/bin/env is required"
	command -v systemctl >/dev/null 2>&1 || fail "systemctl is required"
	command -v sed >/dev/null 2>&1 || fail "sed is required"
	command -v tr >/dev/null 2>&1 || fail "tr is required"
	need_node
	if [ "$managed_scope" = user ]; then
		read_user_identity
		command -v loginctl >/dev/null 2>&1 || fail "loginctl is required"
		scoped_systemctl show-environment >/dev/null 2>&1 || fail "user systemd manager is unavailable"
		linger=$(loginctl show-user "$current_name" -p Linger --value) ||
			fail "could not read Linger for $current_name"
		if [ "$linger" != yes ]; then
			printf '%s\n' "botified gateway install: user scope requires pre-existing Linger=yes" >&2
			printf 'sudo loginctl enable-linger %s\n' "$current_name" >&2
			exit 1
		fi
	else
		command -v id >/dev/null 2>&1 || fail "id is required"
		current_uid=$(id -u) || fail "could not determine current UID"
		[ "$current_uid" = 0 ] || fail "system scope must run as root"
		scoped_systemctl show --property=Version --value >/dev/null 2>&1 ||
			fail "system systemd manager is unavailable"
		validate_system_account
		command -v stat >/dev/null 2>&1 || fail "stat is required"
	fi
	set_scoped_layout
	if [ ! -f "$core_unit_fs" ] || [ -L "$core_unit_fs" ]; then
		fail "Core is not installed as a managed $managed_scope service; run install.sh --scope $managed_scope first"
	fi
	has_managed_unit_marker "$core_unit_fs" ||
		fail "Core unit is not managed by the Botified installer: $core_unit; run install.sh --scope $managed_scope first"
	lifecycle_channels=
	lifecycle_branches=
	previous_ifs=$IFS
	IFS=,
	for preflight_channel in $channel_list; do
		determine_channel_lifecycle "$preflight_channel"
	done
	IFS=$previous_ifs
}

validate_scoped_bundle() {
	[ -x "$bundle_dir/bin/botified-claw-gateway" ] ||
		fail "bundle missing executable bin/botified-claw-gateway"
	[ -f "$bundle_dir/share/botified/gateway/dist/src/cli.js" ] ||
		fail "bundle missing share/botified/gateway/dist/src/cli.js"
	for staged_tree in \
		"$bundle_dir/share/botified/gateway" \
		"$bundle_dir/share/doc/botified-claw-gateway" \
		"$bundle_dir/share/botified-claw-gateway/examples"
	do
		[ -d "$staged_tree" ] || fail "bundle missing ${staged_tree#"$bundle_dir"/}"
	done
	unit_template="$bundle_dir/share/botified/gateway/systemd/botified-claw-gateway.$managed_scope.service.template"
	if [ ! -f "$unit_template" ] || [ -L "$unit_template" ]; then
		fail "bundle missing share/botified/gateway/systemd/botified-claw-gateway.$managed_scope.service.template; this companion release predates managed install; upgrade the gateway companion first"
	fi
	previous_ifs=$IFS
	IFS=,
	for capability_channel in $channel_list; do
		capability_skeleton="$bundle_dir/share/botified-claw-gateway/examples/channels/$capability_channel-gateway.yaml"
		if [ ! -f "$capability_skeleton" ] || [ -L "$capability_skeleton" ]; then
			fail "bundle missing share/botified-claw-gateway/examples/channels/$capability_channel-gateway.yaml; this companion release predates managed install; upgrade the gateway companion first"
		fi
	done
	IFS=$previous_ifs
	"$bundle_dir/bin/botified-claw-gateway" self-check ||
		fail "companion self-check failed"
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
	if [ "$managed_scope" = system ]; then
		docs_parent_fs=${docs_tree_fs%/*}
		if [ -e "$docs_parent_fs" ] || [ -L "$docs_parent_fs" ]; then
			[ -d "$docs_parent_fs" ] ||
				fail "managed docs parent is not a directory: ${docs_tree%/*}"
			chmod a+X "$docs_parent_fs"
		else
			mkdir -p "$docs_parent_fs"
			chmod 0755 "$docs_parent_fs"
		fi
	fi
	replace_scoped_tree "$bundle_dir/share/botified/gateway" "$runtime_tree_fs"
	replace_scoped_tree "$bundle_dir/share/doc/botified-claw-gateway" "$docs_tree_fs"
	replace_scoped_tree "$bundle_dir/share/botified-claw-gateway/examples" "$examples_tree_fs"
	place_scoped_file "$bundle_dir/bin/botified-claw-gateway" "$gateway_binary_fs" 0755
}

prepare_channel_files() {
	prepare_channel=$1
	prepare_config_fs=$(scoped_fs_path "$(channel_config_path "$prepare_channel")")
	prepare_env_fs=$(scoped_fs_path "$(channel_env_path "$prepare_channel")")
	prepare_skeleton="$bundle_dir/share/botified-claw-gateway/examples/channels/$prepare_channel-gateway.yaml"
	if [ -e "$prepare_config_fs" ] || [ -L "$prepare_config_fs" ]; then
		[ -f "$prepare_config_fs" ] && [ ! -L "$prepare_config_fs" ] ||
			fail "existing channel config must be a regular non-symlink file: $(channel_config_path "$prepare_channel")"
	fi
	if [ -e "$prepare_env_fs" ] || [ -L "$prepare_env_fs" ]; then
		[ -f "$prepare_env_fs" ] && [ ! -L "$prepare_env_fs" ] ||
			fail "existing channel environment must be a regular non-symlink file: $(channel_env_path "$prepare_channel")"
	fi
	mkdir -p "$gateway_config_dir_fs"
	if [ "$managed_scope" = user ]; then
		chmod 0700 "$gateway_config_dir_fs"
	else
		chmod 0750 "$gateway_config_dir_fs"
		chown root:botified "$gateway_config_dir_fs"
	fi
	if [ ! -e "$prepare_config_fs" ]; then
		prepare_rendered="$tmpdir/$prepare_channel-gateway.yaml"
		sed -e "s|__RUNTIME_DIR__|$(channel_data_dir "$prepare_channel")|g" \
			-e "s|__LOG_DIR__|$(channel_log_dir "$prepare_channel")|g" \
			"$prepare_skeleton" > "$prepare_rendered"
		if grep -q -e '__RUNTIME_DIR__' -e '__LOG_DIR__' "$prepare_rendered"; then
			fail "rendered channel skeleton still contains path placeholders: $prepare_channel"
		fi
		if [ "$managed_scope" = user ]; then
			place_scoped_file "$prepare_rendered" "$prepare_config_fs" 0600
		else
			place_scoped_file "$prepare_rendered" "$prepare_config_fs" 0640
			chown root:botified "$prepare_config_fs"
		fi
	fi
	if [ ! -e "$prepare_env_fs" ]; then
		prepare_env_rendered="$tmpdir/$prepare_channel-gateway.env"
		cat > "$prepare_env_rendered" <<EOF
# Fill before enabling botified-claw-gateway-$prepare_channel.service.
# The installer never reads, writes, or prints credentials.
# Interactive (all channels, same command shape; secrets are prompted with echo off):
#   botified-claw-gateway setup --channel $prepare_channel --config $gateway_config_dir/$prepare_channel-gateway.yaml
# Non-interactive flags for automation: see \`botified-claw-gateway setup --help\`
EOF
		if [ "$prepare_channel" = weixin ]; then
			printf '# Weixin only: after setup, run botified-claw-gateway login --config %s/%s-gateway.yaml\n' \
				"$gateway_config_dir" "$prepare_channel" >> "$prepare_env_rendered"
		fi
		if [ "$managed_scope" = user ]; then
			place_scoped_file "$prepare_env_rendered" "$prepare_env_fs" 0600
		else
			place_scoped_file "$prepare_env_rendered" "$prepare_env_fs" 0640
			chown root:botified "$prepare_env_fs"
		fi
	fi
}

render_channel_unit() {
	render_channel=$1
	render_template="$bundle_dir/share/botified/gateway/systemd/botified-claw-gateway.$managed_scope.service.template"
	render_target_fs=$(channel_unit_fs "$render_channel")
	render_staged="$tmpdir/botified-claw-gateway-$render_channel.service"
	sed "s/__CHANNEL__/$render_channel/g" "$render_template" > "$render_staged"
	IFS= read -r render_first_line < "$render_staged" ||
		fail "rendered gateway unit is empty"
	[ "$render_first_line" = "$managed_unit_marker" ] ||
		fail "rendered gateway unit lost the managed marker first line"
	if grep -q '__CHANNEL__' "$render_staged"; then
		fail "rendered gateway unit still contains __CHANNEL__: $render_channel"
	fi
	if [ -e "$render_target_fs" ] || [ -L "$render_target_fs" ]; then
		has_managed_unit_marker "$render_target_fs" ||
			refuse "refusing to replace unmanaged gateway unit: $(channel_unit_path "$render_channel")"
	fi
	place_scoped_file "$render_staged" "$render_target_fs" 0644
}

read_channel_cmdline() {
	cmdline_pid=$1
	cmdline_cli_js=$2
	cmdline_config=$3
	cmdline_attempts=0
	while :; do
		channel_cmdline=$(tr '\000' '\n' < "/proc/$cmdline_pid/cmdline") || channel_cmdline=""
		if [ -n "$channel_cmdline" ] &&
			printf '%s\n' "$channel_cmdline" | grep -qF -x -- "$cmdline_cli_js" &&
			printf '%s\n' "$channel_cmdline" | grep -qF -x -- "$cmdline_config"; then
			return 0
		fi
		cmdline_attempts=$((cmdline_attempts + 1))
		[ "$cmdline_attempts" -ge 5 ] && break
		sleep 1
	done
	proof_fail "could not read a matching /proc/$cmdline_pid/cmdline"
}

verify_channel_runtime() {
	verify_channel=$1
	verify_unit="botified-claw-gateway-$verify_channel.service"
	verify_config=$(channel_config_path "$verify_channel")
	verify_cli_js=$(channel_cli_js_path "$verify_channel")
	enabled_state=$(scoped_systemctl is-enabled "$verify_unit") ||
		proof_fail "$verify_unit is not enabled"
	[ "$enabled_state" = enabled ] || proof_fail "$verify_unit is not exactly enabled"
	active_state=$(scoped_systemctl is-active "$verify_unit") ||
		proof_fail "$verify_unit is not active"
	[ "$active_state" = active ] || proof_fail "$verify_unit is not exactly active"
	main_pid=$(scoped_systemctl show -p MainPID --value "$verify_unit") ||
		proof_fail "could not read $verify_unit MainPID"
	is_decimal "$main_pid" && [ "$main_pid" -ne 0 ] ||
		proof_fail "$verify_unit has no stable MainPID"
	read_channel_cmdline "$main_pid" "$verify_cli_js" "$verify_config" ||
		proof_fail "could not read the $verify_unit process command line"
	sleep 5
	after_pid=$(scoped_systemctl show -p MainPID --value "$verify_unit") ||
		proof_fail "could not reread $verify_unit MainPID"
	[ "$after_pid" = "$main_pid" ] ||
		proof_fail "$verify_unit restarted during runtime verification"
	read_channel_cmdline "$after_pid" "$verify_cli_js" "$verify_config" ||
		proof_fail "could not reread the $verify_unit process command line"
	if [ "$managed_scope" = system ]; then
		command -v stat >/dev/null 2>&1 || fail "stat is required"
		process_ids=$(stat -c %u:%g "/proc/$after_pid") ||
			proof_fail "could not read $verify_unit process identity"
		[ "$process_ids" = "$botified_uid:$botified_gid" ] ||
			proof_fail "$verify_unit is not running as botified"
	fi
}

print_channel_activation() {
	activation_channel=$1
	activation_config=$(channel_config_path "$activation_channel")
	activation_env=$(channel_env_path "$activation_channel")
	activation_unit="botified-claw-gateway-$activation_channel.service"
	log ""
	log "Channel $activation_channel is installed but not activated:"
	log "  1. Fill credentials in: $activation_env"
	log "  2. botified-claw-gateway setup --channel $activation_channel --config $activation_config"
	if [ "$activation_channel" = weixin ]; then
		log "     botified-claw-gateway login --config $activation_config"
	fi
	if [ "$managed_scope" = user ]; then
		log "  3. systemctl --user enable --now $activation_unit"
	else
		log "  3. systemctl enable --now $activation_unit"
	fi
}

install_gateway() {
	scoped_preflight
	need_downloader
	need_tar
	tmpdir=$(mktemp -d 2>/dev/null || mktemp -d -t botified-gateway-install)
	trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM
	if [ "$version" = latest ]; then
		base_url="https://github.com/$repo/releases/latest/download"
	else
		base_url="https://github.com/$repo/releases/download/$version"
	fi
	log "Installing botified-claw-gateway from $repo ($version) for $managed_scope scope"
	log "Channels: $channel_list"
	download "$base_url/$asset" "$tmpdir/$asset" || fail "could not download $asset"
	download "$base_url/SHA256SUMS" "$tmpdir/SHA256SUMS" || fail "could not download SHA256SUMS"
	need_checksum
	verify_checksum "$tmpdir/SHA256SUMS" "$tmpdir/$asset" "$asset"
	log "Checksum verified."
	bundle_dir="$tmpdir/bundle"
	mkdir -p "$bundle_dir"
	tar -xzf "$tmpdir/$asset" -C "$bundle_dir" || fail "could not extract $asset"
	validate_scoped_bundle
	commit_scoped_release
	previous_ifs=$IFS
	IFS=,
	for install_channel in $channel_list; do
		prepare_channel_files "$install_channel"
		render_channel_unit "$install_channel"
		scoped_systemctl daemon-reload || fail "systemd daemon-reload failed"
		channel_branch=$(branch_for_channel "$install_channel") ||
			fail "internal error: no lifecycle branch for $install_channel"
		if [ "$channel_branch" = upgrade ]; then
			scoped_systemctl restart "botified-claw-gateway-$install_channel.service" ||
				fail "could not restart botified-claw-gateway-$install_channel.service"
			verify_channel_runtime "$install_channel"
			log "Upgraded and restarted managed gateway channel: botified-claw-gateway-$install_channel.service"
			log "  Enabled: $enabled_state"
			log "  Active: $active_state"
			log "  MainPID: $main_pid"
		else
			print_channel_activation "$install_channel"
		fi
	done
	IFS=$previous_ifs
	log ""
	log "Installed gateway wrapper: $gateway_binary"
	log "Installed runtime tree: $runtime_tree"
	log "Installed docs: $docs_tree"
	log "Installed examples: $examples_tree"
	log "Unit template source: $runtime_tree/systemd/botified-claw-gateway.$managed_scope.service.template"
	gateway_bin_dir=$(dirname "$gateway_binary")
	case ":$PATH:" in
		*":$gateway_bin_dir:"*) ;;
		*)
			log ""
			log "Add this to your shell startup file so your shell can find botified-claw-gateway:"
			log "  export PATH=\"$gateway_bin_dir:\$PATH\""
			;;
	esac
}

argument_count=$#
managed_scope=
channel_input=
channel_given=0

while [ "$#" -gt 0 ]; do
	case "$1" in
		--scope)
			[ "$#" -ge 2 ] || usage_fail "missing value for --scope"
			[ -z "$managed_scope" ] || usage_fail "--scope may only be given once"
			case "$2" in
				user|system) managed_scope=$2 ;;
				*) usage_fail "unknown scope: $2" ;;
			esac
			shift 2
			;;
		--channel)
			[ "$#" -ge 2 ] || usage_fail "missing value for --channel"
			channel_input="${channel_input:+$channel_input,}$2"
			channel_given=1
			shift 2
			;;
		*)
			usage_fail "unknown argument: $1"
			;;
	esac
done

if [ "$argument_count" -eq 0 ]; then
	scope_answer=$(interactive_ask \
		'Gateway install scope (user|system): ' '^(user|system)$' \
		'pass --scope explicitly') ||
		exit 5
	case "$scope_answer" in
		user|system) managed_scope=$scope_answer ;;
		*) usage_fail "unknown scope: $scope_answer" ;;
	esac
	channel_answer=$(interactive_ask \
		'Gateway channels, comma separated (weixin|feishu|matrix; empty for weixin): ' \
		'^$|^(weixin|feishu|matrix)(,(weixin|feishu|matrix))*$' \
		'answer a comma separated channel list (weixin, feishu, matrix), or pass --scope and --channel explicitly') ||
		exit 5
	channel_input=$channel_answer
fi

[ -n "$managed_scope" ] || usage_fail "--scope is required"
if [ -z "$channel_input" ]; then
	if [ "$channel_given" -eq 1 ]; then
		usage_fail "channel list must not be empty"
	fi
	channel_input=weixin
fi
parse_channel_spec "$channel_input"

install_gateway
