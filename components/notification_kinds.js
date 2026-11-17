.pragma library

// One icon per notification kind, shared by the toast and the notification centre.
// Paths are relative to components/.
var ICONS = {
    update: "../assets/icons/go-up-symbolic.svg",
    listen: "../assets/icons/material/ms-graphic_eq.svg",
    friend: "../assets/icons/contact-new-symbolic.svg",
    library: "../assets/icons/material/ms-library_music-fill.svg",
    download: "../assets/icons/download-symbolic.svg",
    success: "../assets/icons/material/ms-check.svg",
    error: "../assets/icons/material/ms-close.svg",
    info: "../assets/icons/notifications-symbolic.svg"
};

function icon(kind) { return ICONS[kind] || ICONS.info; }

function isError(kind) { return kind === "error"; }

// "vừa xong", "5 phút", "3 giờ", "hôm qua", "12/11"
function ago(ts, now, vi) {
    var s = Math.max(0, Math.floor((now - ts) / 1000));
    if (s < 60) return vi ? "vừa xong" : "just now";
    var m = Math.floor(s / 60);
    if (m < 60) return vi ? (m + " phút") : (m + "m");
    var h = Math.floor(m / 60);
    if (h < 24) return vi ? (h + " giờ") : (h + "h");
    var d = Math.floor(h / 24);
    if (d === 1) return vi ? "hôm qua" : "yesterday";
    if (d < 7) return vi ? (d + " ngày") : (d + "d");
    var dt = new Date(ts);
    return dt.getDate() + "/" + (dt.getMonth() + 1);
}
