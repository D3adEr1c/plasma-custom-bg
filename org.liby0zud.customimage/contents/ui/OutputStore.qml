import QtQuick
import QtCore
import "OutputProfiles.js" as Profiles

QtObject {
    id: store
    // Explicit location shares the file between desktop and KCM processes.
    property url location: StandardPaths.writableLocation(StandardPaths.GenericConfigLocation)
        + "/custom-image-wallpaper.ini"
    // No declared value properties: changing categories cannot auto-save defaults.
    property Settings settings: Settings { location: store.location }
    function open(output) {
        settings.category = "Display-" + encodeURIComponent(output);
        settings.sync();
    }
    function read(output) {
        if (!output) return null;
        open(output);
        if (Number(settings.value("FormatVersion", 0)) !== 2
            || settings.value("TargetOutput", "") !== output) return null;
        const profile = Profiles.defaults(output);
        Profiles.keys.forEach(key => {
            const value = settings.value(key, profile[key]);
            profile[key] = typeof profile[key] === "number" ? Number(value) : String(value);
        });
        return profile;
    }
    function write(output, profile) {
        if (!output || profile.TargetOutput !== output) return;
        const previous = read(output);
        if (previous && Profiles.revision(previous) >= Profiles.revision(profile)) return;
        open(output);
        const complete = Profiles.snapshot(profile, "");
        Profiles.keys.filter(key => key !== "ProfileRevision").forEach(key => {
            settings.setValue(key, complete[key]);
        });
        settings.setValue("ProfileRevision", complete.ProfileRevision);
        settings.setValue("FormatVersion", 2);
        settings.sync();
    }
}
