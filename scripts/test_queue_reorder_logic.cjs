// Unit tests for components/queue_reorder_logic.js (drag to reorder the queue, liner's useListReorder):
//   node scripts/test_queue_reorder_logic.cjs
const fs = require('fs'), vm = require('vm'), assert = require('assert');
const src = fs.readFileSync(__dirname + '/../components/queue_reorder_logic.js', 'utf8').replace(/^\.pragma.*$/m, '');
const L = vm.createContext({});
vm.runInContext(src, L);
const H = 68;

// A press only turns into a drag after 6 px of travel
assert.strictEqual(L.dragStarted(0, 0, 3, 4), false);
assert.strictEqual(L.dragStarted(0, 0, 0, 6), true);

// Drop slot: the row under the pointer, clamped to the list
assert.strictEqual(L.dropIndexFor(10, 10, H, null), 0);
assert.strictEqual(L.dropIndexFor(3 * H + 30, 10, H, null), 3);
assert.strictEqual(L.dropIndexFor(-50, 10, H, null), 0);
assert.strictEqual(L.dropIndexFor(99 * H, 10, H, null), 9);
assert.strictEqual(L.dropIndexFor(500, 1, H, 0), 0);
// Hysteresis: moving down needs a quarter of the next row, moving up needs to leave its bottom quarter
assert.strictEqual(L.dropIndexFor(3 * H + 10, 10, H, 2), 2);
assert.strictEqual(L.dropIndexFor(3 * H + 20, 10, H, 2), 3);
assert.strictEqual(L.dropIndexFor(1 * H + 60, 10, H, 2), 2);
assert.strictEqual(L.dropIndexFor(1 * H + 40, 10, H, 2), 1);

// Rows between the dragged row and the drop slot step out of the way by one row
assert.strictEqual(L.shiftFor(3, 1, 4, H), -H);  // dragging down: rows 2..4 move up
assert.strictEqual(L.shiftFor(2, 1, 4, H), -H);
assert.strictEqual(L.shiftFor(5, 1, 4, H), 0);
assert.strictEqual(L.shiftFor(1, 1, 4, H), 0);   // the dragged row itself is hidden, not shifted
assert.strictEqual(L.shiftFor(2, 5, 2, H), H);   // dragging up: rows 2..4 move down
assert.strictEqual(L.shiftFor(4, 5, 2, H), H);
assert.strictEqual(L.shiftFor(1, 5, 2, H), 0);
assert.strictEqual(L.shiftFor(3, -1, 2, H), 0);  // no drag

// Auto-scroll near the edges, faster the closer the pointer is (ratio^2 * max + 2)
assert.strictEqual(L.autoScrollDelta(300, 0, 600, H, 18), 0);
assert.strictEqual(L.autoScrollDelta(0, 0, 600, H, 18), -20);
assert.strictEqual(L.autoScrollDelta(600, 0, 600, H, 18), 20);
assert.strictEqual(L.autoScrollDelta(-40, 0, 600, H, 18), -20); // past the edge: capped
assert.strictEqual(L.autoScrollDelta(34, 0, 600, H, 18), -7);

// Moving an item returns a new array; indices of other items follow the move
const a = ['a', 'b', 'c', 'd'];
const m = L.moveItem(a, 0, 2);
assert.deepStrictEqual(m, ['b', 'c', 'a', 'd']);
assert.deepStrictEqual(a, ['a', 'b', 'c', 'd']);
assert.deepStrictEqual(L.moveItem(a, 3, 1), ['a', 'd', 'b', 'c']);
assert.strictEqual(L.moveItem(a, 1, 1), a);
assert.strictEqual(L.moveItem(a, 9, 1), a);
assert.strictEqual(L.movedIndex(0, 0, 2), 2);
assert.strictEqual(L.movedIndex(1, 0, 2), 0);
assert.strictEqual(L.movedIndex(2, 0, 2), 1);
assert.strictEqual(L.movedIndex(3, 0, 2), 3);
assert.strictEqual(L.movedIndex(1, 3, 1), 2);
assert.strictEqual(L.movedIndex(3, 3, 1), 1);

// Scroll target that puts the current row in the middle (liner's getQueueScrollTarget)
assert.strictEqual(L.scrollTargetFor(0, H, 6, 500), 0);
assert.strictEqual(L.scrollTargetFor(10, H, 6, 500), 6 + 10 * H + H / 2 - 250);

console.log('queue_reorder_logic: OK');
