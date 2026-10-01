import QtQuick
import org.kde.plasma.plasmoid
import "AppearanceLogic.js" as AppearanceLogic
import "OutputProfiles.js" as Profiles

WallpaperItem {
    id: root
    readonly property var outputWindow: Window.window
    readonly property string outputName: outputWindow ? Screen.name : ""
    property string legacyOutput: ""
    property var effectiveConfiguration: Profiles.defaults("")
    readonly property bool correctOutput: !!outputName && effectiveConfiguration.TargetOutput === outputName
    readonly property string configurationSerial: JSON.stringify(Profiles.snapshot(root.configuration, ""))
    onConfigurationSerialChanged: refreshTimer.restart()
    onOutputNameChanged: refreshTimer.restart()
    Component.onCompleted: refreshTimer.restart()
    function refreshProfile() {
        if (!outputName || !root.configuration || root.configuration.Image === undefined) return;
        const incoming = Profiles.snapshot(root.configuration, "");
        // Untagged legacy data can seed only the first attached output.
        if (!legacyOutput && !incoming.TargetOutput) legacyOutput = outputName;
        const stored = outputStore.read(outputName);
        const chosen = Profiles.select(outputName, incoming, stored, legacyOutput);
        if (chosen) {
            outputStore.write(outputName, chosen);
            if (JSON.stringify(effectiveConfiguration) !== JSON.stringify(chosen))
                effectiveConfiguration = chosen;
        } else {
            effectiveConfiguration = Profiles.defaults("");
        }
    }
    OutputStore { id: outputStore }
    // Coalesce a host Apply's individual property notifications into one record.
    Timer { id: refreshTimer; interval: 100; onTriggered: root.refreshProfile() }
    Timer { interval: 1000; running: true; repeat: true; onTriggered: { if (!refreshTimer.running) root.refreshProfile(); } }
    readonly property bool night: AppearanceLogic.isNight(effectiveConfiguration.SwitchMode,
                                                         appearance.cycleNight, appearance.darkTheme)
    readonly property var dayProfile: AppearanceLogic.profile(effectiveConfiguration, false)
    readonly property var nightProfile: AppearanceLogic.profile(effectiveConfiguration, true)
    SystemAppearance {
        id: appearance
        monitorCycle: root.effectiveConfiguration.SwitchMode === 0
        initialState: root.effectiveConfiguration.ScheduleState || ""
        // The wallpaper host owns Apply and persistence. Do not write the
        // whole configuration while a switching-mode update is being applied.
    }
    NativeWallpaperSource {
        id: daySource
        source: root.dayProfile.image
        targetSize: Qt.size(root.width * Screen.devicePixelRatio, root.height * Screen.devicePixelRatio)
    }
    NativeWallpaperSource {
        id: nightSource
        source: root.nightProfile.image
        targetSize: daySource.targetSize
    }
    PositionedImage {
        anchors.fill: parent
        visible: root.correctOutput && !root.night
        imageUrl: daySource.resolvedSource
        zoom: root.dayProfile.zoom
        focusX: root.dayProfile.focusX
        focusY: root.dayProfile.focusY
    }
    // Load both files before a scheduled switch to avoid reloading the image at that moment.
    PositionedImage {
        anchors.fill: parent
        visible: root.correctOutput && root.night
        imageUrl: nightSource.resolvedSource
        zoom: root.nightProfile.zoom
        focusX: root.nightProfile.focusX
        focusY: root.nightProfile.focusY
    }
    Rectangle {
        anchors.fill: parent
        visible: !root.correctOutput
        color: "#202124"
        Text {
            anchors.centerIn: parent
            width: Math.min(parent.width - 48, 640)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: "white"
            text: i18nd("plasma_wallpaper_org.liby0zud.customimage", "No saved wallpaper for this display. Choose an image in wallpaper settings.")
        }
    }
}
