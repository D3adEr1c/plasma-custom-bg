const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ctx = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../org.liby0zud.customimage/contents/ui/ZoomInput.js'), 'utf8'), ctx);
let state = { zoom: 1.5, remainder: 0 };
function wheel(angleY, pixelY = 0) {
    state = ctx.advance(state.zoom, state.remainder, angleY, pixelY);
}
wheel(120); assert.equal(state.zoom, 1.51);
wheel(-120); assert.equal(state.zoom, 1.5);
for (let i = 0; i < 12; i++) wheel(10);
assert.equal(state.zoom, 1.51);
assert.ok(Math.abs(state.remainder) < 1e-8);
for (let i = 0; i < 8; i++) wheel(0, -5);
assert.equal(state.zoom, 1.5);
wheel(60); wheel(-60); assert.equal(state.zoom, 1.5);
state = { zoom: 3, remainder: 0 };
for (let i = 0; i < 20; i++) wheel(120);
assert.equal(state.zoom, 3); assert.equal(state.remainder, 0);
wheel(-120); assert.equal(state.zoom, 2.99);
state = { zoom: 1, remainder: 0 };
wheel(-120); assert.equal(state.zoom, 1);
wheel(120); assert.equal(state.zoom, 1.01);
console.log('Passed: wheel notches, fine deltas, pixel gestures, reversal, and zoom bounds.');
