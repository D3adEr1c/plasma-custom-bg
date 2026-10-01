import QtQuick
import org.kde.plasma.wallpapers.image as PlasmaWallpaper

Item {
    id: root
    property string source: ""
    property size targetSize: Qt.size(1920, 1080)
    readonly property url resolvedSource: source ? proxy.modelImage : ""
    PlasmaWallpaper.MediaProxy {
        id: proxy
        source: root.source
        targetSize: root.targetSize
    }
}
