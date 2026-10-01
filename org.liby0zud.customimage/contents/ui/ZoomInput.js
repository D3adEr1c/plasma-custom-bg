// Accumulate small wheel/gesture deltas instead of rounding each event away.
function advance(zoom, remainder, angleY, pixelY) {
    var delta = angleY !== 0 ? angleY / 120 : pixelY / 40;
    if (!Number.isFinite(delta) || delta === 0)
        return { zoom: zoom, remainder: remainder };
    var total = remainder + delta;
    var steps = total >= 0 ? Math.floor(total + 1e-9) : Math.ceil(total - 1e-9);
    var percent = Math.round(zoom * 100);
    var next = Math.max(100, Math.min(300, percent + steps));
    var atLimit = (next === 100 && total < 0) || (next === 300 && total > 0);
    return { zoom: next / 100, remainder: atLimit ? 0 : total - steps };
}
