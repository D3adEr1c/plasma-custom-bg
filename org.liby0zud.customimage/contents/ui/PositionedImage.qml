import QtQuick
import "ZoomInput.js" as ZoomInput

Item {
    id: viewport
    clip: true
    property url imageUrl: ""
    property real zoom: 1.0
    // 0 is the start of the overflow; 1 is its end.
    property real focusX: 0.5
    property real focusY: 0.5
    property bool interactive: false
    signal positionEdited(real focusX, real focusY)
    signal zoomEdited(real zoom)

    function clamp(value, low, high) { return Math.max(low, Math.min(high, value)); }
    readonly property real baseScale: picture.implicitWidth > 0 && picture.implicitHeight > 0
                                      && width > 0 && height > 0
                                      ? Math.max(width / picture.implicitWidth, height / picture.implicitHeight) : 1
    readonly property real drawnWidth: picture.implicitWidth * baseScale * zoom
    readonly property real drawnHeight: picture.implicitHeight * baseScale * zoom
    readonly property real overflowX: Math.max(0, drawnWidth - width)
    readonly property real overflowY: Math.max(0, drawnHeight - height)

    Rectangle { anchors.fill: parent; color: "#202124" }
    Image {
        id: picture
        source: viewport.imageUrl
        width: viewport.drawnWidth
        height: viewport.drawnHeight
        x: -viewport.overflowX * viewport.clamp(viewport.focusX, 0, 1)
        y: -viewport.overflowY * viewport.clamp(viewport.focusY, 0, 1)
        fillMode: Image.Stretch
        asynchronous: true
        cache: true
        visible: status === Image.Ready
    }
    Text {
        anchors.centerIn: parent
        visible: picture.status !== Image.Ready
        text: picture.status === Image.Error ? i18nd("plasma_wallpaper_org.liby0zud.customimage", "Cannot load image") : i18nd("plasma_wallpaper_org.liby0zud.customimage", "Choose an image")
        color: "white"
    }
    function resetWheelInput() { wheelArea.remainder = 0; }
    onImageUrlChanged: resetWheelInput()
    DragHandler {
        id: pan
        enabled: viewport.interactive && picture.status === Image.Ready
        target: null
        property real startX: 0
        property real startY: 0
        onActiveChanged: if (active) { startX = viewport.focusX; startY = viewport.focusY; }
        onTranslationChanged: {
            if (!active) return;
            viewport.positionEdited(
                viewport.overflowX > 0 ? viewport.clamp(startX - translation.x / viewport.overflowX, 0, 1) : 0.5,
                viewport.overflowY > 0 ? viewport.clamp(startY - translation.y / viewport.overflowY, 0, 1) : 0.5);
        }
    }
    MouseArea {
        id: wheelArea
        anchors.fill: parent
        enabled: viewport.interactive && picture.status === Image.Ready
        // Handle wheel events over the preview without consuming drag presses.
        acceptedButtons: Qt.NoButton
        scrollGestureEnabled: true
        property real remainder: 0
        onEnabledChanged: remainder = 0
        onWheel: wheel => {
            const result = ZoomInput.advance(viewport.zoom, remainder,
                                             wheel.angleDelta.y, wheel.pixelDelta.y);
            remainder = result.remainder;
            if (result.zoom !== viewport.zoom)
                viewport.zoomEdited(result.zoom);
            wheel.accepted = true;
        }
    }
}
