import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import org.kde.plasma.plasmoid
import org.kde.kcmutils as KCM
import "AppearanceLogic.js" as AppearanceLogic
import "PreviewGeometry.js" as Geometry
import "OutputProfiles.js" as Profiles
import "GalleryLogic.js" as GalleryLogic

Item {
    id: root
    property string cfg_Image: ""
    property real cfg_Zoom: 1.0
    property real cfg_FocusX: 0.5
    property real cfg_FocusY: 0.5

    property string cfg_NightImage: ""
    property real cfg_NightZoom: 1.0
    property real cfg_NightFocusX: 0.5
    property real cfg_NightFocusY: 0.5
    property int cfg_SwitchMode: 2
    property string cfg_ScheduleState: ""
    property string cfg_TargetOutput: ""
    property string cfg_ProfileRevision: "0"
    property bool applyingEdit: false
    property var restoredProfile: null
    readonly property var editorProfile: restoredProfile || Profiles.snapshot(root, "cfg_")
    property bool editorReady: false
    property bool variantSelectedByUser: false
    function selectDefaultVariant() {
        if (editorReady && !variantSelectedByUser) variantTabs.currentIndex = liveNight ? 1 : 0;
    }
    readonly property bool editingNight: variantTabs.currentIndex === 1
    onEditingNightChanged: framing.close()
    readonly property string currentImage: editingNight ? editorProfile.NightImage : editorProfile.Image
    readonly property real currentZoom: editingNight ? editorProfile.NightZoom : editorProfile.Zoom
    readonly property real currentFocusX: editingNight ? editorProfile.NightFocusX : editorProfile.FocusX
    readonly property real currentFocusY: editingNight ? editorProfile.NightFocusY : editorProfile.FocusY
    readonly property bool liveNight: AppearanceLogic.isNight(editorProfile.SwitchMode, appearance.cycleNight, appearance.darkTheme)
    onLiveNightChanged: selectDefaultVariant()

    readonly property bool settingsSchemaReady: hasProfileKeys(wallpaperConfiguration)
        && hasProfileKeys(desktopItem ? desktopItem.configuration : null)

    function hasProfileKeys(config) {
        if (!config) return true;
        const keys = config.keys();
        return ["NightImage", "NightZoom", "NightFocusX", "NightFocusY", "SwitchMode", "TargetOutput", "ProfileRevision"]
            .every(key => keys.indexOf(key) !== -1);
    }
    // Host initialization/reloads are not user edits. Notify only after a
    // complete, actual change, never from cfg_<key> change handlers.
    function setImage(value, night) {
        finishPendingRestore();
        if (value === (night ? editorProfile.NightImage : editorProfile.Image)) return;
        claimTargetOutput();
        if (night) cfg_NightImage = value;
        else cfg_Image = value;
        touchProfile();
    }
    function setZoom(value) {
        finishPendingRestore();
        if (value === currentZoom) return;
        claimTargetOutput();
        if (editingNight) cfg_NightZoom = value;
        else cfg_Zoom = value;
        touchProfile();
    }
    function setCurrentPosition(x, y) {
        finishPendingRestore();
        if (x === currentFocusX && y === currentFocusY) return;
        claimTargetOutput();
        if (editingNight) { cfg_NightFocusX = x; cfg_NightFocusY = y; }
        else { cfg_FocusX = x; cfg_FocusY = y; }
        touchProfile();
    }
    function setSwitchMode(value) {
        finishPendingRestore();
        if (value === editorProfile.SwitchMode) return;
        claimTargetOutput();
        cfg_SwitchMode = value;
        touchProfile();
    }
    function copyDayToNight() { copyProfile(true); }
    function copyNightToDay() { copyProfile(false); }
    function copyProfile(toNight) {
        finishPendingRestore();
        const profile = editorProfile;
        if (!toNight && !profile.NightImage) return;
        const source = toNight ? "" : "Night";
        const target = toNight ? "Night" : "";
        const fields = ["Image", "Zoom", "FocusX", "FocusY"];
        if (fields.every(key => profile[source + key] === profile[target + key])) return;
        claimTargetOutput();
        fields.forEach(key => root["cfg_" + target + key] = profile[source + key]);
        touchProfile();
    }
    SystemAppearance {
        id: appearance
        monitorCycle: root.editorProfile.SwitchMode === 0
        initialState: root.editorProfile.ScheduleState
    }

    // Plasma injects these properties when constructing the configuration page.
    property var configDialog
    property var wallpaperConfiguration
    property var parentLayout
    property var screenSize: Qt.size(0, 0)
    property var screen: null
    signal configurationChanged()

    readonly property var desktopItem: {
        try { return Plasmoid.wallpaperGraphicsObject || null; }
        catch (error) { return null; }
    }
    readonly property var desktopSize: desktopItem
        ? Qt.size(desktopItem.width, desktopItem.height) : Qt.size(0, 0)
    readonly property var screens: Qt.application.screens
    property string selectedPreviewOutput: ""
    readonly property var fallbackScreen: Geometry.findOutput(screens, selectedPreviewOutput)
    readonly property string hostOutputName: {
        if (screen && screen.name) return screen.name;
        try {
            const window = desktopItem ? desktopItem.Window.window : null;
            return window && window.screen ? window.screen.name : "";
        } catch (error) { return ""; }
    }
    readonly property string targetOutputName: hostOutputName
    readonly property bool previewOutputMissing: !!selectedPreviewOutput && !fallbackScreen && !hostOutputName
    OutputStore { id: outputStore }
    Timer { id: restoreTimer; interval: 50; onTriggered: root.restoreOutputProfile() }
    readonly property string configurationSerial: JSON.stringify(Profiles.snapshot(root, "cfg_"))
    onConfigurationSerialChanged: {
        if (editorReady && !applyingEdit) restoreTimer.restart();
    }
    Component.onCompleted: { editorReady = true; selectDefaultVariant(); restoreTimer.restart(); }
    onHostOutputNameChanged: {
        framing.close();
        variantSelectedByUser = false;
        if (editorReady) restoreTimer.restart();
    }
    function restoreOutputProfile() {
        if (!hostOutputName || !settingsSchemaReady) { restoredProfile = null; selectDefaultVariant(); return; }
        const incoming = Profiles.snapshot(root, "cfg_");
        const stored = outputStore.read(hostOutputName);
        // Prefer saved output data over a migrated desktop's foreign settings.
        const chosen = stored && (incoming.TargetOutput !== hostOutputName
            || Profiles.revision(stored) >= Profiles.revision(incoming)) ? stored
            : incoming.TargetOutput && incoming.TargetOutput !== hostOutputName
                ? Profiles.defaults(hostOutputName) : null;
        // Keep restored data in the editor view. Assigning cfg_ properties here
        // also dirties hosts that listen to each individual property signal.
        restoredProfile = chosen && JSON.stringify(chosen) !== JSON.stringify(incoming) ? chosen : null;
        selectDefaultVariant();
    }
    function finishPendingRestore() {
        if (restoreTimer.running) { restoreTimer.stop(); restoreOutputProfile(); }
    }
    function claimTargetOutput() {
        finishPendingRestore();
        applyingEdit = true;
        const profile = editorProfile;
        Profiles.keys.forEach(key => root["cfg_" + key] = profile[key]);
        restoredProfile = null;
        if (targetOutputName && !previewOutputMissing) cfg_TargetOutput = targetOutputName;
    }
    function touchProfile() {
        cfg_ProfileRevision = String(Math.max(Date.now(), Profiles.revision(Profiles.snapshot(root, "cfg_")) + 1));
        applyingEdit = false;
        configurationChanged();
    }
    readonly property var targetGeometry: Geometry.resolve(screenSize, screen, desktopSize, fallbackScreen)
    readonly property bool automaticTarget: targetGeometry.source === "host" || targetGeometry.source === "desktop"

    implicitWidth: 760
    implicitHeight: 600

    NativeGalleryBackend {
        id: galleryBackend
        selectedImages: [root.editorProfile.Image, root.editorProfile.NightImage]
        targetSize: Qt.size(root.targetGeometry.width * Screen.devicePixelRatio,
                            root.targetGeometry.height * Screen.devicePixelRatio)
    }
    // Called by the wallpaper host after Apply, as for the Image wallpaper.
    function saveConfig() { galleryBackend.commit(); }
    function chooseWallpaper(key, selectors) {
        root.setImage(galleryBackend.wallpaperUrl(key, selectors || [], root.editingNight), root.editingNight);
    }
    function addWallpaper(url, night) {
        const key = galleryBackend.add(url);
        if (key) root.setImage(galleryBackend.wallpaperUrl(key, [], night), night);
    }
    function openFraming() {
        finishPendingRestore();
        if (!currentImage || previewOutputMissing || !settingsSchemaReady) return;
        framing.begin(currentImage, currentZoom, currentFocusX, currentFocusY, editingNight, targetOutputName);
    }
    function acceptFraming(image, zoom, x, y, night, output) {
        finishPendingRestore();
        const prefix = night ? "Night" : "";
        const profile = editorProfile;
        // A dialog belongs to the image and monitor it was opened for.
        if (output !== targetOutputName || profile[prefix + "Image"] !== image) return;
        if (profile[prefix + "Zoom"] === zoom && profile[prefix + "FocusX"] === x && profile[prefix + "FocusY"] === y) return;
        claimTargetOutput();
        root["cfg_" + prefix + "Zoom"] = zoom;
        root["cfg_" + prefix + "FocusX"] = x;
        root["cfg_" + prefix + "FocusY"] = y;
        touchProfile();
    }
    FramingEditor {
        id: framing
        objectName: "framingEditor"
        transientParent: root.Window.window
        targetGeometry: root.targetGeometry
        onFramingAccepted: (image, zoom, x, y, night, output) => root.acceptFraming(image, zoom, x, y, night, output)
    }
    FileDialog {
        id: fileDialog
        property bool nightVariant: false
        title: i18nd("plasma_wallpaper_org.liby0zud.customimage", "Choose wallpaper")
        nameFilters: [i18nd("plasma_wallpaper_org.liby0zud.customimage", "Images (*.png *.jpg *.jpeg *.webp *.bmp *.avif)"), i18nd("plasma_wallpaper_org.liby0zud.customimage", "All files (*)")]
        onAccepted: root.addWallpaper(selectedFile, nightVariant)
    }
    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 32
        spacing: 12
        Controls.Label {
            id: reloadNotice
            visible: !root.settingsSchemaReady
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: i18nd("plasma_wallpaper_org.liby0zud.customimage", "The wallpaper configuration is from an older version. Close Settings, log out and log back in before editing day/night wallpapers.")
        }
        GridLayout {
            enabled: root.settingsSchemaReady
            columns: 2
            columnSpacing: 12
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(620, content.width)
            Layout.maximumWidth: Math.min(620, content.width)
            Controls.Label {
                text: i18nd("plasma_wallpaper_org.liby0zud.customimage", "Switch wallpapers:")
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
            Controls.ComboBox {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                implicitWidth: 380
                model: [
                    i18nd("plasma_wallpaper_org.liby0zud.customimage", "Follow system day/night cycle"),
                    i18nd("plasma_wallpaper_org.liby0zud.customimage", "Follow light/dark theme"),
                    i18nd("plasma_wallpaper_org.liby0zud.customimage", "Always day"),
                    i18nd("plasma_wallpaper_org.liby0zud.customimage", "Always night")
                ]
                currentIndex: root.editorProfile.SwitchMode
                onActivated: root.setSwitchMode(currentIndex)
            }
            Item { visible: root.editorProfile.SwitchMode === 0; implicitHeight: 1 }
            Controls.Button {
                visible: root.editorProfile.SwitchMode === 0
                text: i18nd("plasma_wallpaper_org.liby0zud.customimage", "Configure system day/night cycle…")
                onClicked: KCM.KCMLauncher.open("kcm_nighttime")
            }
            Controls.Label {
                visible: !root.automaticTarget
                text: i18nd("plasma_wallpaper_org.liby0zud.customimage", "Preview screen:")
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
            Controls.ComboBox {
                visible: !root.automaticTarget
                Layout.fillWidth: true
                textRole: "label"
                valueRole: "name"
                model: root.screens.map(s => ({ name: s.name, label: s.name + " (" + s.width + " × " + s.height + ")" }))
                currentIndex: indexOfValue(root.selectedPreviewOutput)
                onActivated: { framing.close(); root.selectedPreviewOutput = currentValue; }
            }
        }
        Controls.Button {
            visible: root.hostOutputName && root.editorProfile.TargetOutput !== root.hostOutputName
            enabled: root.settingsSchemaReady
            Layout.alignment: Qt.AlignHCenter
            text: i18nd("plasma_wallpaper_org.liby0zud.customimage", "Bind settings to %1", root.hostOutputName)
            onClicked: { root.claimTargetOutput(); root.touchProfile(); }
        }
        Controls.TabBar {
            id: variantTabs
            implicitWidth: 240
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(240, content.width)
            Controls.TabButton { objectName: "dayTab"; width: variantTabs.width / 2; text: i18nd("plasma_wallpaper_org.liby0zud.customimage", "Day"); onClicked: root.variantSelectedByUser = true }
            Controls.TabButton { objectName: "nightTab"; width: variantTabs.width / 2; text: i18nd("plasma_wallpaper_org.liby0zud.customimage", "Night"); onClicked: root.variantSelectedByUser = true }
        }
        RowLayout {
            Layout.fillWidth: true
            enabled: root.settingsSchemaReady
            Controls.Label {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideMiddle
                text: root.currentImage ? GalleryLogic.fileLabel(root.currentImage)
                    : i18nd("plasma_wallpaper_org.liby0zud.customimage", "Choose an image")
                Controls.ToolTip.visible: selectedPathHover.hovered
                Controls.ToolTip.text: root.currentImage
                HoverHandler { id: selectedPathHover }
            }
            Controls.Button {
                objectName: "adjustFraming"
                text: i18nd("plasma_wallpaper_org.liby0zud.customimage", "Adjust framing…")
                enabled: !!root.currentImage && !root.previewOutputMissing
                onClicked: root.openFraming()
            }
            Controls.Button {
                objectName: "profileCopy"
                enabled: root.editingNight || !!root.editorProfile.NightImage
                text: root.editingNight
                    ? i18nd("plasma_wallpaper_org.liby0zud.customimage", "Copy day settings to night")
                    : i18nd("plasma_wallpaper_org.liby0zud.customimage", "Copy night settings to day")
                onClicked: { if (root.editingNight) root.copyDayToNight(); else root.copyNightToDay(); }
                Controls.ToolTip.visible: hovered && !enabled
                Controls.ToolTip.text: i18nd("plasma_wallpaper_org.liby0zud.customimage", "Choose a night image before copying its settings to day.")
            }
        }
        Controls.Label {
            visible: root.editingNight && !root.editorProfile.NightImage
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: i18nd("plasma_wallpaper_org.liby0zud.customimage", "No night image selected. The desktop will use the day image and framing.")
        }
        Controls.Label {
            visible: root.previewOutputMissing
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: i18nd("plasma_wallpaper_org.liby0zud.customimage", "The selected preview display is disconnected. Select a connected display.")
        }
        Controls.Frame {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 180
            padding: 8
            WallpaperGallery {
                anchors.fill: parent
                enabled: root.settingsSchemaReady
                wallpaperModel: galleryBackend.wallpaperModel
                selectedImage: root.currentImage
                targetSize: galleryBackend.targetSize
                loading: galleryBackend.loading
                onWallpaperSelected: (key, selectors) => root.chooseWallpaper(key, selectors)
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Controls.Label {
                Layout.fillWidth: true
                text: root.liveNight ? i18nd("plasma_wallpaper_org.liby0zud.customimage", "Currently active: Night")
                                    : i18nd("plasma_wallpaper_org.liby0zud.customimage", "Currently active: Day")
            }
            Controls.Button {
                text: i18nd("plasma_wallpaper_org.liby0zud.customimage", "Add…")
                enabled: root.settingsSchemaReady
                icon.name: "list-add"
                onClicked: { fileDialog.nightVariant = root.editingNight; fileDialog.open(); }
            }
            GetNewWallpapersButton { onWallpapersChanged: galleryBackend.reload() }
        }
    }
}
