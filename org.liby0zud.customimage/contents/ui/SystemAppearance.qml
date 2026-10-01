import QtQuick
import org.kde.plasma.wallpapers.image as PlasmaWallpaper
import "AppearanceLogic.js" as AppearanceLogic

Item {
    id: root
    visible: false
    property bool monitorCycle: false
    property string initialState: ""
    readonly property string state: cycleLoader.item ? cycleLoader.item.state : ""
    readonly property bool cycleNight: cycleLoader.item ? cycleLoader.item.night : false
    readonly property bool darkTheme: themeState.dark
    ThemeState { id: themeState }

    Loader {
        id: cycleLoader
        active: root.monitorCycle
        sourceComponent: Component {
            Item {
                readonly property string state: schedule.state
                readonly property bool night: AppearanceLogic.snapshotIsNight(schedule.snapshot)
                // Reuse Plasma's scheduler, including clock/timezone changes and
                // sunrise/sunset timings. Only its snapshot is read; no package
                // image URLs are rendered. Switch halfway through dawn/dusk.
                PlasmaWallpaper.DayNightWallpaper {
                    id: schedule
                    source: Qt.resolvedUrl("../../")
                    initialState: root.initialState
                }
            }
        }
    }
}
