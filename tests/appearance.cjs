const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ctx = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../org.liby0zud.customimage/contents/ui/AppearanceLogic.js'), 'utf8'), ctx);
for (const cycle of [false, true]) for (const dark of [false, true]) {
    assert.equal(ctx.isNight(0, cycle, dark), cycle);
    assert.equal(ctx.isNight(1, cycle, dark), dark);
    assert.equal(ctx.isNight(2, cycle, dark), false);
    assert.equal(ctx.isNight(3, cycle, dark), true);
}
const day = 'image://package/get?dir=/some/path&darkMode=0';
const night = 'image://package/get?dir=/some/path&darkMode=1';
assert.equal(ctx.snapshotIsNight({bottom: day, top: '', blendFactor: 0}), false);
assert.equal(ctx.snapshotIsNight({bottom: night, top: '', blendFactor: 0}), true);
for (const progress of [0, 0.49, 0.5, 1]) {
    assert.equal(ctx.snapshotIsNight({bottom: day, top: night, blendFactor: progress}), progress >= 0.5);
    assert.equal(ctx.snapshotIsNight({bottom: night, top: day, blendFactor: progress}), progress < 0.5);
}
assert.equal(ctx.snapshotIsNight(null), false);
const old = {Image:'day.png', Zoom:1.7, FocusX:0, FocusY:0.9};
const plain = x => JSON.parse(JSON.stringify(x));
assert.deepEqual(plain(ctx.profile(old, false)), {image:'day.png',zoom:1.7,focusX:0,focusY:0.9});
assert.deepEqual(plain(ctx.profile(old, true)), plain(ctx.profile(old, false)));
const config = {...old, NightImage:'night.png', NightZoom:2.5, NightFocusX:0.8, NightFocusY:0};
assert.deepEqual(plain(ctx.profile(config, true)), {image:'night.png',zoom:2.5,focusX:0.8,focusY:0});
config.NightFocusX=0.1;
assert.equal(ctx.profile(config, false).focusX,0);
config.NightImage='';
assert.deepEqual(plain(ctx.profile(config, true)), plain(ctx.profile(config, false)));
console.log('Passed: switching modes, dawn/dusk midpoint, upgrade defaults, profile independence and missing-night fallback.');
