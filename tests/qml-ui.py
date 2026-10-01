"""Qt-only UI regression check. Plasma/Kirigami services are stand-ins, not integration tested.
Requires PySide6 (Essentials). Run with QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software.
"""
import os
os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
os.environ.setdefault('QT_QUICK_BACKEND', 'software')
from pathlib import Path
import shutil, tempfile, time, json
from PySide6.QtCore import QUrl, QObject, QPointF, QPoint, Qt, QCoreApplication, QMetaObject
from PySide6.QtGui import QGuiApplication, QImage, QColor, QWheelEvent
from PySide6.QtQml import QQmlEngine, QQmlComponent, QQmlPropertyMap
from PySide6.QtQuick import QQuickWindow

test_config = tempfile.TemporaryDirectory()
os.environ['XDG_CONFIG_HOME'] = test_config.name
app = QGuiApplication([])
source = Path(__file__).resolve().parent.parent / 'org.liby0zud.customimage/contents/ui'

def pump():
    for _ in range(35):
        app.processEvents()
        time.sleep(0.005)

with tempfile.TemporaryDirectory() as temp:
    folder = Path(temp)
    for p in source.glob('*'):
        if p.is_file(): shutil.copy(p, folder / p.name)
    # Preserve real config UI and interactive image code; replace only KDE services.
    config = (folder / 'config.qml').read_text()
    config = config.replace('import org.kde.plasma.plasmoid', '').replace('import org.kde.kcmutils as KCM', '')
    config = config.replace('readonly property var screens: Qt.application.screens', 'property var screens: Qt.application.screens')
    config = config.replace('id: variantTabs', 'id: variantTabs; objectName: "variantTabs"')
    config = config.replace('id: preview\n', 'id: preview; objectName: "preview"\n')
    translate = 'function i18nd(domain, message, a, b) { return message.replace("%1", a).replace("%2", b); }'
    config = config.replace('id: root', 'id: root\n    ' + translate, 1)
    (folder / 'config.qml').write_text(config)
    image_code = (folder / 'PositionedImage.qml').read_text().replace('id: viewport', 'id: viewport\n    ' + translate, 1)
    (folder / 'PositionedImage.qml').write_text(image_code)
    (folder / 'SystemAppearance.qml').write_text('''import QtQuick
Item {
 property bool monitorCycle: false
 property string initialState: ""
 readonly property string state: ""
 readonly property bool cycleNight: false
 readonly property bool darkTheme: false
}
''')
    engine = QQmlEngine()
    component = QQmlComponent(engine, QUrl.fromLocalFile(str(folder / 'config.qml')))
    assert not component.isError(), [e.toString() for e in component.errors()]
    root = component.create()
    assert root is not None, [e.toString() for e in component.errors()]
    window = QQuickWindow()
    window.resize(1000, 1000)
    root.setParentItem(window.contentItem())
    root.setWidth(1000); root.setHeight(1000)
    root.setProperty('screenSize', __import__('PySide6.QtCore', fromlist=['QSizeF']).QSizeF(2560, 1440))
    image = QImage(1200, 900, QImage.Format_RGB32); image.fill(QColor('steelblue'))
    image.save(str(folder / 'day.png'))
    image.fill(QColor('darkslateblue')); image.save(str(folder / 'night.png'))
    day_url = QUrl.fromLocalFile(str(folder / 'day.png')).toString()
    night_url = QUrl.fromLocalFile(str(folder / 'night.png')).toString()
    root.setProperty('cfg_Image', day_url)
    root.setProperty('cfg_Zoom', 1.5)
    root.setProperty('cfg_FocusX', 0.2)
    root.setProperty('cfg_NightImage', night_url)
    root.setProperty('cfg_NightZoom', 2.0)
    root.setProperty('cfg_NightFocusX', 0.8)
    window.show(); pump()
    tabs = root.findChild(QObject, 'variantTabs')
    preview = root.findChild(QObject, 'preview')
    assert tabs and preview
    assert abs(root.findChild(QObject, 'dayTab').width() - root.findChild(QObject, 'nightTab').width()) < 1e-6
    assert abs(preview.width() / preview.height() - 2560 / 1440) < 1e-6
    assert preview.property('zoom') == 1.5
    assert preview.mapToScene(QPointF(0, 0)).x() >= 32
    tabs.setProperty('currentIndex', 1); pump()
    assert preview.property('zoom') == 2.0
    assert preview.property('focusX') == 0.8
    root.setZoom(2.3); root.setCurrentPosition(0.9, 0.1); pump()
    assert root.property('cfg_NightZoom') == 2.3
    assert root.property('cfg_Zoom') == 1.5
    assert root.property('cfg_FocusX') == 0.2
    position = preview.mapToScene(QPointF(preview.width() / 2, preview.height() / 2))
    def wheel(delta):
        event = QWheelEvent(position, position, QPoint(0, 0), QPoint(0, delta), Qt.NoButton, Qt.NoModifier, Qt.ScrollUpdate, False)
        QCoreApplication.sendEvent(window, event); pump()
    wheel(120)
    assert abs(root.property('cfg_NightZoom') - 2.31) < 1e-9
    for _ in range(12): wheel(10)
    assert abs(root.property('cfg_NightZoom') - 2.32) < 1e-9
    tabs.setProperty('currentIndex', 0); pump()
    assert preview.property('zoom') == 1.5
    root.copyDayToNight(); pump()
    assert root.property('cfg_NightZoom') == root.property('cfg_Zoom')
    assert root.property('cfg_NightFocusX') == root.property('cfg_FocusX')
    # Exercise both visible copy actions, including complete coordinates and mode.
    copy_button = root.findChild(QObject, 'profileCopy')
    assert copy_button is not None
    root.setProperty('cfg_NightImage', night_url)
    root.setProperty('cfg_NightZoom', 2.4)
    root.setProperty('cfg_NightFocusX', 0.0)
    root.setProperty('cfg_NightFocusY', 1.0)
    pump()
    assert copy_button.property('text') == 'Copy night settings to day'
    assert copy_button.property('enabled') is True
    source_night = [root.property('cfg_Night' + key) for key in ('Image','Zoom','FocusX','FocusY')]
    mode_before = root.property('cfg_SwitchMode')
    assert QMetaObject.invokeMethod(copy_button, 'clicked', Qt.DirectConnection)
    pump()
    assert [root.property('cfg_' + key) for key in ('Image','Zoom','FocusX','FocusY')] == source_night
    assert [root.property('cfg_Night' + key) for key in ('Image','Zoom','FocusX','FocusY')] == source_night
    assert root.property('cfg_SwitchMode') == mode_before
    root.setZoom(1.7); pump()
    assert root.property('cfg_NightZoom') == 2.4
    tabs.setProperty('currentIndex', 1); pump()
    assert copy_button.property('text') == 'Copy day settings to night'
    source_day = [root.property('cfg_' + key) for key in ('Image','Zoom','FocusX','FocusY')]
    assert QMetaObject.invokeMethod(copy_button, 'clicked', Qt.DirectConnection)
    pump()
    assert [root.property('cfg_Night' + key) for key in ('Image','Zoom','FocusX','FocusY')] == source_day
    assert [root.property('cfg_' + key) for key in ('Image','Zoom','FocusX','FocusY')] == source_day
    tabs.setProperty('currentIndex', 0)
    root.setProperty('cfg_NightImage', ''); pump()
    assert copy_button.property('enabled') is False
    root.copyNightToDay(); pump()
    assert [root.property('cfg_' + key) for key in ('Image','Zoom','FocusX','FocusY')] == source_day
    assert root.property('cfg_SwitchMode') == mode_before
    # Match the host's aggregate-change handler: copy all cfg_<key> values.
    config_keys = ['Image', 'Zoom', 'FocusX', 'FocusY', 'NightImage', 'NightZoom',
                   'NightFocusX', 'NightFocusY', 'SwitchMode', 'ScheduleState', 'TargetOutput', 'ProfileRevision']
    host_map = {}
    def sync_host():
        for key in config_keys: host_map[key] = root.property('cfg_' + key)
    root.configurationChanged.connect(sync_host)
    root.setProperty('cfg_NightImage', night_url)
    root.setProperty('cfg_NightZoom', 2.71)
    root.setProperty('cfg_NightFocusX', 0.12)
    root.setProperty('cfg_NightFocusY', 0.34)
    root.setProperty('cfg_SwitchMode', 0)
    pump()
    assert host_map['SwitchMode'] == 0 and host_map['NightImage'] == night_url
    stored = folder / 'saved-settings.json'
    stored.write_text(json.dumps(host_map))
    initial = {'cfg_' + key: value for key, value in json.loads(stored.read_text()).items()}
    reopened = component.createWithInitialProperties(initial)
    assert reopened is not None
    pump()
    for key in config_keys:
        assert reopened.property('cfg_' + key) == host_map[key], key
    reopened_tabs = reopened.findChild(QObject, 'variantTabs')
    reopened_tabs.setProperty('currentIndex', 1); pump()
    assert reopened.property('currentImage') == night_url
    assert reopened.property('currentZoom') == 2.71
    # A live host with an older schema must not allow edits it cannot save.
    old_map = engine.evaluate('({keys: function() { return ["Image", "Zoom", "FocusX", "FocusY"]; }})')
    root.setProperty('wallpaperConfiguration', old_map); pump()
    assert root.property('settingsSchemaReady') is False
    full_map = engine.evaluate('({keys: function() { return ' + json.dumps(config_keys) + '; }})')
    root.setProperty('wallpaperConfiguration', full_map); pump()
    assert root.property('settingsSchemaReady') is True
    # Simulate hotplug in the real selector; its owner is a name, not its index.
    def outputs(names):
        items = [{'name': name, 'width': 2560 if name == 'HDMI-A-1' else 1280,
                  'height': 1440 if name == 'HDMI-A-1' else 800} for name in names]
        root.setProperty('screens', engine.evaluate(json.dumps(items)))
        pump()
    root.setProperty('screenSize', __import__('PySide6.QtCore', fromlist=['QSizeF']).QSizeF(0, 0))
    outputs(['HDMI-A-1', 'eDP-1'])
    root.setProperty('selectedPreviewOutput', 'HDMI-A-1'); pump()
    assert root.property('previewOutputMissing') is False
    outputs(['eDP-1'])
    assert root.property('selectedPreviewOutput') == 'HDMI-A-1'
    assert root.property('previewOutputMissing') is True
    outputs(['eDP-1', 'HDMI-A-1'])
    assert root.property('previewOutputMissing') is False
    root.setProperty('screen', engine.evaluate('({name: "eDP-1", width:1280, height:800})'))
    root.claimTargetOutput(); pump()
    assert root.property('cfg_TargetOutput') == 'eDP-1'
    assert root.property('selectedPreviewOutput') == 'HDMI-A-1'
    assert host_map['TargetOutput'] == 'eDP-1'

    # Exercise the real wallpaper guard with a controlled attached-output input.
    main_code = (folder / 'main.qml').read_text().replace('import org.kde.plasma.plasmoid', '')
    main_code = main_code.replace('WallpaperItem {', 'Item { property var configuration', 1)
    main_code = main_code.replace('id: root', 'id: root\n    ' + translate, 1)
    main_code = main_code.replace('readonly property string outputName: outputWindow ? Screen.name : ""',
                                  'property string outputName: "HDMI-A-1"')
    (folder / 'main.qml').write_text(main_code)
    main_component = QQmlComponent(engine, QUrl.fromLocalFile(str(folder / 'main.qml')))
    assert not main_component.isError(), [e.toString() for e in main_component.errors()]
    wallpaper_config = engine.evaluate('({TargetOutput:"HDMI-A-1",Image:"",NightImage:"",SwitchMode:2})')
    wallpaper = main_component.createWithInitialProperties({'configuration': wallpaper_config})
    assert wallpaper is not None, [e.toString() for e in main_component.errors()]
    pump()
    assert wallpaper.property('correctOutput') is True
    wallpaper.setProperty('outputName', 'eDP-1'); pump()
    assert wallpaper.property('correctOutput') is False
    wallpaper.setProperty('outputName', 'HDMI-A-1'); pump()
    assert wallpaper.property('correctOutput') is True
    # Seed B from its own desktop before simulating A's containment migrating to B.
    b_config = engine.evaluate('({TargetOutput:"eDP-1",Image:"",NightImage:"",Zoom:2.25,NightZoom:2.75,FocusX:0.1,NightFocusY:0.9,SwitchMode:3,ProfileRevision:"100"})')
    b = main_component.createWithInitialProperties({'configuration': b_config, 'outputName':'eDP-1'})
    pump()
    assert b.property('correctOutput') is True
    wallpaper.setProperty('outputName', 'eDP-1'); pump()
    assert wallpaper.property('correctOutput') is True
    assert wallpaper.property('dayProfile').toVariant()['zoom'] == 2.25
    assert wallpaper.property('effectiveConfiguration').toVariant()['NightZoom'] == 2.75
    assert wallpaper.property('night') is True
    # A stale, correctly tagged B containment must not roll back a newer B record.
    stale = engine.evaluate('({TargetOutput:"eDP-1",Image:"",Zoom:1.1,SwitchMode:2,ProfileRevision:"50"})')
    wallpaper.setProperty('configuration', stale); pump()
    assert wallpaper.property('dayProfile').toVariant()['zoom'] == 2.25
    # A newly applied B edit updates B only and reaches the other instance on refresh.
    updated = engine.evaluate('({TargetOutput:"eDP-1",Image:"",Zoom:2.9,NightZoom:2.6,SwitchMode:1,ProfileRevision:"200"})')
    wallpaper.setProperty('configuration', updated); pump()
    b.refreshProfile(); pump()
    assert b.property('dayProfile').toVariant()['zoom'] == 2.9
    # Reconnect A while its containment still carries B's host configuration.
    wallpaper.setProperty('outputName', 'HDMI-A-1'); pump()
    assert wallpaper.property('correctOutput') is True
    assert wallpaper.property('dayProfile').toVariant()['zoom'] == 1.0
    # Opening B's editor with migrated A settings restores B's independent record.
    migrated_editor = component.createWithInitialProperties({'cfg_TargetOutput':'HDMI-A-1',
        'cfg_Zoom':1.2, 'screen':engine.evaluate('({name:"eDP-1",width:1280,height:800})')})
    pump()
    assert migrated_editor.property('cfg_TargetOutput') == 'eDP-1'
    assert migrated_editor.property('cfg_Zoom') == 2.9
    assert migrated_editor.property('cfg_NightZoom') == 2.6
    assert migrated_editor.property('cfg_SwitchMode') == 1
    migrated_editor.setZoom(1.7); pump()
    # Editing/cancelling does not write the independent store before host Apply.
    b.refreshProfile(); pump()
    assert b.property('dayProfile').toVariant()['zoom'] == 2.9
    # Match individual host field notifications; revision is published last.
    applied_map = QQmlPropertyMap()
    for key, value in {'TargetOutput':'eDP-1','Image':'','Zoom':2.9,
            'NightZoom':2.6,'SwitchMode':1,'ProfileRevision':'200'}.items():
        applied_map.insert(key, value)
    b.setProperty('configuration', applied_map); pump()
    applied_map.insert('Zoom', 2.4); pump()
    assert b.property('dayProfile').toVariant()['zoom'] == 2.9
    applied_map.insert('NightZoom', 1.8)
    applied_map.insert('FocusX', 0.33)
    applied_map.insert('SwitchMode', 3)
    applied_map.insert('ProfileRevision', '201'); pump()
    assert b.property('dayProfile').toVariant()['zoom'] == 2.4
    assert b.property('effectiveConfiguration').toVariant()['NightZoom'] == 1.8
    assert b.property('effectiveConfiguration').toVariant()['FocusX'] == 0.33
    assert b.property('night') is True
    migrated_editor.deleteLater(); b.deleteLater()
    wallpaper.deleteLater()
    reopened.deleteLater()
    root.deleteLater(); window.close(); pump()
print('Passed: Qt UI, equal tab widths, independent edits, bidirectional copy, wheel events, host-map synchronization, save/reload, stale-schema guard, per-output restoration and cancelled edits. Native KDE services use stand-ins.')
