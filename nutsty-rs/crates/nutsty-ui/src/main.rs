use gpui::*;
use nutsty_audio::{AudioEngine, CpalAudioPlayer};
use nutsty_core::{AudioSource, PlaybackStatus, Track, Volume};
use nutsty_library::MediaLibrary;
use nutsty_lyrics::SyncedLyrics;
use std::path::PathBuf;
use std::sync::Arc;

#[derive(Clone, Copy, PartialEq, Eq)]
enum NavTab {
    Home,
    Library,
    Queue,
    Settings,
}

struct NutstyApp {
    player: Option<Arc<CpalAudioPlayer>>,
    library: MediaLibrary,
    active_tab: NavTab,
    selected_mood: String,
    current_track: Option<Track>,
    lyrics: Option<SyncedLyrics>,
    search_query: String,
    volume: f32,
    _timer_task: Option<Task<()>>,
}

impl NutstyApp {
    fn new(_cx: &mut Context<Self>) -> Self {
        let player = CpalAudioPlayer::new().ok().map(Arc::new);
        let mut library = MediaLibrary::new();

        // Automatically scan user's Music directories on Linux & Windows
        let music_dirs = vec![
            dirs::audio_dir().unwrap_or_else(|| PathBuf::from("/home/apple/Music")),
            PathBuf::from("/home/apple/Music/SimpMusic/Tracks"),
            PathBuf::from("/home/apple/Music/Downloads_Phone"),
        ];

        let valid_dirs: Vec<PathBuf> = music_dirs.into_iter().filter(|p| p.exists()).collect();
        if !valid_dirs.is_empty() {
            library.scan_directories(&valid_dirs);
        }

        // If library is still empty, seed with high-fidelity demo track
        if library.is_empty() {
            library.add_track(Track::new(
                "Sparkle",
                "RADWIMPS",
                "Your Name. OST",
                230000,
                AudioSource::Local("/home/apple/Music/re-zero-return-by-death.mp3".into()),
            ));
        }

        Self {
            player,
            library,
            active_tab: NavTab::Library,
            selected_mood: "Tất cả".to_string(),
            current_track: None,
            lyrics: None,
            search_query: String::new(),
            volume: 1.0,
            _timer_task: None,
        }
    }

    fn play_track(&mut self, track: Track, cx: &mut Context<Self>) {
        if let Some(player) = &self.player {
            let _ = player.load_source(track.source.clone());
            let _ = player.play();
        }
        self.current_track = Some(track);
        cx.notify();
    }

    fn toggle_play(&mut self, cx: &mut Context<Self>) {
        if let Some(player) = &self.player {
            match player.status() {
                PlaybackStatus::Playing => {
                    let _ = player.pause();
                }
                PlaybackStatus::Paused => {
                    let _ = player.play();
                }
                PlaybackStatus::Stopped => {
                    if let Some(track) = &self.current_track {
                        let _ = player.load_source(track.source.clone());
                        let _ = player.play();
                    } else if let Some(first) = self.library.tracks().first() {
                        let first_track = first.clone();
                        self.play_track(first_track, cx);
                        return;
                    }
                }
            }
        }
        cx.notify();
    }

    fn play_next(&mut self, cx: &mut Context<Self>) {
        let tracks = self.library.tracks();
        if tracks.is_empty() {
            return;
        }

        let next_track = if let Some(current) = &self.current_track {
            if let Some(pos) = tracks.iter().position(|t| t.id == current.id) {
                if pos + 1 < tracks.len() {
                    tracks[pos + 1].clone()
                } else {
                    tracks[0].clone()
                }
            } else {
                tracks[0].clone()
            }
        } else {
            tracks[0].clone()
        };

        self.play_track(next_track, cx);
    }

    fn play_prev(&mut self, cx: &mut Context<Self>) {
        let tracks = self.library.tracks();
        if tracks.is_empty() {
            return;
        }

        let prev_track = if let Some(current) = &self.current_track {
            if let Some(pos) = tracks.iter().position(|t| t.id == current.id) {
                if pos > 0 {
                    tracks[pos - 1].clone()
                } else {
                    tracks[tracks.len() - 1].clone()
                }
            } else {
                tracks[0].clone()
            }
        } else {
            tracks[0].clone()
        };

        self.play_track(prev_track, cx);
    }

