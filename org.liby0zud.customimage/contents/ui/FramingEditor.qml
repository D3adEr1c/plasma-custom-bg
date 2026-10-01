import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import "PreviewGeometry.js" as Geometry

Window {
    id: editor
    width: Math.min(760, Screen.desktopAvailableWidth || 760)
    height: Math.min(620, Screen.desktopAvailableHeight || 620)
    minimumWidth: 360
    minimumHeight: 320
    flags: Qt.Dialog
    modality: Qt.WindowModal
    color: theme.palette.window
    title: nightVariant ? i18nd("plasma_wallpaper_org.liby0zud.customimage", "Adjust night framing")
                        : i18nd("plasma_wallpaper_org.liby0zud.customimage", "Adjust day framing")
    property var targetGeometry: ({width: 1920, height: 1080, source: "placeholder"})
    property string image: ""
    property bool nightVariant: false
    property string output: ""
    property real draftZoom: 1
    property real draftX: 0.5
    property real draftY: 0.5
    signal framingAccepted(string image, real zoom, real x, real y, bool night, string output)
    function begin(source, zoom, x, y, night, display) {
        image = source;
        draftZoom = zoom; draftX = x; draftY = y;
        nightVariant = night; output = display;
        preview.resetWheelInput();
        show();
        requestActivate();
    }
    function accept() {
        framingAccepted(image, draftZoom, draftX, draftY, nightVariant, output);
        close();
    }
    Controls.Control { id: theme; visible: false }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 32
        spacing: 12
        Controls.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: editor.targetGeometry.source === "placeholder"
                ? i18nd("plasma_wallpaper_org.liby0zud.customimage", "Screen size is not ready. Showing a temporary 16:9 preview.")
                : (editor.output ? editor.output + " · " : "") + i18nd("plasma_wallpaper_org.liby0zud.customimage", "Target resolution: %1 × %2", Math.round(editor.targetGeometry.width), Math.round(editor.targetGeometry.height))
            wrapMode: Text.Wrap
        }
        Item {
            id: previewArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            readonly property var fitted: Geometry.fit(editor.targetGeometry, width, height)
            NativeWallpaperSource {
                id: imageSource
                source: editor.image
                targetSize: Qt.size(editor.targetGeometry.width * Screen.devicePixelRatio,
                                    editor.targetGeometry.height * Screen.devicePixelRatio)
            }
            PositionedImage {
                id: preview
                objectName: "preview"
                width: previewArea.fitted.width
                height: previewArea.fitted.height
                anchors.centerIn: parent
                imageUrl: imageSource.resolvedSource
                zoom: editor.draftZoom
                focusX: editor.draftX
                focusY: editor.draftY
                interactive: true
                onPositionEdited: (x, y) => { editor.draftX = x; editor.draftY = y; }
                onZoomEdited: value => editor.draftZoom = value
            }
        }
        Controls.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: i18nd("plasma_wallpaper_org.liby0zud.customimage", "Drag the image to frame it. Scroll to zoom.")
            wrapMode: Text.Wrap
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 10
            Controls.Label { text: i18nd("plasma_wallpaper_org.liby0zud.customimage", "Zoom:") }
            Controls.Slider {
                id: zoomControl
                Layout.preferredWidth: 170
                from: 1
                to: 3
                stepSize: 0.01
                snapMode: Controls.Slider.SnapAlways
                readonly property real tickInterval: 0.25
                readonly property int tickCount: Math.round((to - from) / tickInterval) + 1
                value: editor.draftZoom
                onMoved: editor.draftZoom = value

                // Paint the tick marks separately from the slider's input step.
                background: Item {
                    implicitWidth: 170
                    implicitHeight: 24
                    x: zoomControl.leftPadding + 8
                    y: zoomControl.topPadding + (zoomControl.availableHeight - height) / 2
                    width: Math.max(0, zoomControl.availableWidth - 16)
                    height: 24
                    Rectangle {
                        y: 8
                        width: parent.width
                        height: 4
                        radius: 2
                        color: zoomControl.palette.mid
                        Rectangle {
                            x: zoomControl.mirrored ? parent.width - width : 0
                            width: parent.width * zoomControl.position
                            height: parent.height
                            radius: 2
                            color: zoomControl.palette.highlight
                        }
                    }
                    Repeater {
                        model: zoomControl.tickCount
                        Rectangle {
                            required property int index
                            readonly property real tickPosition: index / (zoomControl.tickCount - 1)
                            x: (zoomControl.mirrored ? 1 - tickPosition : tickPosition) * parent.width - 0.5
                            y: 17
                            width: 1
                            height: 5
                            color: zoomControl.palette.mid
                        }
                    }
                }
                handle: Rectangle {
                    implicitWidth: 16
                    implicitHeight: 16
                    x: zoomControl.leftPadding + zoomControl.visualPosition * (zoomControl.availableWidth - width)
                    y: zoomControl.topPadding + (zoomControl.availableHeight - 24) / 2 + 2
                    radius: 8
                    color: zoomControl.pressed ? zoomControl.palette.highlight : zoomControl.palette.buttonText
                    border.width: zoomControl.activeFocus ? 2 : 0
                    border.color: zoomControl.palette.highlight
                }
            }
            Controls.Label {
                Layout.minimumWidth: 44
                horizontalAlignment: Text.AlignRight
                text: Math.round(editor.draftZoom * 100) + "%"
            }
            Controls.Button {
                text: i18nd("plasma_wallpaper_org.liby0zud.customimage", "Reset")
                onClicked: { editor.draftZoom = 1; editor.draftX = 0.5; editor.draftY = 0.5; }
            }
        }
        Controls.DialogButtonBox {
            Layout.fillWidth: true
            standardButtons: Controls.DialogButtonBox.Ok | Controls.DialogButtonBox.Cancel
            onAccepted: editor.accept()
            onRejected: editor.close()
        }
    }
    Shortcut { sequence: "Escape"; onActivated: editor.close() }
}
