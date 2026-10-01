import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import org.kde.plasma.plasmoid
import org.kde.kcmutils as KCM
import "AppearanceLogic.js" as AppearanceLogic
import "PreviewGeometry.js" as Geometry
import "OutputProfiles.js" as Profiles

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
    property bool restoringProfile: false
    property bool editorReady: false
    readonly property bool editingNight: variantTabs.currentIndex === 1
    onEditingNightChanged: preview.resetWheelInput()
    readonly property string currentImage: editingNight ? cfg_NightImage : cfg_Image
    readonly property real currentZoom: editingNight ? cfg_NightZoom : cfg_Zoom
    readonly property real currentFocusX: editingNight ? cfg_NightFocusX : cfg_FocusX
    readonly property real currentFocusY: editingNight ? cfg_NightFocusY : cfg_FocusY
    readonly property bool liveNight: AppearanceLogic.isNight(cfg_SwitchMode, appearance.cycleNight, appearance.darkTheme)

    readonly property bool settingsSchemaReady: hasProfileKeys(wallpaperConfiguration)
        && hasProfileKeys(desktopItem ? desktopItem.configuration : null)

    function hasProfileKeys(config) {
        if (!config) return true;
        const keys = config.keys();
        return ["NightImage", "NightZoom", "NightFocusX", "NightFocusY", "SwitchMode", "TargetOutput", "ProfileRevision"]
            .every(key => keys.indexOf(key) !== -1);
    }
    // Also notify hosts that use the aggregate signal to track edits.
    onCfg_ImageChanged: { if (!restoringProfile) configurationChanged(); }
    onCfg_ZoomChanged: { if (!restoringProfile) configurationChanged(); }
    onCfg_FocusXChanged: { if (!restoringProfile) configurationChanged(); }
    onCfg_FocusYChanged: { if (!restoringProfile) configurationChanged(); }
    onCfg_NightImageChanged: { if (!restoringProfile) configurationChanged(); }
    onCfg_NightZoomChanged: { if (!restoringProfile) configurationChanged(); }
    onCfg_NightFocusXChanged: { if (!restoringProfile) configurationChanged(); }
    onCfg_NightFocusYChanged: { if (!restoringProfile) configurationChanged(); }
    onCfg_SwitchModeChanged: { if (!restoringProfile) configurationChanged(); }
    onCfg_TargetOutputChanged: { if (!restoringProfile) configurationChanged(); }

    onCfg_ProfileRevisionChanged: { if (!restoringProfile) configurationChanged(); }

    function setImage(value, night) {
        claimTargetOutput();
        if (night) cfg_NightImage = value;
        else cfg_Image = value;
        touchProfile();
    }
    function setZoom(value) {
        claimTargetOutput();
        if (editingNight) cfg_NightZoom = value;
        else cfg_Zoom = value;
        touchProfile();
    }
    function setCurrentPosition(x, y) {
        claimTargetOutput();
        if (editingNight) { cfg_NightFocusX = x; cfg_NightFocusY = y; }
        else { cfg_FocusX = x; cfg_FocusY = y; }
        touchProfile();
    }
    function copyDayToNight() {
        claimTargetOutput();
        cfg_NightImage = cfg_Image;
        cfg_NightZoom = cfg_Zoom;
        cfg_NightFocusX = cfg_FocusX;
        cfg_NightFocusY = cfg_FocusY;
        touchProfile();
    }
    function copyNightToDay() {
        // An absent night image falls back to day; never erase day with it.
        if (!cfg_NightImage) return;
        claimTargetOutput();
        cfg_Image = cfg_NightImage;
        cfg_Zoom = cfg_NightZoom;
        cfg_FocusX = cfg_NightFocusX;
        cfg_FocusY = cfg_NightFocusY;
        touchProfile();
    }
    SystemAppearance {
        id: appearance
        monitorCycle: root.cfg_SwitchMode === 0
        initialState: root.cfg_ScheduleState
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
    Component.onCompleted: { editorReady = true; restoreTimer.restart(); }
    onHostOutputNameChanged: { if (editorReady) restoreTimer.restart(); }
    function restoreOutputProfile() {
        if (!hostOutputName || !settingsSchemaReady) return;
        const incoming = Profiles.snapshot(root, "cfg_");
        const stored = outputStore.read(hostOutputName);
        // Prefer saved output data over a migrated desktop's foreign settings.
        const chosen = stored && (incoming.TargetOutput !== hostOutputName
            || Profiles.revision(stored) >= Profiles.revision(incoming)) ? stored
            : incoming.TargetOutput && incoming.TargetOutput !== hostOutputName
                ? Profiles.defaults(hostOutputName) : null;
        if (!chosen) return;
        restoringProfile = true;
        Profiles.keys.forEach(key => root["cfg_" + key] = chosen[key]);
        restoringProfile = false;
        configurationChanged();
    }
    function claimTargetOutput() {
        // Finish pending restoration before editing a newly selected display.
        if (restoreTimer.running) { restoreTimer.stop(); restoreOutputProfile(); }
        if (targetOutputName && !previewOutputMissing) cfg_TargetOutput = targetOutputName;
    }
    function touchProfile() {
        cfg_ProfileRevision = String(Math.max(Date.now(), Profiles.revision(Profiles.snapshot(root, "cfg_")) + 1));
    }
    readonly property var targetGeometry: Geometry.resolve(screenSize, screen, desktopSize, fallbackScreen)
    readonly property bool automaticTarget: targetGeometry.source === "host" || targetGeometry.source === "desktop"

    // Keep the page compact even when the host gives it extra height.
    implicitWidth: 684
    implicitHeight: content.implicitHeight + 24 + (reloadNotice.visible ? reloadNotice.implicitHeight + 12 : 0)

    FileDialog {
        id: fileDialog
        property bool nightVariant: false
        title: i18nd("plasma_wallpaper_org.liby0zud.customimage", "Choose wallpaper")
        nameFilters: [i18nd("plasma_wallpaper_org.liby0zud.customimage", "Images (*.png *.jpg *.jpeg *.webp *.bmp *.avif)"), i18nd("plasma_wallpaper_org.liby0zud.customimage", "All files (*)")]
        onAccepted: root.setImage(selectedFile.toString(), nightVariant)
    }
    Controls.Label {
        id: reloadNotice
        anchors.top: parent.top
        anchors.topMargin: 12
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(620, Math.max(0, root.width - 64))
        visible: !root.settingsSchemaReady
        wrapMode: Text.Wrap
        text: i18nd("plasma_wallpaper_org.liby0zud.customimage", "The wallpaper configuration is from an older version. Close Settings, log out and log back in before editing day/night wallpapers.")
    }
    ColumnLayout {
        id: content
        enabled: root.settingsSchemaReady
        anchors.top: parent.top
        anchors.topMargin: reloadNotice.visible ? reloadNotice.implicitHeight + 24 : 12
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(620, Math.max(0, root.width - 64))
        spacing: 12

        GridLayout {
            columns: 2
            columnSpacing: 12
            Layout.fillWidth: true
            Controls.Label {
                text: i18nd("plasma_wallpaper_org.liby0zud.customimage", "Switch wallpapers:")
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
            Controls.ComboBox {
                Layout.fillWidth: true
                model: [
                    i18nd("plasma_wallpaper_org.liby0zud.customimage", "Follow system day/night cycle"),
                    i18nd("plasma_wallpaper_org.liby0zud.customimage", "Follow light/dark theme"),
                    i18nd("plasma_wallpaper_org.liby0zud.customimage", "Always day"),
                    i18nd("plasma_wallpaper_org.liby0zud.customimage", "Always night")
                ]
                currentIndex: root.cfg_SwitchMode
                onActivated: { root.claimTargetOutput(); root.cfg_SwitchMode = currentIndex; root.touchProfile(); }
            }
            Item { visible: root.cfg_SwitchMode === 0; implicitHeight: 1 }
            Controls.Button {
                visible: root.cfg_SwitchMode === 0
                text: i18nd("plasma_wallpaper_org.liby0zud.customimage", "Configure system day/night cycle…")
                onClicked: KCM.KCMLauncher.open("kcm_nighttime")
            }
        }
        Controls.Button {
            visible: root.hostOutputName && root.cfg_TargetOutput !== root.hostOutputName
            Layout.alignment: Qt.AlignHCenter
            text: i18nd("plasma_wallpaper_org.liby0zud.customimage", "Bind settings to %1", root.hostOutputName)
            onClicked: { root.claimTargetOutput(); root.touchProfile(); }
        }
        Controls.TabBar {
            id: variantTabs
            implicitWidth: 240
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 240
            Layout.maximumWidth: content.width
            Controls.TabButton {
                objectName: "dayTab"
                width: variantTabs.width / 2
                text: i18nd("plasma_wallpaper_org.liby0zud.customimage", "Day")
            }
            Controls.TabButton {
                objectName: "nightTab"
                width: variantTabs.width / 2
                text: i18nd("plasma_wallpaper_org.liby0zud.customimage", "Night")
            }
        }
        GridLayout {
            columns: 2
            columnSpacing: 12
            rowSpacing: 10
            Layout.fillWidth: true
            Controls.Label {
                text: i18nd("plasma_wallpaper_org.liby0zud.customimage", "Image:")
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
            RowLayout {
                Layout.fillWidth: true
                Controls.TextField {
                    id: imagePath
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: root.currentImage
                    placeholderText: i18nd("plasma_wallpaper_org.liby0zud.customimage", "Image file path")
                    onTextEdited: root.setImage(text, root.editingNight)
                }
                Controls.Button { text: i18nd("plasma_wallpaper_org.liby0zud.customimage", "Browse…"); onClicked: { fileDialog.nightVariant = root.editingNight; fileDialog.open(); } }
            }
            Controls.Label {
                visible: !root.automaticTarget
                text: i18nd("plasma_wallpaper_org.liby0zud.customimage", "Preview screen:")
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
            Controls.ComboBox {
                id: screenChoice
                visible: !root.automaticTarget
                Layout.fillWidth: true
                textRole: "label"
                valueRole: "name"
                model: root.screens.map(s => ({ name: s.name, label: s.name + " (" + s.width + " × " + s.height + ")" }))
                currentIndex: indexOfValue(root.selectedPreviewOutput)
                onActivated: root.selectedPreviewOutput = currentValue
            }
        }
        Item {
            id: previewArea
            Layout.fillWidth: true
            Layout.preferredHeight: fitted.height
            Layout.minimumHeight: fitted.height
            Layout.maximumHeight: fitted.height
            readonly property var fitted: Geometry.fit(root.targetGeometry, width > 0 ? width : 620, 380)
            PositionedImage {
                id: preview
                width: previewArea.fitted.width
                height: previewArea.fitted.height
                anchors.centerIn: parent
                imageUrl: root.currentImage
                zoom: root.currentZoom
                focusX: root.currentFocusX
                focusY: root.currentFocusY
                interactive: !root.previewOutputMissing
                onPositionEdited: (x, y) => root.setCurrentPosition(x, y)
                onZoomEdited: value => root.setZoom(value)
            }
        }
        Controls.Label {
            visible: root.previewOutputMissing
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: i18nd("plasma_wallpaper_org.liby0zud.customimage", "The selected preview display is disconnected. Select a connected display.")
        }
        Controls.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: root.liveNight
                ? i18nd("plasma_wallpaper_org.liby0zud.customimage", "Currently active: Night")
                : i18nd("plasma_wallpaper_org.liby0zud.customimage", "Currently active: Day")
        }
        Controls.Label {
            visible: root.editingNight && !root.cfg_NightImage
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: i18nd("plasma_wallpaper_org.liby0zud.customimage", "No night image selected. The desktop will use the day image and framing.")
        }
        Controls.Button {
            objectName: "profileCopy"
            Layout.alignment: Qt.AlignHCenter
            enabled: root.editingNight || !!root.cfg_NightImage
            text: root.editingNight
                ? i18nd("plasma_wallpaper_org.liby0zud.customimage", "Copy day settings to night")
                : i18nd("plasma_wallpaper_org.liby0zud.customimage", "Copy night settings to day")
            onClicked: {
                if (root.editingNight) root.copyDayToNight();
                else root.copyNightToDay();
            }
            Controls.ToolTip.visible: hovered && !enabled
            Controls.ToolTip.text: i18nd("plasma_wallpaper_org.liby0zud.customimage", "Choose a night image before copying its settings to day.")
        }
        Controls.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: root.targetGeometry.source === "placeholder"
                ? i18nd("plasma_wallpaper_org.liby0zud.customimage", "Screen size is not ready. Showing a temporary 16:9 preview.")
                : (root.automaticTarget ? i18nd("plasma_wallpaper_org.liby0zud.customimage", "Target resolution: %1 × %2", Math.round(root.targetGeometry.width), Math.round(root.targetGeometry.height))
                    : i18nd("plasma_wallpaper_org.liby0zud.customimage", "Preview resolution: %1 × %2", Math.round(root.targetGeometry.width), Math.round(root.targetGeometry.height)))
        }
        Controls.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: i18nd("plasma_wallpaper_org.liby0zud.customimage", "Drag the image to frame it. Scroll to zoom.")
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
                value: root.currentZoom
                onMoved: root.setZoom(value)

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
                text: Math.round(root.currentZoom * 100) + "%"
            }
            Controls.Button {
                text: i18nd("plasma_wallpaper_org.liby0zud.customimage", "Reset")
                onClicked: { root.setZoom(1); root.setCurrentPosition(0.5, 0.5); }
            }
        }
    }
}
