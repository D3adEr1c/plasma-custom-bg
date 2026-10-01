function baseKey(value) {
    const text = String(value || "").split(/[?#]/)[0].replace(/\/+$/, "");
    try { return decodeURIComponent(text.replace(/^file:\/\//, "")); }
    catch (error) { return text; }
}
function isSelected(selected, key, path) {
    const current = baseKey(selected);
    return !!current && (current === baseKey(key) || current === baseKey(path));
}
function fileLabel(value) {
    const path = String(value || "").split(/[?#]/)[0];
    const name = path.split("/").filter(s => s).pop() || path;
    try { return decodeURIComponent(name); }
    catch (error) { return name; }
}
