#!/usr/bin/env bash
set -euo pipefail
plugin_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/org.liby0zud.customimage"
target="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/wallpapers/org.liby0zud.customimage"
profile_store="${XDG_CONFIG_HOME:-$HOME/.config}/custom-image-wallpaper.ini"
if [[ -f "$profile_store" ]]; then
    python3 "$(dirname -- "$plugin_dir")/scripts/migrate-output-store.py" "$profile_store"
fi
mkdir -p -- "$(dirname -- "$target")"
if [[ -e "$target" ]]; then
    if [[ ! -f "$target/metadata.json" ]] || ! grep -q "org.liby0zud.customimage" "$target/metadata.json"; then
        echo "Refusing to replace an unrelated directory: $target" >&2
        exit 1
    fi
    cp -R -- "$plugin_dir"/. "$target"/
else
    cp -R -- "$plugin_dir" "$target"
fi
locale_source="$(dirname -- "$plugin_dir")/locale"
if [[ -d "$locale_source" ]]; then
    mkdir -p -- "${XDG_DATA_HOME:-$HOME/.local/share}/locale"
    cp -R -- "$locale_source"/. "${XDG_DATA_HOME:-$HOME/.local/share}/locale/"
fi
echo "Installed: $target"
echo 'Open Desktop and Wallpaper settings, then select "Custom Image" as Wallpaper Type.'

echo 'After updating: close System Settings, log out and log back in BEFORE configuring the wallpaper.'
echo 'This reloads both the QML and the configuration schema; reopening Settings alone is insufficient.'

# Retain the installed legacy plugin for desktops that still reference its ID.
# Label it clearly so both choices in the wallpaper picker are distinguishable.
legacy="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/wallpapers/org.example.positionedimage"
if [[ -f "$legacy/metadata.json" ]]; then
    python3 - "$legacy/metadata.json" <<'PYCODE'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
plugin = data.get("KPlugin", {})
if plugin.get("Id") == "org.example.positionedimage":
    backup = path.with_name("metadata.before-id-migration.json")
    if not backup.exists(): backup.write_bytes(path.read_bytes())
    plugin["Name"] = "Custom Image (legacy ID)"
    plugin["Name[zh_CN]"] = "自定义图像（旧 ID）"
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
PYCODE
    echo 'The old plugin remains installed as "Custom Image (legacy ID)".'
    echo 'After logging back in, select "Custom Image" on each display and Apply.'
    echo 'Version 0.3.0 output profiles are reused automatically by the new ID.'
fi
