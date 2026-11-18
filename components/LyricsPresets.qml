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
          width: 960, widthRatio: 0.65, yRatio: 0.68, height: 260, hideWithoutLyrics: false }
    ]

    readonly property int fallbackId: 2

    function get(id) {
        for (var i = 0; i < list.length; i++) {
            if (list[i].id === id) return list[i];
        }
        return get(fallbackId);
    }
}
