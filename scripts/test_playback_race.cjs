// Fast-switch and Listen Along races: runs components/playback_engine.js and social_engine.js with a
// fake clock and the status mpv really reports while the next song is still resolving.
// Run: node scripts/test_playback_race.cjs
const fs = require('fs'), vm = require('vm'), assert = require('assert');
const ROOT = __dirname + '/..';
let NOW = 1000000;
const execLog = [], xhrLog = [];
const FakeDate = class extends Date { static now() { return NOW; } };
const sandbox = {
    console, Math, String, Array, Object, JSON, Number, Boolean, parseInt, parseFloat, isNaN,
    Date: FakeDate,
    I18n: { tr: (vi) => vi },
    Quickshell: { execDetached: (c) => execLog.push(c.slice(1).join(' ')), env: () => "" },
    XMLHttpRequest: function () { this.open = (m, u) => { this.url = u; }; this.setRequestHeader = () => {};
                                  this.send = (b) => xhrLog.push({ url: this.url, body: b }); },
};
const PE = vm.createContext(Object.assign({}, sandbox));
vm.runInContext(fs.readFileSync(ROOT + '/components/playback_engine.js', 'utf8'), PE);
const SE = vm.createContext(Object.assign({}, sandbox));
vm.runInContext(fs.readFileSync(ROOT + '/components/social_engine.js', 'utf8'), SE);

const A = { title: "Song A", artist: "X", videoId: "AAAAAAAAAAA", duration: 260 };
const B = { title: "Song B", artist: "Y", videoId: "BBBBBBBBBBB", duration: 200 };
const C = { title: "Song C", artist: "Z", videoId: "CCCCCCCCCCC", duration: 180 };
const PATH_A = "https://rr1.googlevideo.com/videoplayback?id=A";
const PATH_B = "https://rr1.googlevideo.com/videoplayback?id=B";
const status = (path, pos, playing, dur) => JSON.stringify({ is_playing: !!playing, is_paused: !playing, time_pos: pos,
    duration: dur, filename: "videoplayback", path: path, is_loading: false });

function makeWin(startPos, onTrackSet) {
    const w = {
        appDir: "/app", currentTracks: [A, B, C], currentTime: 0, totalDuration: 260, isPlaying: true,
        isLoadingAudio: false, isShuffle: false, repeatMode: "off", lastSeekTimestamp: 0,
        trackChangeTimestamp: NOW - 60000, postLoadGraceTimestamp: NOW - 60000, lastLocalActionTimestamp: NOW - 60000,
        crossfadeEnabled: false, activeCoListeners: [], listeningAlongFriend: null, lastMpvPath: "", lastMpvPathKey: "",
        staleStatusPath: "", isSyncingFromFriend: false, pendingListenAlongSeekPosition: 0, lastNowPlayingSyncTime: 0,
        rapidNavDebounceTimer: { running: false, restart() { this.running = true; }, stop() { this.running = false; } },
        seekDebounceTimer: null, findLocalDownloadedTrack: () => null, syncHistoryToGoogle: false,
        getCurrentUserEmail: () => "host@x", getCurrentUserName: () => "Host", getCurrentUserAvatar: () => "",
        getTrackCoverUrl: () => "", songAccentColor: "", sendSocialEventFast() {}, showToast() {}, syncNowPlaying() {},
    };
    w.isSameTrack = PE.isSameTrack;
    let cur = A;
    Object.defineProperty(w, 'currentTrack', { get: () => cur, set: (v) => { cur = v; if (onTrackSet) onTrackSet(w, v); } });
    w.playNext = (auto) => PE.playNext(w, auto);
    w.playOnlineTrack = (t, r) => PE.playOnlineTrack(w, t, r, null, null, null);
    w.playTrack = (t) => PE.playTrack(w, t, null);
    w.seekAudio = (s) => PE.seekAudio(w, s);
    w.seekLocalOnly = (s) => PE.seekLocalOnly(w, s);
    // mpv is playing A
    PE.handlePlayerStatus(w, status(PATH_A, startPos, true, 260), null, null);
    assert.strictEqual(w.currentTime, startPos);
    return w;
}
function skipTo(w, trk) {
    PE.triggerRapidTrackSwitch(w, trk);
    NOW += 170; w.rapidNavDebounceTimer.running = false;
    PE.playOnlineTrack(w, trk, false, null, null, null);
}

console.log("lyrics lookup sees the new song's length...");
{
    let seen = null;
    const w = makeWin(120, (win, v) => { if (v === B) seen = win.totalDuration; });
    PE.triggerRapidTrackSwitch(w, B);
    assert.strictEqual(seen, 200);
}

console.log("previous song's status is ignored until mpv opens the new one...");
{
    const w = makeWin(120);
    skipTo(w, B);
    NOW += 80; PE.handlePlayerStatus(w, status(PATH_A, 120, false, 260), null, null);
    assert.strictEqual(w.isLoadingAudio, true);
    assert.strictEqual(w.currentTime, 0);
    assert.strictEqual(w.totalDuration, 200);
    execLog.length = 0;
    NOW += 900; PE.handlePlayerStatus(w, status(PATH_A, 120, false, 260), null, null);
    assert.ok(!execLog.some(c => c.endsWith("resume")), "old song must not be un-paused: " + execLog);
    // host publishes position 0 for B while it loads
    xhrLog.length = 0;
    SE.syncNowPlaying(w, true);
    const np = JSON.parse(xhrLog[0].body).now_playing;
    assert.strictEqual(np.videoId, B.videoId);
    assert.strictEqual(np.position, 0);
    // B opens
    NOW += 600; PE.handlePlayerStatus(w, status(PATH_B, 0.4, true, 200), null, null);
    assert.strictEqual(w.isLoadingAudio, false);
    assert.strictEqual(w.staleStatusPath, "");
    assert.strictEqual(w.totalDuration, 200);
}

