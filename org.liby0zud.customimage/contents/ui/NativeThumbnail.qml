import QtQuick

Image {
    property url thumbnail: ""
    property size targetSize: Qt.size(1920, 1080)
    source: thumbnail
    asynchronous: true
    retainWhileLoading: true
    cache: false
    fillMode: Image.PreserveAspectFit
    // The provider uses the requested ratio to select a package resolution.
    sourceSize: Qt.size(Math.max(1, Math.round(width * Screen.devicePixelRatio)),
                        Math.max(1, Math.round(width * targetSize.height / Math.max(1, targetSize.width) * Screen.devicePixelRatio)))
}
