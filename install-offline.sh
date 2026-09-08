#!/bin/sh
set -eu

usage_line='usage: install-offline.sh [--core-only | --scope user|system [--gateway [--channel <channel>[,<channel>...]]]] [--bundle-dir <dir>]'

log() {
	printf '%s\n' "$*"
}

fail() {
	printf 'botified offline install: %s\n' "$*" >&2
	exit 1
}

usage_fail() {
	printf 'botified offline install: %s\n' "$*" >&2
	printf '%s\n' "$usage_line" >&2
	exit 2
}

interactive_fail() {
	printf 'botified offline install: %s\n' "$*" >&2
	exit 5
}

interactive_ask() {
	ask_prompt=$1
	ask_pattern=$2
	ask_hint=$3
	ask_tty=${BOTIFIED_INSTALL_TEST_TTY:-/dev/tty}
	[ -e "$ask_tty" ] ||
		interactive_fail "interactive input requires $ask_tty; pass --core-only or --scope explicitly"
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

validate_bundle() {
	os=$(uname -s 2>/dev/null || true)
	arch=$(uname -m 2>/dev/null || true)
	case "$os:$arch" in
		Linux:x86_64) core_asset=botified-core-linux-x86_64-musl.tar.gz ;;
		Linux:aarch64) core_asset=botified-core-linux-aarch64-gnu.tar.gz ;;
		*) fail "unsupported platform: ${os:-unknown} ${arch:-unknown}; supported: Linux x86_64/aarch64" ;;
	esac
	[ -d "$bundle_dir" ] || fail "offline bundle directory not found: $bundle_dir"
	for member in \
		install-offline.sh \
		install.sh \
		install-gateway.sh \
		"$core_asset" \
		botified-claw-gateway-companion.tar.gz \
		SHA256SUMS \
		INSTALLER-SOURCE
	do
		[ -f "$bundle_dir/$member" ] ||
			fail "offline bundle is missing $member: $bundle_dir"
	done
	log "Installing botified from offline bundle: $bundle_dir"
	log "Detected core bundle: $core_asset"
}

core_only=0
managed_scope=
want_gateway=0
channel_input=
channel_given=0
bundle_dir_input=

while [ "$#" -gt 0 ]; do
	case "$1" in
		--core-only)
			[ "$core_only" = 0 ] || usage_fail "--core-only may only be given once"
			core_only=1
			shift
			;;
		--scope)
			[ "$#" -ge 2 ] || usage_fail "missing value for --scope"
			[ -z "$managed_scope" ] || usage_fail "--scope may only be given once"
			case "$2" in
				user|system) managed_scope=$2 ;;
				*) usage_fail "unknown scope: $2" ;;
			esac
			shift 2
			;;
		--gateway)
			[ "$want_gateway" = 0 ] || usage_fail "--gateway may only be given once"
			want_gateway=1
			shift
			;;
		--channel)
			[ "$#" -ge 2 ] || usage_fail "missing value for --channel"
			channel_input="${channel_input:+$channel_input,}$2"
			channel_given=1
			shift 2
			;;
		--bundle-dir)
			[ "$#" -ge 2 ] || usage_fail "missing value for --bundle-dir"
			[ -z "$bundle_dir_input" ] || usage_fail "--bundle-dir may only be given once"
			bundle_dir_input=$2
			shift 2
			;;
		*)
			usage_fail "unknown argument: $1"
			;;
	esac
done

if [ "$core_only" = 1 ]; then
	[ -z "$managed_scope" ] && [ "$want_gateway" = 0 ] && [ "$channel_given" = 0 ] ||
		usage_fail "--core-only cannot be combined with --scope, --gateway, or --channel"
fi
[ "$channel_given" = 0 ] || [ "$want_gateway" = 1 ] ||
	usage_fail "--channel requires --gateway"
[ "$want_gateway" = 0 ] || [ -n "$managed_scope" ] ||
	usage_fail "--gateway requires --scope"
[ "$channel_given" = 0 ] || [ -n "$channel_input" ] ||
	usage_fail "channel list must not be empty"

if [ "$core_only" = 0 ] && [ -z "$managed_scope" ]; then
	form_answer=$(interactive_ask \
		'Offline install form (core-only|managed|managed-gateway): ' \
		'^(core-only|managed|managed-gateway)$' \
		'answer core-only, managed, or managed-gateway, or pass --core-only or --scope explicitly') ||
		exit 5
	case "$form_answer" in
		core-only) core_only=1 ;;
		managed) ;;
		managed-gateway) want_gateway=1 ;;
		*) usage_fail "unknown offline install form: $form_answer" ;;
	esac
	if [ "$core_only" = 0 ]; then
		scope_answer=$(interactive_ask \
			'Offline managed scope (user|system): ' '^(user|system)$' \
			'pass --scope explicitly') ||
			exit 5
		case "$scope_answer" in
			user|system) managed_scope=$scope_answer ;;
			*) usage_fail "unknown scope: $scope_answer" ;;
		esac
	fi
	if [ "$want_gateway" = 1 ]; then
		channel_answer=$(interactive_ask \
			'Gateway channels, comma separated (weixin|feishu|matrix; empty for weixin): ' \
			'^$|^(weixin|feishu|matrix)(,(weixin|feishu|matrix))*$' \
			'answer a comma separated channel list (weixin, feishu, matrix), or pass --channel explicitly') ||
			exit 5
		channel_input=$channel_answer
	fi
fi

if [ "$want_gateway" = 1 ] && [ -n "$channel_input" ]; then
	parse_channel_spec "$channel_input"
fi

bundle_dir=$bundle_dir_input
if [ -z "$bundle_dir" ]; then
	bundle_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) ||
		fail "could not determine the offline bundle directory; pass --bundle-dir explicitly"
fi

validate_bundle

BOTIFIED_ASSET_DIR=$bundle_dir
export BOTIFIED_ASSET_DIR

core_arguments=
[ "$core_only" = 1 ] || core_arguments="--scope $managed_scope"
if [ "$want_gateway" = 1 ]; then
	# Core of the same scope is installed first; every installer runs as a
	# subprocess straight out of the bundle and verifies its asset checksums
	# against the bundled SHA256SUMS before placing anything.
	# shellcheck disable=SC2086
	sh "$bundle_dir/install.sh" $core_arguments
	gateway_arguments="--scope $managed_scope"
	if [ -n "$channel_list" ]; then
		gateway_arguments="$gateway_arguments --channel $channel_list"
	fi
	# shellcheck disable=SC2086
	exec sh "$bundle_dir/install-gateway.sh" $gateway_arguments
fi
# shellcheck disable=SC2086
exec sh "$bundle_dir/install.sh" $core_arguments
