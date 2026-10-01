const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const geometry = {};
vm.createContext(geometry);
vm.runInContext(fs.readFileSync(path.join(__dirname, '../org.liby0zud.customimage/contents/ui/PreviewGeometry.js'), 'utf8'), geometry);

// Initial 0 × 0, invalid, or temporarily disconnected screens must never collapse the preview.
for (const size of [null, {width: 0, height: 0}, {width: 1920, height: 0}, {width: NaN, height: 1080}]) {
    const target = geometry.resolve(size, null, size, null);
    const preview = geometry.fit(target, 0, 0);
    assert.ok(preview.width > 0 && preview.height > 0);
    assert.ok(Number.isFinite(preview.width) && Number.isFinite(preview.height));
}
// The configured output must take precedence over the screen containing the dialog.
const dialogScreen = {width: 1920, height: 1080};
for (const target of [{width: 2560, height: 1600}, {width: 1080, height: 1920}, {width: 3440, height: 1440}]) {
    const resolved = geometry.resolve(target, null, dialogScreen, dialogScreen);
    assert.equal(resolved.source, 'host');
    const preview = geometry.fit(resolved, 350, 380);
    assert.ok(Math.abs(preview.width / preview.height - target.width / target.height) < 1e-12);
    assert.ok(preview.width <= 350 + 1e-9 && preview.height <= 380 + 1e-9);
    // Same normalized position and zoom give exactly the same visible source rectangle.
    const image = {width: 6000, height: 4000};
    function crop(view) {
        const scale = Math.max(view.width / image.width, view.height / image.height) * 1.4;
        return [Math.max(0, image.width - view.width / scale) * 0.71,
                Math.max(0, image.height - view.height / scale) * 0.28,
                view.width / scale, view.height / scale];
    }
    crop(target).forEach((value, index) => assert.ok(Math.abs(value - crop(preview)[index]) < 1e-9));
}
assert.equal(geometry.resolve(null, {geometry: {width: 2560, height: 1600}}, null, dialogScreen).source, 'host');
assert.equal(geometry.resolve(null, null, {width: 2560, height: 1600}, dialogScreen).source, 'desktop');
assert.equal(geometry.resolve(null, null, null, dialogScreen).source, 'selected');
console.log('Passed: zero-size recovery, screen selection priority, aspect ratios, and preview/desktop crop equivalence.');
