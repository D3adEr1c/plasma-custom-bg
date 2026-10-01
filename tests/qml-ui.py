"""Qt-only UI regression check. Plasma/Kirigami services are stand-ins, not integration tested.
Requires PySide6 (Essentials). Run with QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software.
"""
import os
os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
os.environ.setdefault('QT_QUICK_BACKEND', 'software')
from pathlib import Path
import shutil, tempfile, time, json
from PySide6.QtCore import QUrl, QObject, QPointF, QPoint, Qt, QCoreApplication, QMetaObject, QAbstractListModel, QModelIndex
from PySide6.QtGui import QGuiApplication, QImage, QColor, QWheelEvent
from PySide6.QtQml import QQmlEngine, QQmlComponent, QQmlPropertyMap
from PySide6.QtQuick import QQuickWindow, QQuickImageProvider

test_config = tempfile.TemporaryDirectory()
os.environ['XDG_CONFIG_HOME'] = test_config.name
app = QGuiApplication([])
source = Path(__file__).resolve().parent.parent / 'org.liby0zud.customimage/contents/ui'

class NativeRoleModel(QAbstractListModel):
    """Plasma 6.7 role contract, including QUrl-valued sources (no old roles)."""
    names = ['display', 'decoration', 'author', 'preview', 'source', 'removable',
             'pendingDeletion', 'checked', 'selectors']
    def __init__(self, rows):
        super().__init__()
        self.rows = rows
    def roleNames(self):
        return {Qt.UserRole + i: name.encode() for i, name in enumerate(self.names)}
    def rowCount(self, parent=QModelIndex()):
        return 0 if parent.isValid() else len(self.rows)
    def data(self, index, role):
        if not index.isValid(): return None
        name = self.names[role - Qt.UserRole] if Qt.UserRole <= role < Qt.UserRole + len(self.names) else None
        return self.rows[index.row()].get(name)

