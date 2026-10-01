// Profiles are keyed by connector name. No screen-list index is persisted.
var keys = ["Image", "Zoom", "FocusX", "FocusY", "NightImage", "NightZoom",
            "NightFocusX", "NightFocusY", "SwitchMode", "ScheduleState", "TargetOutput", "ProfileRevision"];
function defaults(output) {
    return {Image:"", Zoom:1, FocusX:0.5, FocusY:0.5, NightImage:"", NightZoom:1,
        NightFocusX:0.5, NightFocusY:0.5, SwitchMode:2, ScheduleState:"",
        TargetOutput:output, ProfileRevision:"0"};
}
function snapshot(config, prefix) {
    var result = defaults("");
    keys.forEach(function(key) {
        var value = config ? config[(prefix || "") + key] : undefined;
        if (value !== undefined && value !== null) result[key] = value;
    });
    return result;
}
function revision(profile) { return Number(profile && profile.ProfileRevision) || 0; }
function select(output, incoming, stored, legacyOwner) {
    if (!output) return null;
    var owner = incoming.TargetOutput || legacyOwner;
    if (owner !== output) return stored;
    if (stored && revision(incoming) <= revision(stored)) return stored;
    var result = snapshot(incoming, "");
    result.TargetOutput = output;
    return result;
}
