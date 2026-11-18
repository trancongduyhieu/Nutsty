.pragma library

// Shared lyric line helpers for the Now Playing view and the desktop Apple Music preset.

function sanitizeWordList(wList) {
    if (!wList || wList.length === 0) return [];
    var res = [];
    var lastStart = -1.0;
    for (var i = 0; i < wList.length; i++) {
        var w = wList[i];
        var s = (w.start !== undefined) ? Number(w.start) : 0.0;
        var e = (w.end !== undefined) ? Number(w.end) : (s + 0.2);
        if (lastStart >= 0 && s < lastStart) {
            s = lastStart;
        }
        if (e < s + 0.05) {
            e = s + 0.05;
        }
        lastStart = s;
        res.push({
            text: w.text || "",
            start: s,
            end: e,
            duration: Math.max(0.05, e - s),
            hasSpace: (w.hasSpace !== false),
            isHeld: !!w.isHeld
        });
    }
    return res;
}

// 1:1 Mochy-Music splitBackingVocal: separates lead text and bracketed backing vocal
function splitBackingVocal(text, words) {
    if (!text || (text.indexOf('(') < 0 && text.indexOf('[') < 0)) {
        return { lead: text || "", backing: "", leadWords: sanitizeWordList(words || []), backingWords: [] };
    }

    var leadChars = [];
    var backingChars = [];
    var inBracket = new Array(text.length);
    var depth = 0;

    for (var i = 0; i < text.length; i++) {
        var ch = text.charAt(i);
        if (ch === '(' || ch === '[') {
            depth++;
            inBracket[i] = true;
        } else if ((ch === ')' || ch === ']') && depth > 0) {
            depth--;
            inBracket[i] = true;
            if (depth === 0) backingChars.push(' ');
        } else if (depth > 0) {
            inBracket[i] = true;
            backingChars.push(ch);
        } else {
            inBracket[i] = false;
            leadChars.push(ch);
        }
    }

    if (depth !== 0) {
        return { lead: text, backing: "", leadWords: sanitizeWordList(words || []), backingWords: [] };
    }

    var leadText = leadChars.join('').replace(/\s{2,}/g, ' ').trim();
    var backingText = backingChars.join('').replace(/\s{2,}/g, ' ').trim();

    if (!backingText) {
        return { lead: text, backing: "", leadWords: sanitizeWordList(words || []), backingWords: [] };
    }

    var leadWords = [];
    var backingWords = [];
    if (words && words.length > 0) {
        var searchFrom = 0;
        for (var j = 0; j < words.length; j++) {
            var w = words[j];
            var trimmed = (w.text || "").trim();
            if (!trimmed) continue;
            var start = text.indexOf(trimmed, searchFrom);
            if (start < 0) continue;
            searchFrom = start + trimmed.length;

            var bare = (w.text || "").replace(/[\(\)\[\]]/g, '');
            var cleanWord = {
                text: bare,
                start: w.start,
                end: w.end,
                duration: w.duration,
                hasSpace: w.hasSpace,
                isHeld: w.isHeld
            };

            if (start < inBracket.length && inBracket[start]) {
                backingWords.push(cleanWord);
            } else {
                leadWords.push(cleanWord);
            }
        }
    }

    return {
        lead: leadText,
        backing: backingText,
        leadWords: sanitizeWordList(leadWords),
        backingWords: sanitizeWordList(backingWords)
    };
}