console.log("one press of Next near the end moves exactly one song...");
{
    const w = makeWin(255);
    skipTo(w, B);
    NOW += 80; PE.handlePlayerStatus(w, status(PATH_A, 255, false, 260), null, null);
    NOW += 900; PE.handlePlayerStatus(w, status(PATH_A, 255, false, 260), null, null);
    NOW += 3500; PE.handlePlayerStatus(w, status(PATH_A, 259.3, true, 260), null, null);
    assert.strictEqual(w.currentTrack, B);
}

console.log("going back to the song mpv still holds is not blocked...");
{
    const w = makeWin(60);
    skipTo(w, B);
    NOW += 300; PE.handlePlayerStatus(w, status(PATH_A, 60, false, 260), null, null);
    NOW += 200; skipTo(w, A);                      // Prev before B ever opened
    assert.strictEqual(w.staleStatusPath, "");
    NOW += 400; PE.handlePlayerStatus(w, status(PATH_A, 0.5, true, 260), null, null);
    assert.strictEqual(w.isLoadingAudio, false);
}

console.log("a song that never opens still times out...");
{
    const w = makeWin(30);
    skipTo(w, B);
    NOW += 26000; PE.handlePlayerStatus(w, status(PATH_A, 30, false, 260), null, null);
    assert.strictEqual(w.isLoadingAudio, false);
    assert.strictEqual(w.isPlaying, false);
}

console.log("Listen Along events name their song...");
{
    const sent = [];
    const w = makeWin(10); w.activeCoListeners = ["guest@x"];
    w.sendSocialEventFast = (t, to, d) => sent.push({ t, d });
    PE.seekAudio(w, 95);
    PE.togglePlay(w, null);
    assert.deepStrictEqual(JSON.parse(JSON.stringify(sent[0].d)), { videoId: A.videoId, position: 95 });
    assert.strictEqual(sent[1].t, "pause");
    assert.strictEqual(sent[1].d.videoId, A.videoId);
    const guest = { currentTrack: B, isLoadingAudio: false };
    assert.strictEqual(SE._eventIsForOtherTrack(guest, { data: sent[0].d }), true);
    assert.strictEqual(SE._eventIsForOtherTrack(guest, { data: { position: 5 } }), false); // older builds
}

console.log("host clock offset is removed from the position estimate...");
{
    const skewMs = 7000;               // host clock 7 s ahead of the guest
    let age = 0;
    for (let i = 0; i < 6; i++) {      // host stamps every 4 s, guest sees each 0.3-1.5 s later
        const hostStampMs = NOW + skewMs;
        NOW += [300, 1200, 800, 1500, 400, 900][i];
        age = SE.hostStampAgeSec("host1", hostStampMs / 1000, 600);
        NOW += 4000 - [300, 1200, 800, 1500, 400, 900][i];
    }
    // last sample was seen 0.9 s after the stamp; the estimate is that minus the shortest delay (0.3 s)
    assert.ok(Math.abs(age - 0.6) < 0.01, "age " + age);
}

// --- Tidal lossless: track duration reaches the daemon, mid-song stream drop recovers ---
{
    execLog.length = 0;
    PE.dispatchPlay({ appDir: "/app", crossfadeArmed: false, crossfadeArmedPlan: null, crossfadeHandoverUntil: 0 },
                    "ytdl://abc", "T", "A", "img", 5, 266);
    assert.strictEqual(execLog[execLog.length - 1], "/app/backend/player_daemon.py play ytdl://abc T A img 5 266");

    const idle = JSON.stringify({ is_playing: false, is_paused: false, is_loading: false, path: "", filename: "" });
    const w = makeWin(80);
    w.streamRecoverKey = "";
    assert.strictEqual(PE.isMidSongDrop(w, JSON.parse(idle)), true);
    assert.strictEqual(PE.isMidSongDrop(w, { is_playing: true, path: PATH_A }), false);
    assert.strictEqual(PE.isMidSongDrop(Object.assign({}, w, { currentTime: 258 }), JSON.parse(idle)), false); // auto-advance owns the end
    assert.strictEqual(PE.isMidSongDrop(Object.assign({}, w, { trackChangeTimestamp: NOW }), JSON.parse(idle)), false);
    assert.strictEqual(PE.isMidSongDrop(Object.assign({}, w, { isPlaying: false }), JSON.parse(idle)), false);

    execLog.length = 0;
    PE.handlePlayerStatus(w, idle, null, null);
    assert.deepStrictEqual(execLog.filter(c => c.includes("stream_failed")), ["/app/backend/player_daemon.py stream_failed 80"]);
    PE.handlePlayerStatus(w, idle, null, null);
    assert.strictEqual(execLog.filter(c => c.includes("stream_failed")).length, 1, "once per song");
    // the same song played again (repeat one, replay) is a new play: a drop there recovers too
    w.trackChangeTimestamp = NOW - 30000;
    PE.handlePlayerStatus(w, idle, null, null);
    assert.strictEqual(execLog.filter(c => c.includes("stream_failed")).length, 2, "once per play, not per song forever");
}

console.log("ALL PLAYBACK RACE TESTS PASSED");
