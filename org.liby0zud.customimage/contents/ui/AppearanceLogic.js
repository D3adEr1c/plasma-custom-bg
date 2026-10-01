// Mode values: 0 = system cycle, 1 = theme, 2 = day, 3 = night.
function isNight(mode, cycleNight, darkTheme) {
    if (mode === 0) return cycleNight;
    if (mode === 1) return darkTheme;
    return mode === 3;
}
function snapshotIsNight(snapshot) {
    if (!snapshot) return false;
    var url = snapshot.top && snapshot.blendFactor >= 0.5 ? snapshot.top : snapshot.bottom;
    return /[?&]darkMode=1(?:&|$)/.test(String(url || ""));
}
function profile(config, night) {
    // Missing night image falls back to the complete day profile, not its crop alone.
    var useNight = night && !!config.NightImage;
    return {
        image: useNight ? config.NightImage : (config.Image || ""),
        zoom: useNight ? (config.NightZoom || 1) : (config.Zoom || 1),
        focusX: useNight ? (config.NightFocusX ?? 0.5) : (config.FocusX ?? 0.5),
        focusY: useNight ? (config.NightFocusY ?? 0.5) : (config.FocusY ?? 0.5)
    };
}
