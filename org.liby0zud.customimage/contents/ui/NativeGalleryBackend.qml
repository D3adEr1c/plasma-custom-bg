import QtQuick
import org.kde.plasma.wallpapers.image as PlasmaWallpaper
import "GalleryLogic.js" as GalleryLogic

Item {
    id: root
    property size targetSize: Qt.size(1920, 1080)
    readonly property var wallpaperModel: backend.wallpaperModel
    readonly property bool loading: backend.loading
    property var selectedImages: []
    onSelectedImagesChanged: syncTimer.restart()
    onLoadingChanged: if (!loading) syncTimer.restart()
    Component.onCompleted: syncTimer.restart()
    Timer { id: syncTimer; interval: 100; onTriggered: root.includeSelections() }
    PlasmaWallpaper.ImageBackend {
        id: backend
        usedInConfig: true
        renderingMode: PlasmaWallpaper.ImageBackend.SingleImage
        targetSize: root.targetSize
    }
    function add(url) {
        const key = backend.addUsersWallpaper(url);
        if (key) return key;
        return backend.wallpaperModel.indexOf(GalleryLogic.baseKey(url)) >= 0 ? String(url) : "";
    }
    function includeSelections() {
        if (loading) return;
        selectedImages.forEach(source => {
            if (source && backend.wallpaperModel.indexOf(GalleryLogic.baseKey(source)) < 0)
                backend.addUsersWallpaper(source.split(/[?#]/)[0]);
        });
    }
    function commit() { backend.wallpaperModel.commitAddition(); }
    function reload() { backend.wallpaperModel.reload(); }
    function wallpaperUrl(key, selectors, night) {
        if (typeof backend.makeWallpaperUrl === "function") {
            // Pin package variants to this profile; our scheduler owns switching.
            if (backend.dynamicMode !== undefined)
                backend.dynamicMode = night ? PlasmaWallpaper.DynamicMode.AlwaysDark : PlasmaWallpaper.DynamicMode.AlwaysLight;
            return backend.makeWallpaperUrl(key, selectors).toString();
        }
        return key.toString();
    }
}
