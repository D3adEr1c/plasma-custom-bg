import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import "GalleryLogic.js" as GalleryLogic

Item {
    id: root
    property var wallpaperModel
    property string selectedImage: ""
    property size targetSize: Qt.size(1920, 1080)
    property bool loading: false
    signal wallpaperSelected(string key, var selectors)
    GridView {
        id: grid
        objectName: "wallpaperGrid"
        anchors.fill: parent
        clip: true
        model: root.wallpaperModel
        cellWidth: width / Math.max(1, Math.floor(width / 176))
        cellHeight: 152
        currentIndex: -1
        Controls.ScrollBar.vertical: Controls.ScrollBar {}
        delegate: Controls.ItemDelegate {
            id: tile
            required property var model
            required property int index
            // Plasma 6.7 exposes a source URL and a preview-provider URL.
            readonly property string key: String(model.source || "")
            readonly property var selectors: model.selectors || []
            width: grid.cellWidth - 8
            height: grid.cellHeight - 8
            highlighted: GalleryLogic.isSelected(root.selectedImage, key, "")
            Accessible.name: String(model.display || key)
            onClicked: { grid.currentIndex = index; root.wallpaperSelected(key, selectors); }
            contentItem: ColumnLayout {
                spacing: 4
                NativeThumbnail {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 60
                    thumbnail: tile.model.preview
                    targetSize: root.targetSize
                    objectName: "wallpaperThumbnail"
                }
                Controls.Label {
                    Layout.fillWidth: true
                    text: String(tile.model.display || tile.key)
                    horizontalAlignment: Text.AlignHCenter
                    color: tile.highlighted ? tile.palette.highlightedText : tile.palette.text
                    elide: Text.ElideRight
                }
                Controls.Label {
                    Layout.fillWidth: true
                    text: String(tile.model.author || "")
                    horizontalAlignment: Text.AlignHCenter
                    color: tile.highlighted ? tile.palette.highlightedText : tile.palette.text
                    elide: Text.ElideRight
                    opacity: 0.65
                    font.pointSize: Math.max(8, tile.font.pointSize - 1)
                }
            }
            Controls.ToolTip.visible: hovered
            Controls.ToolTip.text: String(model.display || key)
        }
    }
    Controls.BusyIndicator { anchors.centerIn: parent; running: root.loading; visible: running }
    Controls.Label {
        anchors.centerIn: parent
        width: Math.max(0, parent.width - 32)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        visible: !root.loading && grid.count === 0
        text: i18nd("plasma_wallpaper_org.liby0zud.customimage", "No wallpapers found. Add an image to get started.")
    }
}
