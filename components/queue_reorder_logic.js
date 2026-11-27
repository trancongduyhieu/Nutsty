.pragma library
// Drag-to-reorder maths for the queue list, after liner's useListReorder:
// a press becomes a drag after 6 px, the drop slot has hysteresis, the rows in between
// step aside by one row, and the list scrolls itself when the pointer nears an edge.

var DRAG_THRESHOLD = 6;

function dragStarted(x0, y0, x, y) {
    return Math.hypot(x - x0, y - y0) >= DRAG_THRESHOLD;
}

// relY: pointer y in list content coordinates (minus the grab offset's row centre handled by caller)
function dropIndexFor(relY, total, h, currentDrop) {
    if (total <= 0) return 0;
    var raw = Math.floor(relY / h);
    var clamped = Math.max(0, Math.min(total - 1, raw));
    if (currentDrop === null || currentDrop === undefined || currentDrop < 0) return clamped;
    var progress = (relY - raw * h) / h;
    if (clamped > currentDrop && progress < 0.25) return currentDrop;
    if (clamped < currentDrop && progress > 0.75) return currentDrop;
    return clamped;
}

function shiftFor(index, dragIndex, dropIndex, h) {
    if (dragIndex < 0 || index === dragIndex) return 0;
    if (dragIndex < dropIndex && index > dragIndex && index <= dropIndex) return -h;
    if (dragIndex > dropIndex && index >= dropIndex && index < dragIndex) return h;
    return 0;
}

// Pixels to scroll this frame; y, top, bottom in the same coordinates
function autoScrollDelta(y, top, bottom, threshold, maxSpeed) {
    var dTop = y - top, dBottom = bottom - y;
    if (dTop < threshold) {
        var r = Math.min(1, (threshold - Math.max(0, dTop)) / threshold);
        return -Math.round(r * r * maxSpeed + 2);
    }
    if (dBottom < threshold) {
        var r2 = Math.min(1, (threshold - Math.max(0, dBottom)) / threshold);
        return Math.round(r2 * r2 * maxSpeed + 2);
    }
    return 0;
}

function moveItem(arr, from, to) {
    if (!arr || from === to || from < 0 || to < 0 || from >= arr.length || to >= arr.length) return arr;
    var out = arr.slice();
    var item = out.splice(from, 1)[0];
    out.splice(to, 0, item);
    return out;
}

// Where the item that sat at `index` ends up after moving `from` to `to`
function movedIndex(index, from, to) {
    if (index === from) return to;
    if (from < to && index > from && index <= to) return index - 1;
    if (from > to && index >= to && index < from) return index + 1;
    return index;
}

function scrollTargetFor(index, h, topPad, viewH) {
    return Math.max(0, Math.round(topPad + index * h + h / 2 - viewH / 2));
}
