#!/bin/bash
set -euo pipefail
umask 077

root="$(cd "$(dirname "$0")/.." && pwd)"
addons="${EVERLOOK_ADDONS_DIR:-}"
if [ -z "$addons" ]; then
	echo "addon-sync: set EVERLOOK_ADDONS_DIR to your World of Warcraft Interface/AddOns folder" >&2
	exit 1
fi
core="$root/Everlook"

# Before the split the token lived beside the TOC in addon/.
if [ -f "$root/sign.lua" ] && [ ! -L "$root/sign.lua" ] && [ ! -e "$core/sign.lua" ]; then
	mv "$root/sign.lua" "$core/sign.lua"
fi

if [ -L "$core/sign.lua" ] || { [ -e "$core/sign.lua" ] && [ ! -f "$core/sign.lua" ]; }; then
	echo "addon-sync: $core/sign.lua exists and is not a regular file" >&2
	exit 1
fi

mkdir -p "$addons"

# Moves a real folder aside so the link can take its place. Prints where the
# old contents are now, which is the destination itself when nothing moved.
set_aside() {
	local dest="$1" name="$2"
	if [ -L "$dest" ] || [ ! -e "$dest" ]; then
		echo "$dest"
		return
	fi
	if [ ! -d "$dest" ]; then
		echo "addon-sync: $dest exists and is not a directory" >&2
		exit 1
	fi
	local backup
	backup="$(mktemp -d "${dest}.backup.XXXXXX")"
	mv "$dest" "$backup/$name"
	echo "addon-sync: previous addon saved at $backup/$name" >&2
	echo "$backup/$name"
}

for source in "$root"/Everlook "$root"/Everlook_*; do
	[ -d "$source" ] || continue
	name="$(basename "$source")"
	dest="$addons/$name"
	previous="$(set_aside "$dest" "$name")"
	if [ "$name" = Everlook ] && [ ! -f "$core/sign.lua" ]; then
		if [ -f "$previous/sign.lua" ] && grep -q 'Everlook.config.token' "$previous/sign.lua"; then
			cp "$previous/sign.lua" "$core/sign.lua"
		else
			cp "$core/sign_template.lua" "$core/sign.lua"
		fi
	fi
	ln -sfnT "$source" "$dest"
	echo "$dest -> $source"
done
chmod 600 "$core/sign.lua"

# A module folder that was removed or renamed leaves a dangling link behind.
for dest in "$addons"/Everlook_*; do
	if [ -L "$dest" ] && [ ! -e "$dest" ]; then
		target="$(readlink "$dest")"
		case "$target" in
			"$root"/*) rm "$dest" && echo "addon-sync: removed $dest, whose folder is gone" ;;
		esac
	fi
done
