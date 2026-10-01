// SPDX-License-Identifier: MIT
function validSize(size) {
    return !!size && Number.isFinite(size.width) && Number.isFinite(size.height)
        && size.width > 0 && size.height > 0;
}

function resolve(hostSize, hostScreen, desktopSize, selectedScreen) {
    if (validSize(hostSize)) return { width: hostSize.width, height: hostSize.height, source: "host" };
    if (hostScreen && validSize(hostScreen.geometry)) {
        return { width: hostScreen.geometry.width, height: hostScreen.geometry.height, source: "host" };
    }
    if (validSize(hostScreen)) return { width: hostScreen.width, height: hostScreen.height, source: "host" };
    if (validSize(desktopSize)) return { width: desktopSize.width, height: desktopSize.height, source: "desktop" };
    if (validSize(selectedScreen)) return { width: selectedScreen.width, height: selectedScreen.height, source: "selected" };
    // A visible placeholder, not a claim about the target screen.
    return { width: 16, height: 9, source: "placeholder" };
}

function fit(size, availableWidth, availableHeight) {
    var safeSize = validSize(size) ? size : { width: 16, height: 9 };
    var maxWidth = Number.isFinite(availableWidth) && availableWidth > 0 ? availableWidth : 620;
    var maxHeight = Number.isFinite(availableHeight) && availableHeight > 0 ? availableHeight : 380;
    var scale = Math.min(maxWidth / safeSize.width, maxHeight / safeSize.height);
    return { width: safeSize.width * scale, height: safeSize.height * scale };
}

// Screen list positions can change after hotplug. Never substitute another output.
function findOutput(screens, name) {
    if (!name) return null;
    return screens.find(screen => screen.name === name) || null;
}
function matchesOutput(owner, current) {
    return !!current && (!owner || owner === current);
}
