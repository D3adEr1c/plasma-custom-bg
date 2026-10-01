"""Test the real Qt appearance component (requires PySide6 Essentials).
The colorScheme input is injected; palette changes are real Qt application changes.
"""
import os
os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
from pathlib import Path
from PySide6.QtCore import Qt, QUrl, QObject
from PySide6.QtGui import QGuiApplication, QPalette, QColor
from PySide6.QtQml import QQmlEngine, QQmlComponent

app = QGuiApplication([])
engine = QQmlEngine()
source = Path(__file__).resolve().parent.parent / 'org.liby0zud.customimage/contents/ui'
component = QQmlComponent(engine, QUrl.fromLocalFile(str(source / 'ThemeState.qml')))
assert not component.isError(), [e.toString() for e in component.errors()]
state = component.create()
assert state is not None, [e.toString() for e in component.errors()]
initial = app.styleHints().colorScheme().value
assert state.property('colorScheme') == initial
changes = []
state.darkChanged.connect(lambda: changes.append(state.property('dark')))

def palette(background, foreground):
    colors = QPalette()
    colors.setColor(QPalette.Window, QColor(background))
    colors.setColor(QPalette.WindowText, QColor(foreground))
    app.setPalette(colors)
    for _ in range(5): app.processEvents()

# System preference wins even if the application palette has the opposite appearance.
palette('#202020', '#eeeeee')
state.setProperty('colorScheme', Qt.Light.value)
assert state.property('dark') is False
palette('#eeeeee', '#202020')
state.setProperty('colorScheme', Qt.Dark.value)
assert state.property('dark') is True
for value in [Qt.Light, Qt.Dark, Qt.Light, Qt.Dark]:
    state.setProperty('colorScheme', value.value)
    assert state.property('dark') == (value == Qt.Dark)
assert changes[-4:] == [False, True, False, True]

# Unknown preference follows actual palette notifications without recreating the component.
state.setProperty('colorScheme', Qt.Unknown.value)
palette('#eeeeee', '#202020'); assert state.property('dark') is False
palette('#202020', '#eeeeee'); assert state.property('dark') is True
palette('#eeeeee', '#202020'); assert state.property('dark') is False

# Use the real appearance state to drive the same profile-selection bindings as the wallpaper.
check = QQmlComponent(engine)
check.setData(b'''import QtQuick
import "AppearanceLogic.js" as Logic
QtObject {
 property var appearance
 property int mode: 1
 property var config: ({Image: "day.png", NightImage: "night.png", Zoom: 1.5, NightZoom: 2.1})
 readonly property bool night: Logic.isNight(mode, false, appearance ? appearance.dark : false)
 readonly property string image: Logic.profile(config, night).image
}
''', QUrl.fromLocalFile(str(source / 'ThemeCheck.qml')))
assert not check.isError(), [e.toString() for e in check.errors()]
wallpaper = check.createWithInitialProperties({'appearance': state})
assert wallpaper is not None
for value, expected in [(Qt.Light, 'day.png'), (Qt.Dark, 'night.png'), (Qt.Light, 'day.png')]:
    state.setProperty('colorScheme', value.value)
    assert wallpaper.property('image') == expected
wallpaper.setProperty('mode', 2)
state.setProperty('colorScheme', Qt.Dark.value)
assert wallpaper.property('image') == 'day.png'
wallpaper.setProperty('mode', 3)
state.setProperty('colorScheme', Qt.Light.value)
assert wallpaper.property('image') == 'night.png'
print('Passed: real ThemeState, system-preference priority, repeated changes, live palette fallback and day/night binding selection.')
