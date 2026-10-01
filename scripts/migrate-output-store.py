#!/usr/bin/env python3
"""Migrate 0.3.0/0.3.1 Qt Settings JSON records to ordinary INI fields.
Uses only Python's standard library; keeps a byte-for-byte backup and is idempotent.
"""
import configparser
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
from urllib.parse import quote, unquote

DEFAULTS = dict(Image='', Zoom=1.0, FocusX=0.5, FocusY=0.5, NightImage='',
                NightZoom=1.0, NightFocusX=0.5, NightFocusY=0.5, SwitchMode=2,
                ScheduleState='', TargetOutput='', ProfileRevision='0')


def decode_string(value):
    # The old writer always stores JSON as a quoted Qt INI string. For these
    # JSON payloads Qt's quote/backslash escaping also forms a JSON string.
    return json.loads(value) if value.startswith('"') else value


def encode_string(value):
    # QSettings reserves @ prefixes for QVariant encodings.
    if value.startswith('@'):
        value = '@' + value
    return json.dumps(value, ensure_ascii=False)


def category(output):
    # Match encodeURIComponent in QML, then Qt's INI section-key escaping.
    name = 'Display-' + quote(output, safe="~!*'()-._")
    return quote(name, safe='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-.' )


def migrate(path):
    if not path.exists():
        return 0
    original = path.read_bytes()
    config = configparser.ConfigParser(interpolation=None, strict=True)
    config.optionxform = str
    config.read_string(original.decode('utf-8-sig'))
    if not config.has_section('Outputs'):
        return 0
    migrated = 0
    for key, raw in list(config.items('Outputs')):
        if not raw.strip():
            # Remove empty legacy keys left by an earlier interrupted migration.
            config.remove_option('Outputs', key)
            continue
        record = json.loads(decode_string(raw))
        if not isinstance(record, dict):
            raise ValueError('Invalid legacy record: ' + key)
        profile = record.get('profile')
        if record.get('schema') != 1 or not isinstance(profile, dict):
            raise ValueError('Unsupported legacy record: ' + key)
        output = profile.get('TargetOutput')
        expected = quote(output, safe="~!*'()-._") if isinstance(output, str) else None
        if not output or unquote(key) != expected:
            raise ValueError('Legacy output identity mismatch: ' + key)
        values = dict(DEFAULTS, **{k: v for k, v in profile.items() if k in DEFAULTS})
        section = category(output)
        previous = int(decode_string(config.get(section, 'ProfileRevision', fallback='0')))
        if not config.has_section(section) or int(values['ProfileRevision']) > previous:
            if not config.has_section(section):
                config.add_section(section)
            config.set(section, 'FormatVersion', '2')
            for field, value in values.items():
                if field in ('Zoom', 'FocusX', 'FocusY', 'NightZoom', 'NightFocusX', 'NightFocusY'):
                    config.set(section, field, str(float(value)))
                elif field == 'SwitchMode':
                    config.set(section, field, str(int(value)))
                else:
                    if not isinstance(value, str):
                        raise ValueError('Invalid string field: ' + field)
                    config.set(section, field, encode_string(value))
        config.remove_option('Outputs', key)
        migrated += 1
    if not config.items('Outputs'):
        config.remove_section('Outputs')
    # Do not replace a file changed by another process while being parsed.
    if path.read_bytes() != original:
        raise RuntimeError('The store changed during migration; close wallpaper settings and retry.')
    backup = path.with_name(path.name + '.before-plain-ini.bak')
    if not backup.exists():
        with backup.open('xb') as stream:
            stream.write(original)
        backup.chmod(stat.S_IMODE(path.stat().st_mode))
    fd, temp = tempfile.mkstemp(prefix=path.name + '.', dir=path.parent)
    try:
        os.fchmod(fd, stat.S_IMODE(path.stat().st_mode))
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            config.write(stream, space_around_delimiters=False)
            stream.flush()
            os.fsync(stream.fileno())
        if path.read_bytes() != original:
            raise RuntimeError('The store changed during migration; close wallpaper settings and retry.')
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)
    return migrated


if __name__ == '__main__':
    store = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
        os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config'))) / 'custom-image-wallpaper.ini'
    try:
        count = migrate(store)
    except (ValueError, TypeError, KeyError, OSError, RuntimeError, configparser.Error) as error:
        print('Profile migration failed; original store retained: ' + str(error), file=sys.stderr)
        sys.exit(1)
    if count:
        print('Migrated %d display profiles to plain INI; original file backed up.' % count)
