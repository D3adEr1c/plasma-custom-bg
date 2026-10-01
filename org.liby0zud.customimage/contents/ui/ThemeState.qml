import QtQuick

QtObject {
    // Read the platform's system appearance, independent of a Plasma style's
    // fixed panel colors or the settings window's inherited Kirigami palette.
    property int colorScheme: Qt.styleHints.colorScheme
    readonly property bool dark: colorScheme === Qt.Dark ? true
        : colorScheme === Qt.Light ? false
        : luminance(systemPalette.window) < luminance(systemPalette.windowText)
    property SystemPalette systemPalette: SystemPalette {
        colorGroup: SystemPalette.Active
    }
    function luminance(color) {
        return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b;
    }
}