class PreviewProvider(QQuickImageProvider):
    """Exercise real Qt Image loading through image://wallpaper-preview URLs."""
    def __init__(self):
        super().__init__(QQuickImageProvider.Image)
        self.requests = []
    def requestImage(self, identifier, size, requested_size):
        self.requests.append(identifier)
        image = QImage(identifier.removeprefix('image/'))
        size.setWidth(image.width()); size.setHeight(image.height())
        if requested_size.isValid():
            image = image.scaled(requested_size, Qt.KeepAspectRatio, Qt.SmoothTransformation)
        return image

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
    config = config.replace('id: galleryBackend', 'id: galleryBackend; objectName: "galleryBackend"')
    config = config.replace('id: variantTabs', 'id: variantTabs; objectName: "variantTabs"')
    config = config.replace('id: preview\n', 'id: preview; objectName: "preview"\n')
    translate = 'function i18nd(domain, message, a, b) { return message.replace("%1", a).replace("%2", b); }'
    config = config.replace('id: root', 'id: root\n    ' + translate, 1)
    (folder / 'config.qml').write_text(config)
    image_code = (folder / 'PositionedImage.qml').read_text().replace('id: viewport', 'id: viewport\n    ' + translate, 1)
    (folder / 'PositionedImage.qml').write_text(image_code)
    (folder / 'SystemAppearance.qml').write_text('''import QtQuick
Item {
 objectName: "testAppearance"
 property bool monitorCycle: false
 property string initialState: ""
 readonly property string state: ""
 property bool cycleNight: false
 property bool darkTheme: false
}
''')
    # Keep gallery and editor UI real; substitute unavailable native KDE adapters.
    (folder / 'NativeGalleryBackend.qml').write_text('''import QtQuick
Item {
 property size targetSize: Qt.size(1920,1080)
 property var wallpaperModel: ListModel {}
 property bool loading: false
 property var selectedImages: []
 function wallpaperUrl(key, selectors, night) { return String(key); }
 function add(url) { return String(url); }
 function commit() {}
 function reload() {}
}
''')
    (folder / 'NativeWallpaperSource.qml').write_text('''import QtQuick
Item { property string source: ""; property size targetSize: Qt.size(1920,1080); readonly property url resolvedSource: source }
''')
    # Python image providers cannot acquire the GIL while Qt waits during a
    # render pass. Only this provider test runs image loading synchronously;
    # production keeps native C++ provider loading asynchronous.
    thumbnail_code = (folder / 'NativeThumbnail.qml').read_text()
    (folder / 'NativeThumbnail.qml').write_text(thumbnail_code.replace('asynchronous: true', 'asynchronous: false'))
    (folder / 'GetNewWallpapersButton.qml').write_text('''import QtQuick.Controls
Button { signal wallpapersChanged(); text: "Get New Wallpapers…" }
''')
    for name in ['FramingEditor.qml', 'WallpaperGallery.qml']:
        code = (folder / name).read_text()
        marker = 'id: editor' if name == 'FramingEditor.qml' else 'id: root'
        (folder / name).write_text(code.replace(marker, marker + '\n    ' + translate, 1))
    engine = QQmlEngine()
    preview_provider = PreviewProvider()
    engine.addImageProvider("wallpaper-preview", preview_provider)
    component = QQmlComponent(engine, QUrl.fromLocalFile(str(folder / 'config.qml')))
    assert not component.isError(), [e.toString() for e in component.errors()]
    root = component.create()
    assert root is not None, [e.toString() for e in component.errors()]
    # Defaults follow the effective mode, including late scheduler/theme updates.
    for mode in (0, 1, 2, 3):
        default_page = component.createWithInitialProperties({'cfg_SwitchMode': mode})
        assert default_page is not None
        default_notifications = []
        default_page.configurationChanged.connect(lambda: default_notifications.append(True))
        pump()
        default_tabs = default_page.findChild(QObject, 'variantTabs')
        system = default_page.findChild(QObject, 'testAppearance')
        assert default_tabs.property('currentIndex') == (1 if mode == 3 else 0)
        system.setProperty('cycleNight', True)
        system.setProperty('darkTheme', True)
        pump()
        assert default_tabs.property('currentIndex') == (0 if mode == 2 else 1)
        # A manual tab choice survives subsequent appearance and restore updates.
        day_button = default_page.findChild(QObject, 'dayTab')
        QMetaObject.invokeMethod(day_button, 'clicked', Qt.DirectConnection)
        default_tabs.setProperty('currentIndex', 0)
        system.setProperty('cycleNight', False)
        system.setProperty('darkTheme', False)
        pump()
        system.setProperty('cycleNight', True)
        system.setProperty('darkTheme', True)
        default_page.restoreOutputProfile()
        pump()
        assert default_tabs.property('currentIndex') == 0
        assert default_notifications == []
        default_page.deleteLater()
        pump()
    edit_notifications = []
    root.configurationChanged.connect(lambda: edit_notifications.append(True))
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
    editor = root.findChild(QObject, 'framingEditor')
    root.openFraming(); pump()
    preview = root.findChild(QObject, 'preview')
    assert tabs and preview
    assert abs(root.findChild(QObject, 'dayTab').width() - root.findChild(QObject, 'nightTab').width()) < 1e-6
    assert abs(preview.width() / preview.height() - 2560 / 1440) < 1e-6
    assert preview.property('zoom') == 1.5
    assert preview.mapToScene(QPointF(0, 0)).x() >= 32
    tabs.setProperty('currentIndex', 1); root.openFraming(); pump()
    assert preview.property('zoom') == 2.0
    assert preview.property('focusX') == 0.8
    assert edit_notifications == []  # Host initialization and tabs are read-only.
    root.setZoom(2.3); root.setCurrentPosition(0.9, 0.1); pump()
    assert root.property('cfg_NightZoom') == 2.3
    assert root.property('cfg_Zoom') == 1.5
    assert root.property('cfg_FocusX') == 0.2
    assert len(edit_notifications) == 2
    revision_before_noop = root.property('cfg_ProfileRevision')
    root.setZoom(2.3)
    root.setCurrentPosition(0.9, 0.1)
    root.setSwitchMode(root.property('cfg_SwitchMode'))
    pump()
    assert len(edit_notifications) == 2
    assert root.property('cfg_ProfileRevision') == revision_before_noop
    # Draft edits never notify the host until confirmed. Closing discards them.
    root.openFraming(); pump()
    draft_notifications = len(edit_notifications)
    editor.setProperty('draftZoom', 2.6)
    editor.setProperty('draftX', 0.3)
    editor.close(); pump()
    assert root.property('cfg_NightZoom') == 2.3
    assert len(edit_notifications) == draft_notifications
    root.openFraming(); pump()
    assert preview.property('zoom') == 2.3
    position = preview.mapToScene(QPointF(preview.width() / 2, preview.height() / 2))
    def wheel(delta):
        event = QWheelEvent(position, position, QPoint(0, 0), QPoint(0, delta), Qt.NoButton, Qt.NoModifier, Qt.ScrollUpdate, False)
        QCoreApplication.sendEvent(editor, event); pump()
    wheel(120)
    assert abs(editor.property('draftZoom') - 2.31) < 1e-9
    assert root.property('cfg_NightZoom') == 2.3
    for _ in range(12): wheel(10)
    assert abs(editor.property('draftZoom') - 2.32) < 1e-9
    assert len(edit_notifications) == draft_notifications
    editor.accept(); pump()
    assert abs(root.property('cfg_NightZoom') - 2.32) < 1e-9
    assert len(edit_notifications) == draft_notifications + 1
    root.openFraming(); pump()
    editor.accept(); pump()
    assert len(edit_notifications) == draft_notifications + 1  # Unchanged OK is clean.
    tabs.setProperty('currentIndex', 0); root.openFraming(); pump()
    assert preview.property('zoom') == 1.5
    editor.close()
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
    equal_copy_revision = root.property('cfg_ProfileRevision')
    equal_copy_notifications = len(edit_notifications)
    root.copyDayToNight()
    root.copyNightToDay()
    pump()
    assert root.property('cfg_ProfileRevision') == equal_copy_revision
    assert len(edit_notifications) == equal_copy_notifications
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
    tabs.setProperty('currentIndex', 1)
    root.setImage(night_url, True)
    root.setZoom(2.71)
    root.setCurrentPosition(0.12, 0.34)
    root.setSwitchMode(0)
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
    # Native model roles reach the real gallery delegate and the active profile.
    gallery_backend = root.findChild(QObject, 'galleryBackend')
    grid = root.findChild(QObject, 'wallpaperGrid')
    engine.globalObject().setProperty('galleryGrid', engine.newQObject(grid))
    fixtures = [dict(display='Day image', author='Test', source=QUrl(day_url),
                     preview='image://wallpaper-preview/image/' + str(folder / 'day.png'), selectors=[]),
                dict(display='Night image', author='Test', source=QUrl(night_url),
                     preview='image://wallpaper-preview/image/' + str(folder / 'night.png'), selectors=[])]
    gallery_model = NativeRoleModel(fixtures)
    gallery_backend.setProperty('wallpaperModel', gallery_model)
    pump()
    assert grid.property('count') == 2
    thumbnails = [engine.evaluate('galleryGrid.itemAtIndex(' + str(i) + ').contentItem.children[0]').toQObject() for i in range(2)]
    assert all(thumbnails)
    assert all(engine.evaluate('galleryGrid.itemAtIndex(' + str(i) + ').contentItem.children[0].status').toInt() == 1 for i in range(2))  # Image.Ready
    assert len(preview_provider.requests) >= 2
    assert all(thumbnail.property('source').toString().startswith('image://wallpaper-preview/') for thumbnail in thumbnails)
    tabs.setProperty('currentIndex', 0); pump()
    original_night = root.property('cfg_NightImage')
    result = engine.evaluate('galleryGrid.itemAtIndex(0).clicked()')
    assert not result.isError(), result.toString()
    pump()
    assert root.property('cfg_Image') == day_url
    assert root.property('cfg_NightImage') == original_night
    adjust_button = root.findChild(QObject, 'adjustFraming')
    assert adjust_button.property('enabled') is True
    assert QMetaObject.invokeMethod(adjust_button, 'clicked', Qt.DirectConnection)
    pump()
    assert editor.isVisible() is True
    assert preview.property('imageUrl').toString() == day_url
    editor.close()
    count_before_same = len(edit_notifications)
    engine.evaluate('galleryGrid.itemAtIndex(0).clicked()'); pump()
    assert len(edit_notifications) == count_before_same
    tabs.setProperty('currentIndex', 1); pump()
    engine.evaluate('galleryGrid.itemAtIndex(1).clicked()'); pump()
    assert root.property('cfg_NightImage') == night_url
    assert root.property('cfg_Image') == day_url
    if os.environ.get('CUSTOM_IMAGE_QA_DIR'):
        qa = Path(os.environ['CUSTOM_IMAGE_QA_DIR']); qa.mkdir(parents=True, exist_ok=True)
        window.resize(760, 600); root.setWidth(760); root.setHeight(600); pump()
        window.grabWindow().save(str(qa / 'gallery.png'))
        root.openFraming(); pump()
        editor.grabWindow().save(str(qa / 'framing.png'))
        editor.close()
    # A draft cannot land on another image or monitor after the host changes.
    root.openFraming(); pump()
    editor.setProperty('draftZoom', 2.99)
    root.setImage(day_url, True); pump()
    old_zoom = root.property('cfg_NightZoom')
    editor.accept(); pump()
    assert root.property('cfg_NightZoom') == old_zoom
    root.openFraming(); pump()
    editor.setProperty('draftZoom', 2.98)
    root.setProperty('screen', engine.evaluate('({name:"DP-2",width:1920,height:1080})')); pump()
    assert editor.isVisible() is False
    before_moved_accept = len(edit_notifications)
    editor.accept(); pump()
    assert len(edit_notifications) == before_moved_accept
    root.setProperty('screen', None); pump()

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
    root.claimTargetOutput(); root.touchProfile(); pump()
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
    migrated_signals = []
    migrated_editor.configurationChanged.connect(lambda: migrated_signals.append('aggregate'))
    for key in config_keys:
        getattr(migrated_editor, 'cfg_' + key + 'Changed').connect(lambda: migrated_signals.append('field'))
    pump()
    assert migrated_signals == []  # No dirty signal, including individual fields.
    assert migrated_editor.property('cfg_TargetOutput') == 'HDMI-A-1'
    assert migrated_editor.property('cfg_Zoom') == 1.2
    assert migrated_editor.property('currentZoom') == 2.9
    assert migrated_editor.property('editorProfile').toVariant()['NightZoom'] == 2.6
    assert migrated_editor.property('editorProfile').toVariant()['SwitchMode'] == 1
    unchanged_revision = migrated_editor.property('cfg_ProfileRevision')
    migrated_editor.restoreOutputProfile()
    migrated_editor.restoreOutputProfile()
    migrated_editor.setZoom(2.9)
    migrated_editor.setSwitchMode(1)
    migrated_editor.setCurrentPosition(migrated_editor.property('currentFocusX'), migrated_editor.property('currentFocusY'))
    migrated_tabs = migrated_editor.findChild(QObject, 'variantTabs')
    migrated_tabs.setProperty('currentIndex', 1); pump()
    migrated_tabs.setProperty('currentIndex', 0); pump()
    assert migrated_signals == []
    assert migrated_editor.property('cfg_ProfileRevision') == unchanged_revision
    migrated_editor.setZoom(1.7); pump()
    assert migrated_signals.count('aggregate') == 1
    assert migrated_editor.property('cfg_TargetOutput') == 'eDP-1'
    assert migrated_editor.property('cfg_NightZoom') == 2.6
    assert migrated_editor.property('cfg_SwitchMode') == 1
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
    # Reopening an already matching, applied profile must also remain clean.
    saved_profile = b.property('effectiveConfiguration').toVariant()
    matching_initial = {'cfg_' + key:value for key,value in saved_profile.items()}
    matching_initial['screen'] = engine.evaluate('({name:"eDP-1",width:1280,height:800})')
    matching_editor = component.createWithInitialProperties(matching_initial)
    matching_signals = []
    matching_editor.configurationChanged.connect(lambda: matching_signals.append('aggregate'))
    for key in config_keys:
        getattr(matching_editor, 'cfg_' + key + 'Changed').connect(lambda: matching_signals.append('field'))
    pump()
    assert matching_signals == []
    for key in config_keys:
        assert matching_editor.property('cfg_' + key) == saved_profile[key]
    matching_editor.deleteLater()
    migrated_editor.deleteLater(); b.deleteLater()
    wallpaper.deleteLater()
    reopened.deleteLater()
    root.deleteLater(); window.close(); pump()
print('Passed: gallery selection, framing dialog drafts/OK/cancel, image/output guards, Qt UI, equal tab widths, independent edits, bidirectional copy, wheel events, host-map synchronization, save/reload, stale-schema guard, per-output restoration, cancelled edits and clean initialization/no-op actions. Native KDE services use stand-ins.')
