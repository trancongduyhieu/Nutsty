pragma Singleton
import QtQuick
import Quickshell

QtObject {
    id: i18n

    // Active Language Locale: "vi" (Tiếng Việt) | "en" (English)
    property string locale: "vi"
    readonly property bool isVietnamese: locale === "vi"

    // Primary Inline Pair Translation Helper
    // Guarantees effortless bimodal translations right where the text is declared:
    // text: I18n.tr("Cài đặt", "Settings")
    function tr(viText, enText) {
        return locale === "vi" ? (viText !== undefined ? viText : "") : (enText !== undefined ? enText : viText);
    }

    // Session seed: rolled once when the app starts, never changes afterwards.
    readonly property int sessionSeed: Math.floor(Math.random() * 1000000000)

    // Stable hash of a string mixed with the session seed (non-negative int).
    function seededIndex(key, count, salt) {
        if (!count || count < 1) return 0;
        var s = String(key) + "#" + String(sessionSeed) + "#" + String(salt === undefined ? "" : salt);
        var h = 5381;
        for (var i = 0; i < s.length; i++)
            h = ((h * 33) ^ s.charCodeAt(i)) >>> 0;
        return h % count;
    }

    // Rotating copy: vi and en lists are parallel (same index in both languages).
    // The variant is fixed for the whole app session, so text never swaps on screen.
    // Text: I18n.pick("home.quick", ["Tuyển tập nhanh", ...], ["Quick picks", ...])
    function pick(key, viList, enList) {
        var list = locale === "vi" ? viList : enList;
        if (!list || list.length === 0) list = viList || [];
        if (list.length === 0) return "";
        var n = Math.min(viList ? viList.length : list.length, enList ? enList.length : list.length);
        if (n < 1) n = list.length;
        return list[seededIndex(key, n)];
    }

    // Dynamic Mood / Filter Chip Title Localizer
    // Translates pills across Home mood bar and Up Next filter chips
    function formatMoodChipTitle(title) {
        if (!title) return "";
        var raw = String(title).trim();
        if (locale === "en") {
            // Normalize standard capitalized English
            var lowerEn = raw.toLowerCase();
            if (lowerEn === "tất cả") return "All";
            if (lowerEn === "khám phá") return "Discover";
            if (lowerEn === "quen thuộc") return "Familiar";
            if (lowerEn === "lãng mạn") return "Romance";
            if (lowerEn === "tiệc tùng") return "Party";
            if (lowerEn === "thư giãn") return "Chill";
            if (lowerEn === "tập luyện") return "Workout";
            if (lowerEn === "tập trung") return "Focus";
            if (lowerEn === "ngủ say") return "Sleep";
            if (lowerEn === "tiếp năng lượng" || lowerEn === "năng lượng") return "Energize";
            if (lowerEn === "yêu đời") return "Feel good";
            if (lowerEn === "tâm trạng") return "Sad";
            if (lowerEn === "di chuyển") return "Commute";
            return raw;
        }

        var key = raw.toLowerCase();
        if (key === "all") return "Tất cả";
        if (key === "discover") return "Khám phá";
        if (key === "familiar") return "Quen thuộc";
        if (key === "romance") return "Lãng mạn";
        if (key === "party") return "Tiệc tùng";
        if (key === "chill" || key === "relax") return "Thư giãn";
        if (key === "workout" || key === "in the gym") return "Tập luyện";
        if (key === "focus") return "Tập trung";
        if (key === "sleep") return "Ngủ say";
        if (key === "energy" || key === "energize") return "Năng lượng";
        if (key === "feel good") return "Yêu đời";
        if (key === "sad") return "Tâm trạng";
        if (key === "commute") return "Di chuyển";
        if (key === "reading") return "Đọc sách";
        if (key === "classical") return "Cổ điển";
        if (key === "deep cuts") return "Giai điệu ẩn";
        if (key === "popular") return "Phổ biến";
        if (key === "down beat" || key === "downbeat") return "Nhịp êm dịu";
        if (key === "instrumental") return "Nhạc không lời";
        if (key === "2020s") return "Thập niên 2020";
        if (key === "2010s") return "Thập niên 2010";
        if (key === "2000s") return "Thập niên 2000";
        if (key === "1990s") return "Thập niên 1990";
        if (key === "1980s") return "Thập niên 1980";
        if (key === "1970s") return "Thập niên 1970";
        if (key === "1960s") return "Thập niên 1960";
        if (key === "1950s") return "Thập niên 1950";
        return raw;
    }

    // Comprehensive Semantic Normalizer for YouTube Music Shelves / Sections
    // Covers all 21+ sections requested by user + variations and dynamic affixes
    function formatSectionTitle(title) {
        if (!title) return "";
        var raw = String(title).trim();
        if (locale === "en") {
            return raw;
        }

        var lower = raw.toLowerCase();
        // Remove trailing punctuation or redundant spaces
        lower = lower.replace(/[.:]+$/, "").trim();

        // Exact & plural-aware semantic mappings
        var dict = {
            "music video for you": "Video âm nhạc dành cho bạn",
            "music videos for you": "Video âm nhạc dành cho bạn",
            "cover and remixes": "Bản cover & Phối lại",
            "covers and remixes": "Bản cover & Phối lại",
            "cover & remixes": "Bản cover & Phối lại",
            "covers & remixes": "Bản cover & Phối lại",
            "long listen": "Nghe kéo dài",
            "long listens": "Nghe kéo dài",
            "trending song for you": "Bài hát thịnh hành dành cho bạn",
            "trending songs for you": "Bài hát thịnh hành dành cho bạn",
            "trending community playlist": "Danh sách phát cộng đồng thịnh hành",
            "trending community playlists": "Danh sách phát cộng đồng thịnh hành",
            "album for you": "Tuyển tập dành cho bạn",
            "albums for you": "Tuyển tập dành cho bạn",
            "take it easy": "Thư giãn nhẹ nhàng",
            "from the community": "Từ cộng đồng",
            "keep listening": "Tiếp tục lắng nghe",
            "peaceful bedtime": "Giấc ngủ êm đềm",
            "gentle piano": "Piano nhẹ nhàng",
            "classical for sleeping": "Nhạc cổ điển ru ngủ",
            "classsical for sleeping": "Nhạc cổ điển ru ngủ",
            "rain sound": "Tiếng mưa rơi",
            "rain sounds": "Tiếng mưa rơi",
            "deep focus": "Tập trung sâu",
            "power boost": "Tăng cường năng lượng",
            "kicking back": "Nghỉ ngơi thư giãn",
            "try something chilled": "Thử giai điệu thư thái",
            "mixed for you": "Dành riêng cho bạn",
            "sweetheart & romance": "Ngọt ngào & Lãng mạn",
            "sweetheart and romance": "Ngọt ngào & Lãng mạn",
            "quick pick": "Tuyển tập nhanh",
            "quick picks": "Tuyển tập nhanh",
            "in the gym": "Tại phòng tập",
            "recommended for you": "Được đề xuất cho bạn",
            "listen again": "Nghe lại",
            "forgotten favorites": "Giai điệu quen thuộc",
            "from your library": "Từ thư viện của bạn",
            "trending": "Thịnh hành",
            "new releases": "Bản phát hành mới",
            "community playlists": "Danh sách phát cộng đồng",
            "featured playlists for you": "Danh sách phát nổi bật cho bạn",
            "music videos": "Video âm nhạc",
            "hits of today": "Bản hit hôm nay",
            "energy boosters": "Tiếp thêm năng lượng",
            "chill out": "Thư giãn tối đa",
            "classical focus": "Tập trung cùng nhạc cổ điển",
            "reading": "Đọc sách",
            "classical": "Cổ điển",
            "deep cuts": "Giai điệu ẩn",
            "popular": "Phổ biến",
            "down beat": "Nhịp êm dịu",
            "downbeat": "Nhịp êm dịu",
            "instrumental": "Nhạc không lời"
        };

        if (dict[lower]) {
            return dict[lower];
        }

        // Dynamic prefix/suffix checks
        if (lower.endsWith(" playlists")) {
            var moodPrefix = raw.slice(0, -10).trim();
            return formatMoodChipTitle(moodPrefix) + " - Danh sách phát";
        }
        if (lower.startsWith("similar to ")) {
            return "Tương tự như " + raw.slice(11).trim();
        }
        if (lower.startsWith("more from ")) {
            return "Thêm từ " + raw.slice(10).trim();
        }
        if (lower.startsWith("recommended based on ")) {
            return "Đề xuất dựa trên " + raw.slice(21).trim();
        }

        return raw;
    }

    // Auto-detect operating system locale on initial cold start
    Component.onCompleted: {
        try {
            var sysLang = Quickshell.env("LANG") || Quickshell.env("LC_ALL") || "";
            if (sysLang.indexOf("vi") !== -1 || sysLang.indexOf("VI") !== -1) {
                locale = "vi";
            } else if (sysLang.indexOf("en") !== -1 || sysLang.indexOf("EN") !== -1) {
                locale = "en";
            }
        } catch(e) {
            console.log("[I18n] Note: Could not query system LANG env, defaulting to:", locale);
        }
    }
}
