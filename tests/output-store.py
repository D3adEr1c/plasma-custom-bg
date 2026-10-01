"""Real Qt Settings persistence across separate processes; no KDE stand-ins needed."""
import os, sys, tempfile, subprocess, json
from pathlib import Path

if len(sys.argv) == 1:
    import configparser
    source_root = Path(__file__).resolve().parent.parent
    for initial in ('write', 'legacy'):
        with tempfile.TemporaryDirectory() as config:
            env = dict(os.environ, XDG_CONFIG_HOME=config, QT_QPA_PLATFORM='offscreen', EXPECT_UNUSUAL=str(initial == 'legacy'))
            store = Path(config) / 'custom-image-wallpaper.ini'
            subprocess.run([sys.executable, __file__, initial], env=env, check=True)
            if initial == 'legacy':
                original = store.read_bytes()
                subprocess.run([sys.executable, str(source_root / 'scripts/migrate-output-store.py'), str(store)], check=True)
                assert store.with_name(store.name + '.before-plain-ini.bak').read_bytes() == original
                migrated = store.read_bytes()
                subprocess.run([sys.executable, str(source_root / 'scripts/migrate-output-store.py'), str(store)], check=True)
                assert store.read_bytes() == migrated
            for phase in ('read', 'update', 'verify'):
                subprocess.run([sys.executable, __file__, phase], env=env, check=True)
            parsed = configparser.ConfigParser(interpolation=None)
            parsed.read(store)
            assert not parsed.has_section('Outputs')
            assert parsed.has_section('Display-HDMI-A-1')
            assert parsed.has_section('Display-eDP-1')
            assert parsed.get('Display-HDMI-A-1', 'Zoom') == '1.7'
            assert not any('"schema"' in value or '\\"schema\\"' in value
                           for section in parsed for value in parsed[section].values())
    # Invalid legacy data must leave the original untouched.
    with tempfile.TemporaryDirectory() as config:
        store = Path(config) / 'custom-image-wallpaper.ini'
        store.write_text('[Outputs]\neDP-1=invalid-record\n')
        original = store.read_bytes()
        result = subprocess.run([sys.executable, str(source_root / 'scripts/migrate-output-store.py'), str(store)], capture_output=True)
        assert result.returncode != 0 and store.read_bytes() == original
    print('Passed: plain INI fields, real Qt restart, independent outputs, revisions, complete legacy migration, backup and idempotence.')
    sys.exit(0)

from PySide6.QtCore import QUrl, QSettings
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlEngine, QQmlComponent
app = QGuiApplication([])
engine = QQmlEngine()
source = Path(__file__).resolve().parent.parent / 'org.liby0zud.customimage/contents/ui'
component = QQmlComponent(engine)
component.setData(b'''import QtQuick
import "."
QtObject {
 property OutputStore store: OutputStore {}
 function save(name, data) { store.write(name, JSON.parse(data)); }
 function load(name) { return JSON.stringify(store.read(name)); }
}''', QUrl.fromLocalFile(str(source / 'StoreTest.qml')))
root = component.create()
assert root is not None, [e.toString() for e in component.errors()]
def save(name, **profile):
    root.save(name, json.dumps(profile))
def read(name):
    return json.loads(root.load(name))
phase = sys.argv[1]
if phase == 'legacy':
    legacy = QSettings(str(Path(os.environ['XDG_CONFIG_HOME']) / 'custom-image-wallpaper.ini'), QSettings.IniFormat)
    legacy.beginGroup('Outputs')
    profiles = {
        'HDMI-A-1':dict(TargetOutput='HDMI-A-1', Image='file:///a-day.png', NightImage='file:///a-night.png',
                       Zoom=1.7, NightZoom=2.3, FocusX=0.0, NightFocusY=1.0, SwitchMode=0, ProfileRevision='100'),
        'eDP-1':dict(TargetOutput='eDP-1', Image='file:///b-day.png', NightImage='file:///b-night.png',
                    Zoom=2.6, NightZoom=1.2, FocusY=0.15, NightFocusX=0.85, SwitchMode=1, ProfileRevision='200'),
        'output / (ø)!%':dict(TargetOutput='output / (ø)!%', Image='file:///雪,=\\quoted\".png',
                             ScheduleState='@schedule\nstate', ProfileRevision='300')
    }
    from urllib.parse import quote
    for output, profile in profiles.items():
        key = quote(output, safe="~!*'()-._")
        legacy.setValue(key, json.dumps({'schema':1,'profile':profile}, ensure_ascii=False, separators=(',', ':')))
    legacy.sync()
elif phase == 'write':
    save('HDMI-A-1', TargetOutput='HDMI-A-1', Image='file:///a-day.png',
         NightImage='file:///a-night.png', Zoom=1.7, NightZoom=2.3,
         FocusX=0.0, NightFocusY=1.0, SwitchMode=0, ProfileRevision='100')
    save('eDP-1', TargetOutput='eDP-1', Image='file:///b-day.png',
         NightImage='file:///b-night.png', Zoom=2.6, NightZoom=1.2,
         FocusY=0.15, NightFocusX=0.85, SwitchMode=1, ProfileRevision='200')
elif phase == 'read':
    assert read('HDMI-A-1')['NightImage'] == 'file:///a-night.png'
    assert read('HDMI-A-1')['FocusX'] == 0.0
    assert read('eDP-1')['Zoom'] == 2.6
    assert read('eDP-1')['SwitchMode'] == 1
    assert read('missing') is None
    unusual = read('output / (ø)!%')
    if os.environ.get('EXPECT_UNUSUAL') == 'True':
        assert unusual is not None
        assert unusual['Image'] == 'file:///雪,=\\quoted\".png'
        assert unusual['ScheduleState'] == '@schedule\nstate'
elif phase == 'update':
    save('eDP-1', TargetOutput='HDMI-A-1', Zoom=3, ProfileRevision='999')
    save('eDP-1', TargetOutput='eDP-1', Zoom=1, ProfileRevision='199')
    assert read('eDP-1')['Zoom'] == 2.6
    save('eDP-1', TargetOutput='eDP-1', Zoom=2.8, SwitchMode=3, ProfileRevision='201')
elif phase == 'verify':
    assert read('HDMI-A-1')['Zoom'] == 1.7
    assert read('HDMI-A-1')['NightZoom'] == 2.3
    assert read('eDP-1')['Zoom'] == 2.8
    assert read('eDP-1')['SwitchMode'] == 3