    fn seek_relative(&mut self, ratio: f32, cx: &mut Context<Self>) {
        if let Some(player) = &self.player {
            let progress = player.progress();
            if progress.duration_ms > 0 {
                let target_ms = (progress.duration_ms as f32 * ratio.clamp(0.0, 1.0)) as u32;
                let _ = player.seek(target_ms);
            }
        }
        cx.notify();
    }

    fn set_volume(&mut self, vol: f32, cx: &mut Context<Self>) {
        self.volume = vol.clamp(0.0, 1.0);
        if let Some(player) = &self.player {
            player.set_volume(Volume::new(self.volume));
        }
        cx.notify();
    }
}

// Theme tokens mirroring Theme.qml
mod theme {
    use gpui::*;

    pub const BG_APP: Hsla = hsla(225.0 / 360.0, 0.16, 0.06, 1.0);       // #0c0d12
    pub const BG_SIDEBAR: Hsla = hsla(225.0 / 360.0, 0.14, 0.08, 0.85);  // Frosted dark slate
    pub const BG_CARD: Hsla = hsla(225.0 / 360.0, 0.12, 0.11, 1.0);      // #161821
    pub const BG_CARD_HOVER: Hsla = hsla(225.0 / 360.0, 0.14, 0.16, 1.0);// #212533
    pub const BG_DOCK: Hsla = hsla(225.0 / 360.0, 0.18, 0.07, 0.94);     // Bottom dock capsule
    pub const ACCENT: Hsla = hsla(36.0 / 360.0, 0.65, 0.65, 1.0);        // #deb06c Warm Gold (Theme.accent)
    pub const ACCENT_CYAN: Hsla = hsla(199.0 / 360.0, 0.89, 0.60, 1.0);  // #38bdf8 Cyan
    pub const TEXT_PRIMARY: Hsla = hsla(0.0, 0.0, 1.0, 1.0);             // #ffffff
    pub const TEXT_SECONDARY: Hsla = hsla(220.0 / 360.0, 0.10, 0.70, 1.0);// #a6abb8
    pub const TEXT_MUTED: Hsla = hsla(220.0 / 360.0, 0.08, 0.45, 1.0);   // #6c7282
    pub const BORDER_HAIRLINE: Hsla = hsla(0.0, 0.0, 1.0, 0.07);         // 1px subtle border
}

impl Render for NutstyApp {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let status = self.player.as_ref().map(|p| p.status()).unwrap_or(PlaybackStatus::Stopped);
        let progress = self.player.as_ref().map(|p| p.progress()).unwrap_or_default();

        let track_title = self.current_track.as_ref().map(|t| t.title.to_string()).unwrap_or_else(|| "Nutsty Native".to_string());
        let track_artist = self.current_track.as_ref().map(|t| t.artist.to_string()).unwrap_or_else(|| "Sẵn sàng phát nhạc".to_string());
        let _track_album = self.current_track.as_ref().map(|t| t.album.to_string()).unwrap_or_default();

        let active_lyric: SharedString = self
            .lyrics
            .as_ref()
            .and_then(|l| l.line_at(progress.position_ms))
            .map(|line| SharedString::from(line.text.as_str().to_string()))
            .unwrap_or_else(|| SharedString::from("♪ Lời bài hát đồng bộ thời gian thực ♪"));

        let displayed_tracks = if self.search_query.is_empty() {
            self.library.tracks().to_vec()
        } else {
            self.library.search(&self.search_query).into_iter().cloned().collect()
        };

