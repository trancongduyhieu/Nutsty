pragma Singleton
import QtQuick

// Desktop lyrics presets: the one list the desktop widget and the settings picker both read.
// To add a preset: add an entry here, then a Component for its view in LyricsPresetView.qml.
//   width / widthRatio  box width on the desktop: min(width, screenWidth * widthRatio)
//   yRatio              default top of the box as a share of the screen height
//   height              box height until the view reports its own implicitHeight
//   hideWithoutLyrics   hide the view (the title banner shows instead) while there are no synced lyrics
QtObject {
    readonly property var list: [
        { id: 1, titleVi: "Mẫu 1: Điện ảnh Serif", titleEn: "Preset 1: Cinematic Serif",
          subtitleVi: "1 dòng • Instrument Serif", subtitleEn: "1 line • Instrument Serif",
          width: 740, widthRatio: 0.45, yRatio: 0.725, height: 120, hideWithoutLyrics: true },
        { id: 2, titleVi: "Mẫu 2: Apple Music", titleEn: "Preset 2: Apple Music",
          subtitleVi: "5 dòng • Chiều sâu quang học", subtitleEn: "5 lines • Optical depth of field",
          width: 880, widthRatio: 0.55, yRatio: 0.62, height: 300, hideWithoutLyrics: true },
        { id: 3, titleVi: "Mẫu 3: Tối giản lướt", titleEn: "Preset 3: Minimal Glide",
          subtitleVi: "2 dòng • Nhòe chuyển động", subtitleEn: "2 lines • Motion blur",
          width: 760, widthRatio: 0.50, yRatio: 0.70, height: 140, hideWithoutLyrics: false },
        { id: 4, titleVi: "Mẫu 4: Đồ họa Chuyển động", titleEn: "Preset 4: Motion Typography",
          subtitleVi: "Chữ khối • Khung Bento", subtitleEn: "Block text • Bento frame",
          width: 960, widthRatio: 0.65, yRatio: 0.68, height: 260, hideWithoutLyrics: false },
        { id: 5, titleVi: "Mẫu 5: Biểu cảm Mochy", titleEn: "Preset 5: Mochy Expressive",
          subtitleVi: "Chữ nhấn • Dòng xếp chồng", subtitleEn: "Shout words • Stacked lines",
          width: 880, widthRatio: 0.55, yRatio: 0.64, height: 250, hideWithoutLyrics: true },
        { id: 6, titleVi: "Mẫu 6: Biến hóa chuyển động", titleEn: "Preset 6: Motion Variations",
          subtitleVi: "Mỗi câu một kiểu • Theo JIZURA", subtitleEn: "A new move every line • After JIZURA",
          width: 880, widthRatio: 0.55, yRatio: 0.66, height: 220, hideWithoutLyrics: true },
        { id: 7, titleVi: "Mẫu 7: Sân khấu chữ", titleEn: "Preset 7: Type Stage",
          subtitleVi: "Câu chồng hoặc câu đơn • Chất phim cũ", subtitleEn: "Stacked or single lines • Old film look",
          width: 880, widthRatio: 0.55, yRatio: 0.60, height: 300, hideWithoutLyrics: true },
        { id: 8, titleVi: "Mẫu 8: Sân khấu chữ tối đa", titleEn: "Preset 8: Type Stage Max",
          subtitleVi: "Vẽ tay kín khung • Nét đôi, hình vẽ nguệch ngoạc", subtitleEn: "Pen marks everywhere • Double strokes, doodles",
          width: 880, widthRatio: 0.55, yRatio: 0.60, height: 300, hideWithoutLyrics: true }
    ]

    readonly property int fallbackId: 2

    // Preset 8 effect sets (kinetic_stage.js SETS), in the order the settings show them
    readonly property var kineticSets: [
        { key: "sweet",   vi: "Ngọt ngào", en: "Sweet",
          aboutVi: "Pop, ballad, nhạc tình: tim, sao lấp lánh, bóng đèn, bóng bay",
          aboutEn: "Pop, ballads, love songs: hearts, sparkles, a bulb, balloons" },
        { key: "rough",   vi: "Rock", en: "Rock",
          aboutVi: "Rock, metal, punk: tia sét, vết nứt, chữ vỡ, dây đàn đứt",
          aboutEn: "Rock, metal, punk: bolts, cracks, shattered words, a snapped string" },
        { key: "street",  vi: "Rap", en: "Rap",
          aboutVi: "Rap, hip-hop: vương miện, sơn chảy, bình xịt, micro rơi",
          aboutEn: "Rap, hip-hop: crowns, paint drips, a spray can, a mic drop" },
        { key: "dance",   vi: "Nhảy", en: "Dance",
          aboutVi: "EDM, house, pop nhanh: sóng âm, quả cầu disco, cột âm lượng, laser",
          aboutEn: "EDM, house, fast pop: waves, a disco ball, EQ bars, lasers" },
        { key: "calm",    vi: "Êm dịu", en: "Calm",
          aboutVi: "Nhạc êm, không lời: mây, giọt nước, lá rơi, trăng lên",
          aboutEn: "Ambient, instrumental: clouds, drops, a falling leaf, moonrise" },
        { key: "classic", vi: "Jazz", en: "Jazz",
          aboutVi: "Jazz, blues, soul: nốt nhạc, đĩa than, khói, kèn",
          aboutEn: "Jazz, blues, soul: notes, a record, smoke, a horn" },
        { key: "anime",   vi: "Anime", en: "Anime",
          aboutVi: "Anime, nhạc phim: sao bốn cánh, mồ hôi, vệt tập trung, hoa anh đào",
          aboutEn: "Anime, soundtracks: four-point stars, sweat drops, focus lines, sakura" },
        { key: "folk",    vi: "Dân ca", en: "Folk",
          aboutVi: "Dân ca, đồng quê: mặt trời mọc, đàn chim, mầm cây",
          aboutEn: "Folk, country: sunrise, a flock of birds, a sprout" }
    ]
    function kineticSet(key) {
        for (var i = 0; i < kineticSets.length; i++) {
            if (kineticSets[i].key === key) return kineticSets[i];
        }
        return kineticSets[0];
    }

    function get(id) {
        for (var i = 0; i < list.length; i++) {
            if (list[i].id === id) return list[i];
        }
        return get(fallbackId);
    }
}