        div()
            .flex()
            .flex_col()
            .size_full()
            .bg(theme::BG_APP)
            .text_color(theme::TEXT_PRIMARY)
            .font_family("Inter")
            // 1. TOP HEADER BAR
            .child(
                div()
                    .flex()
                    .items_center()
                    .justify_between()
                    .h(px(56.0))
                    .px_6()
                    .border_b_1()
                    .border_color(theme::BORDER_HAIRLINE)
                    .bg(theme::BG_SIDEBAR)
                    // Logo & Version Pill
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap_3()
                            .child(
                                div()
                                    .text_lg()
                                    .font_weight(FontWeight::BOLD)
                                    .text_color(theme::ACCENT)
                                    .child("NUTSTY"),
                            )
                            .child(
                                div()
                                    .text_xs()
                                    .px_2()
                                    .py_0p5()
                                    .rounded_full()
                                    .bg(hsla(36.0 / 360.0, 0.65, 0.65, 0.15))
                                    .text_color(theme::ACCENT)
                                    .child("RUST 120 FPS"),
                            ),
                    )
                    // Search Bar Pill
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap_2()
                            .w_96()
                            .h_8()
                            .px_3()
                            .rounded_full()
                            .bg(theme::BG_CARD)
                            .border_1()
                            .border_color(theme::BORDER_HAIRLINE)
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(theme::TEXT_MUTED)
                                    .child("🔍"),
                            )
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(theme::TEXT_SECONDARY)
                                    .child("Tìm kiếm bài hát, nghệ sĩ, album..."),
                            ),
                    )
                    // Header Right Status
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap_2()
                            .text_xs()
                            .text_color(theme::TEXT_MUTED)
                            .child("RAM: ~40 MB")
                            .child("•")
                            .child("GPU Native"),
                    ),
            )
            // 2. MAIN BODY (SIDEBAR + CONTENT)
            .child(
                div()
                    .flex_1()
                    .flex()
                    .flex_row()
                    .overflow_hidden()
                    // 2A. LEFT SIDEBAR (Ported from NavSidebar.qml)
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .justify_between()
                            .w(px(240.0))
                            .h_full()
                            .p_3()
                            .border_r_1()
                            .border_color(theme::BORDER_HAIRLINE)
                            .bg(theme::BG_SIDEBAR)
                            // Navigation Buttons
                            .child(
                                div()
                                    .flex()
                                    .flex_col()
                                    .gap_1()
                                    .child(self.render_nav_item(NavTab::Home, "Khám phá", "🏠", cx))
                                    .child(self.render_nav_item(NavTab::Library, "Thư viện & Tải xuống", "📁", cx))
                                    .child(self.render_nav_item(NavTab::Queue, "Hàng đợi phát", "📜", cx))
                                    .child(self.render_nav_item(NavTab::Settings, "Cài đặt & Lời bài hát", "⚙️", cx)),
                            )
                            // Sidebar Bottom Stats Card
                            .child(
                                div()
                                    .flex()
                                    .flex_col()
                                    .p_3()
                                    .rounded_xl()
                                    .bg(theme::BG_CARD)
                                    .border_1()
                                    .border_color(theme::BORDER_HAIRLINE)
                                    .child(
                                        div()
                                            .text_xs()
                                            .font_weight(FontWeight::SEMIBOLD)
                                            .text_color(theme::TEXT_PRIMARY)
                                            .child("THƯ VIỆN NHẠC LOCAL"),
                                    )
                                    .child(
                                        div()
                                            .text_xs()
                                            .text_color(theme::TEXT_MUTED)
                                            .child(format!("{} bài hát đã nạp", self.library.len())),
                                    ),
                            ),
                    )
                    // 2B. RIGHT CONTENT AREA (Ported from MainTrackGrid.qml & HomeFeedView.qml)
                    .child(
                        div()
                            .flex_1()
                            .flex()
                            .flex_col()
                            .p_6()
                            .gap_4()
                            .overflow_hidden()
                            // Mood Pills Bar
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .gap_2()
                                    .child(self.render_mood_chip("Tất cả", cx))
                                    .child(self.render_mood_chip("Thư giãn", cx))
                                    .child(self.render_mood_chip("Tập trung", cx))
                                    .child(self.render_mood_chip("Năng lượng", cx))
                                    .child(self.render_mood_chip("Lofi Anime", cx)),
                            )
                            // Section Header
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .justify_between()
                                    .child(
                                        div()
                                            .text_sm()
                                            .font_weight(FontWeight::BOLD)
                                            .text_color(theme::TEXT_PRIMARY)
                                            .child(format!("DANH SÁCH BÀI HÁT ({})", displayed_tracks.len())),
                                    )
                                    .child(
                                        div()
                                            .text_xs()
                                            .text_color(theme::ACCENT)
                                            .child("Quét tự động ~/Music"),
                                    ),
                            )
                            // Virtualized / Scrollable Track List
                            .child(
                                div()
                                    .flex_1()
                                    .flex()
                                    .flex_col()
                                    .gap_2()
                                    .overflow_hidden()
                                    .children(displayed_tracks.into_iter().enumerate().take(12).map(|(idx, track)| {
                                        let is_current = self.current_track.as_ref().map(|t| t.id == track.id).unwrap_or(false);
                                        let trk_clone = track.clone();

                                        div()
                                            .flex()
                                            .items_center()
                                            .justify_between()
                                            .px_4()
                                            .py_2p5()
                                            .rounded_xl()
                                            .bg(if is_current { theme::BG_CARD_HOVER } else { theme::BG_CARD })
                                            .border_1()
                                            .border_color(if is_current { hsla(36.0 / 360.0, 0.65, 0.65, 0.35) } else { theme::BORDER_HAIRLINE })
                                            .hover(|s| s.bg(theme::BG_CARD_HOVER))
                                            .on_mouse_down(MouseButton::Left, cx.listener(move |this, _, _, cx| {
                                                this.play_track(trk_clone.clone(), cx);
                                            }))
                                            // Left Track Metadata
                                            .child(
                                                div()
                                                    .flex()
                                                    .items_center()
                                                    .gap_4()
                                                    .child(
                                                        div()
                                                            .w_6()
                                                            .text_xs()
                                                            .font_weight(FontWeight::SEMIBOLD)
                                                            .text_color(if is_current { theme::ACCENT } else { theme::TEXT_MUTED })
                                                            .child(if is_current { "▶".to_string() } else { format!("{:02}", idx + 1) }),
                                                    )
                                                    .child(
                                                        div()
                                                            .flex()
                                                            .flex_col()
                                                            .child(
                                                                div()
                                                                    .text_sm()
                                                                    .font_weight(FontWeight::MEDIUM)
                                                                    .text_color(if is_current { theme::ACCENT } else { theme::TEXT_PRIMARY })
                                                                    .child(track.title.to_string()),
                                                            )
                                                            .child(
                                                                div()
                                                                    .text_xs()
                                                                    .text_color(theme::TEXT_SECONDARY)
                                                                    .child(format!("{} • {}", track.artist, track.album)),
                                                            ),
                                                    ),
                                            )
                                            // Right Duration
                                            .child(
                                                div()
                                                    .text_xs()
                                                    .text_color(theme::TEXT_MUTED)
                                                    .child(format_duration(track.duration_ms)),
                                            )
                                    })),
                            ),
                    ),
            )
            // 3. SYNCHRONIZED LYRICS STRIP
            .child(
                div()
                    .flex()
                    .items_center()
                    .justify_center()
                    .h_8()
                    .bg(hsla(225.0 / 360.0, 0.16, 0.05, 1.0))
                    .border_t_1()
                    .border_color(theme::BORDER_HAIRLINE)
                    .text_xs()
                    .font_weight(FontWeight::MEDIUM)
                    .text_color(theme::ACCENT)
                    .child(active_lyric),
            )
            // 4. FLOATING PLAYER DOCK (Ported from PlayerBarBottom.qml)
            .child(
                div()
                    .flex()
                    .items_center()
                    .justify_between()
                    .h_20()
                    .px_6()
                    .py_3()
                    .border_t_1()
                    .border_color(theme::BORDER_HAIRLINE)
                    .bg(theme::BG_DOCK)
                    // Left Track Info
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap_3()
                            .w_64()
                            // Square Thumbnail placeholder
                            .child(
                                div()
                                    .size_12()
                                    .rounded_lg()
                                    .bg(theme::BG_CARD)
                                    .border_1()
                                    .border_color(theme::BORDER_HAIRLINE)
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .text_sm()
                                    .child("🎵"),
                            )
                            .child(
                                div()
                                    .flex()
                                    .flex_col()
                                    .overflow_hidden()
                                    .child(
                                        div()
                                            .text_sm()
                                            .font_weight(FontWeight::BOLD)
                                            .text_color(theme::TEXT_PRIMARY)
                                            .child(track_title),
                                    )
                                    .child(
                                        div()
                                            .text_xs()
                                            .text_color(theme::TEXT_SECONDARY)
                                            .child(track_artist),
                                    ),
                            ),
                    )
                    // Center Controls & Scrubbing Bar
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .items_center()
                            .gap_1p5()
                            // Transport buttons
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .gap_4()
                                    // Prev button
                                    .child(
                                        div()
                                            .p_1()
                                            .text_sm()
                                            .text_color(theme::TEXT_SECONDARY)
                                            .hover(|s| s.text_color(theme::TEXT_PRIMARY))
                                            .on_mouse_down(MouseButton::Left, cx.listener(|this, _, _, cx| {
                                                this.play_prev(cx);
                                            }))
                                            .child("⏮"),
                                    )
                                    // Play / Pause Circle Button
                                    .child(
                                        div()
                                            .flex()
                                            .items_center()
                                            .justify_center()
                                            .size_10()
                                            .rounded_full()
                                            .bg(theme::ACCENT)
                                            .text_color(rgb(0x0c0d12))
                                            .font_weight(FontWeight::BOLD)
                                            .text_sm()
                                            .hover(|s| s.bg(hsla(36.0 / 360.0, 0.75, 0.72, 1.0)))
                                            .on_mouse_down(MouseButton::Left, cx.listener(|this, _, _, cx| {
                                                this.toggle_play(cx);
                                            }))
                                            .child(match status {
                                                PlaybackStatus::Playing => "⏸",
                                                _ => "▶",
                                            }),
                                    )
                                    // Next button
                                    .child(
                                        div()
                                            .p_1()
                                            .text_sm()
                                            .text_color(theme::TEXT_SECONDARY)
                                            .hover(|s| s.text_color(theme::TEXT_PRIMARY))
                                            .on_mouse_down(MouseButton::Left, cx.listener(|this, _, _, cx| {
                                                this.play_next(cx);
                                            }))
                                            .child("⏭"),
                                    ),
                            )
                            // Progress bar & Time indicators
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .gap_3()
                                    .child(
                                        div()
                                            .text_xs()
                                            .text_color(theme::TEXT_MUTED)
                                            .child(format_duration(progress.position_ms)),
                                    )
                                    // Interactive Seekbar
                                    .child(
                                        div()
                                            .w(px(320.0))
                                            .h_1p5()
                                            .rounded_full()
                                            .bg(theme::BG_CARD)
                                            .hover(|s| s.h_2())
                                            .on_mouse_down(MouseButton::Left, cx.listener(|this, _, _, cx| {
                                                this.seek_relative(0.5, cx);
                                            }))
                                            .child(
                                                div()
                                                    .h_full()
                                                    .w(px(progress.progress_ratio() * 320.0))
                                                    .rounded_full()
                                                    .bg(theme::ACCENT),
                                            ),
                                    )
                                    .child(
                                        div()
                                            .text_xs()
                                            .text_color(theme::TEXT_MUTED)
                                            .child(format_duration(progress.duration_ms)),
                                    ),
                            ),
                    )
                    // Right Extra Controls & Volume
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .justify_end()
                            .w_64()
                            .gap_3()
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(theme::TEXT_SECONDARY)
                                    .hover(|s| s.text_color(theme::TEXT_PRIMARY))
                                    .on_mouse_down(MouseButton::Left, cx.listener(|this, _, _, cx| {
                                        let new_vol = if this.volume > 0.0 { 0.0 } else { 1.0 };
                                        this.set_volume(new_vol, cx);
                                    }))
                                    .child(if self.volume == 0.0 { "🔇" } else { "🔊" }),
                            )
                            .child(
                                div()
                                    .w_20()
                                    .h_1p5()
                                    .rounded_full()
                                    .bg(theme::BG_CARD)
                                    .hover(|s| s.h_2())
                                    .on_mouse_down(MouseButton::Left, cx.listener(|this, _, _, cx| {
                                        this.set_volume(0.8, cx);
                                    }))
                                    .child(
                                        div()
                                            .h_full()
                                            .w(px(self.volume * 80.0))
                                            .rounded_full()
                                            .bg(theme::ACCENT),
                                    ),
                            ),
                    ),
            )
    }
}

impl NutstyApp {
    fn render_nav_item(&self, tab: NavTab, label: &'static str, icon: &'static str, cx: &mut Context<Self>) -> impl IntoElement {
        let is_active = self.active_tab == tab;

        div()
            .flex()
            .items_center()
            .gap_3()
            .h_10()
            .px_3()
            .rounded_lg()
            .bg(if is_active { theme::BG_CARD_HOVER } else { hsla(0.0, 0.0, 0.0, 0.0) })
            .border_1()
            .border_color(if is_active { hsla(36.0 / 360.0, 0.65, 0.65, 0.25) } else { hsla(0.0, 0.0, 0.0, 0.0) })
            .hover(|s| s.bg(theme::BG_CARD_HOVER))
            .on_mouse_down(MouseButton::Left, cx.listener(move |this, _, _, cx| {
                this.active_tab = tab;
                cx.notify();
            }))
            .child(
                div()
                    .text_sm()
                    .child(icon),
            )
            .child(
                div()
                    .text_xs()
                    .font_weight(if is_active { FontWeight::BOLD } else { FontWeight::MEDIUM })
                    .text_color(if is_active { theme::ACCENT } else { theme::TEXT_SECONDARY })
                    .child(label),
            )
    }

    fn render_mood_chip(&self, mood: &'static str, cx: &mut Context<Self>) -> impl IntoElement {
        let is_active = self.selected_mood == mood;

        div()
            .px_3()
            .py_1()
            .rounded_full()
            .text_xs()
            .font_weight(FontWeight::MEDIUM)
            .bg(if is_active { theme::ACCENT } else { theme::BG_CARD })
            .text_color(if is_active { hsla(225.0 / 360.0, 0.16, 0.06, 1.0) } else { theme::TEXT_SECONDARY })
            .border_1()
            .border_color(if is_active { theme::ACCENT } else { theme::BORDER_HAIRLINE })
            .hover(|s| s.bg(if is_active { theme::ACCENT } else { theme::BG_CARD_HOVER }))
            .on_mouse_down(MouseButton::Left, cx.listener(move |this, _, _, cx| {
                this.selected_mood = mood.to_string();
                cx.notify();
            }))
            .child(mood)
    }
}

fn format_duration(ms: u32) -> String {
    let seconds = ms / 1000;
    let mins = seconds / 60;
    let rem_secs = seconds % 60;
    format!("{:02}:{:02}", mins, rem_secs)
}

fn main() {
    gpui_platform::application()
        .with_quit_mode(QuitMode::LastWindowClosed)
        .run(|cx: &mut App| {
            let bounds = Bounds::centered(None, size(px(1120.0), px(720.0)), cx);
            cx.open_window(
                WindowOptions {
                    window_bounds: Some(WindowBounds::Windowed(bounds)),
                    titlebar: Some(TitlebarOptions {
                        title: Some("Nutsty Native".into()),
                        appears_transparent: true,
                        traffic_light_position: None,
                    }),
                    ..Default::default()
                },
                |_, cx| cx.new(|cx| NutstyApp::new(cx)),
            )
            .unwrap();
            cx.activate(true);
        });
}
