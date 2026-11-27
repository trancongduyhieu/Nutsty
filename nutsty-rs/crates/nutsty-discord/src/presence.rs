//! What Discord should show, worked out from what Nutsty reports. No I/O here, so it is tested
//! on its own: the activity JSON, when two activities look the same, and the send budget.

use serde_json::{json, Map, Value};
use std::collections::VecDeque;

/// Shown when the song has no artwork Discord can fetch (a local file, or none at all).
pub const LOGO_URL: &str =
    "https://raw.githubusercontent.com/trancongduyhieu/Nutsty/main/assets/discord/nutsty-mark.png";

/// Discord's limit for a status line and for a button label.
const LINE_MAX: usize = 128;
const BUTTON_MAX: usize = 32;
/// A position read twice drifts a little; only a jump bigger than this (a seek) is news.
const TIME_SLACK_MS: i64 = 2_500;
/// A paused song stays up, frozen, this long and then comes down.
pub const KEEP_PAUSED_MS: i64 = 10 * 60_000;

/// Discord turns down a one-letter line; this blank-looking letter makes it two.
const BLANK: char = '\u{2800}';

#[derive(Clone, Debug, PartialEq)]
pub struct Activity {
    pub details: String,
    pub state: Option<String>,
    pub large_image: String,
    pub large_text: Option<String>,
    pub small_text: Option<String>,
    pub start_ms: Option<i64>,
    pub end_ms: Option<i64>,
    pub button: Option<(String, String)>,
    pub playing: bool,
}

/// A status line as Discord takes it: None when empty, padded when one letter, cut at the limit.
pub fn line(raw: &str, max: usize) -> Option<String> {
    let text = raw.split_whitespace().collect::<Vec<_>>().join(" ");
    let count = text.chars().count();
    match count {
        0 => None,
        1 => Some(format!("{text}{BLANK}")),
        n if n > max => {
            let cut: String = text.chars().take(max - 1).collect();
            Some(format!("{}…", cut.trim_end()))
        }
        _ => Some(text),
    }
}

fn str_of(v: &Value, key: &str) -> String {
    v.get(key).and_then(Value::as_str).unwrap_or("").to_string()
}

fn num_of(v: &Value, key: &str) -> f64 {
    v.get(key).and_then(Value::as_f64).filter(|n| n.is_finite()).unwrap_or(0.0)
}

fn is_web_url(url: &str) -> bool {
    url.starts_with("https://") || url.starts_with("http://")
}

/// YouTube Music artwork comes as a small square (`=w120-h120...`); Discord shows up to 240 px.
fn bigger_artwork(url: &str) -> String {
    if url.contains("googleusercontent.com")
        && let Some(i) = url.rfind("=w") {
            return format!("{}=w544-h544-l90-rj", &url[..i]);
        }
    url.to_string()
}

impl Activity {
    /// Builds the activity from one line Nutsty sent, read at `now_ms`. None when there is no
    /// song name, which is the one line Discord needs.
    pub fn from_report(v: &Value, now_ms: i64) -> Option<Activity> {
        let details = line(&str_of(v, "details"), LINE_MAX)?;
        let cover = str_of(v, "cover");
        let large_image = if is_web_url(&cover) { bigger_artwork(&cover) } else { LOGO_URL.to_string() };
        let playing = v.get("playing").and_then(Value::as_bool).unwrap_or(false);
        let position = num_of(v, "position").max(0.0);
        let duration = num_of(v, "duration");
        // a paused song gets no times, or Discord would carry on moving the bar
        let (start_ms, end_ms) = if playing && duration > 0.0 {
            let start = now_ms - (position.min(duration) * 1000.0) as i64;
            (Some(start), Some(start + (duration * 1000.0) as i64))
        } else {
            (None, None)
        };
        let button_url = str_of(v, "button_url");
        let button = line(&str_of(v, "button_label"), BUTTON_MAX)
            .filter(|_| is_web_url(&button_url))
            .map(|label| (label, button_url));
        Some(Activity {
            details,
            state: line(&str_of(v, "state"), LINE_MAX),
            large_image,
            large_text: line(&str_of(v, "large_text"), LINE_MAX),
            small_text: line(&str_of(v, "small_text"), LINE_MAX),
            start_ms,
            end_ms,
            button,
            playing,
        })
    }

    /// Whether sending this instead of `other` changes nothing people can see.
    pub fn looks_like(&self, other: &Activity) -> bool {
        fn near(a: Option<i64>, b: Option<i64>) -> bool {
            match (a, b) {
                (None, None) => true,
                (Some(a), Some(b)) => (a - b).abs() < TIME_SLACK_MS,
                _ => false,
            }
        }
        let strip = |a: &Activity| Activity { start_ms: None, end_ms: None, ..a.clone() };
        strip(self) == strip(other) && near(self.start_ms, other.start_ms) && near(self.end_ms, other.end_ms)
    }

    /// The activity as SET_ACTIVITY takes it. Type 2 is "Listening to".
    pub fn to_json(&self) -> Value {
        let mut act = Map::new();
        act.insert("type".into(), json!(2));
        act.insert("details".into(), json!(self.details));
        if let Some(state) = &self.state {
            act.insert("state".into(), json!(state));
        }
        if let Some(start) = self.start_ms {
            let mut ts = Map::new();
            ts.insert("start".into(), json!(start));
            if let Some(end) = self.end_ms {
                ts.insert("end".into(), json!(end));
            }
            act.insert("timestamps".into(), Value::Object(ts));
        }
        let mut assets = Map::new();
        assets.insert("large_image".into(), json!(self.large_image));
        if let Some(t) = &self.large_text {
            assets.insert("large_text".into(), json!(t));
        }
        // the small badge only makes sense next to real artwork, not next to the logo itself
        if self.large_image != LOGO_URL {
            assets.insert("small_image".into(), json!(LOGO_URL));
            if let Some(t) = &self.small_text {
                assets.insert("small_text".into(), json!(t));
            }
        }
        act.insert("assets".into(), Value::Object(assets));
        if let Some((label, url)) = &self.button {
            act.insert("buttons".into(), json!([{ "label": label, "url": url }]));
        }
        act.insert("instance".into(), json!(false));
        Value::Object(act)
    }
}

/// Discord closes the connection past five activity updates in twenty seconds.
pub struct SendBudget {
    sent: VecDeque<i64>,
}

impl SendBudget {
    const LIMIT: usize = 5;
    const WINDOW_MS: i64 = 20_000;

    pub fn new() -> Self {
        SendBudget { sent: VecDeque::new() }
    }

    /// Milliseconds until another update may go out; 0 means now.
    pub fn wait_ms(&mut self, now_ms: i64) -> i64 {
        while self.sent.front().is_some_and(|t| now_ms - t >= Self::WINDOW_MS) {
            self.sent.pop_front();
        }
        if self.sent.len() < Self::LIMIT {
            0
        } else {
            self.sent.front().map_or(0, |t| t + Self::WINDOW_MS - now_ms).max(1)
        }
    }

    pub fn record(&mut self, now_ms: i64) {
        self.sent.push_back(now_ms);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn report(playing: bool, pos: f64) -> Value {
        json!({
            "details": "Fake Plastic Trees", "state": "Radiohead", "large_text": "The Bends",
            "small_text": "Nutsty",
            "cover": "https://lh3.googleusercontent.com/abc=w120-h120-l90-rj",
            "button_label": "Listen on YouTube Music",
            "button_url": "https://music.youtube.com/watch?v=x",
            "position": pos, "duration": 290.0, "playing": playing
        })
    }

    #[test]
    fn lines_follow_discord_rules() {
        assert_eq!(line("  ", 128), None);
        assert_eq!(line("a", 128), Some(format!("a{BLANK}")));
        assert_eq!(line("a  b\n c", 128).as_deref(), Some("a b c"));
        let long = "x".repeat(200);
        let cut = line(&long, 128).unwrap();
        assert_eq!(cut.chars().count(), 128);
        assert!(cut.ends_with('…'));
    }

    #[test]
    fn playing_song_gets_a_bar_from_start_to_end() {
        let a = Activity::from_report(&report(true, 96.0), 1_000_000).unwrap();
        assert_eq!(a.start_ms, Some(1_000_000 - 96_000));
        assert_eq!(a.end_ms, Some(1_000_000 - 96_000 + 290_000));
        assert!(a.large_image.ends_with("=w544-h544-l90-rj"));
        let j = a.to_json();
        assert_eq!(j["type"], 2);
        assert_eq!(j["buttons"][0]["label"], "Listen on YouTube Music");
        assert_eq!(j["assets"]["small_image"], LOGO_URL);
    }

    #[test]
    fn paused_song_has_no_times() {
        let a = Activity::from_report(&report(false, 96.0), 1_000_000).unwrap();
        assert_eq!(a.start_ms, None);
        assert!(a.to_json().get("timestamps").is_none());
    }

    #[test]
    fn local_file_falls_back_to_the_logo_without_badge() {
        let mut r = report(true, 0.0);
        r["cover"] = json!("file:///home/x/cover.jpg");
        let j = Activity::from_report(&r, 0).unwrap().to_json();
        assert_eq!(j["assets"]["large_image"], LOGO_URL);
        assert!(j["assets"].get("small_image").is_none());
    }

    #[test]
    fn no_title_means_nothing_to_show() {
        let mut r = report(true, 0.0);
        r["details"] = json!("");
        assert!(Activity::from_report(&r, 0).is_none());
    }

    #[test]
    fn drift_is_not_news_but_a_seek_is() {
        let a = Activity::from_report(&report(true, 10.0), 100_000).unwrap();
        // two seconds later the song is two seconds further: same start
        let drift = Activity::from_report(&report(true, 12.4), 102_000).unwrap();
        assert!(a.looks_like(&drift));
        let seek = Activity::from_report(&report(true, 60.0), 102_000).unwrap();
        assert!(!a.looks_like(&seek));
        let paused = Activity::from_report(&report(false, 12.0), 102_000).unwrap();
        assert!(!a.looks_like(&paused));
    }

    #[test]
    fn budget_allows_five_in_twenty_seconds() {
        let mut b = SendBudget::new();
        for i in 0..5 {
            assert_eq!(b.wait_ms(i * 100), 0);
            b.record(i * 100);
        }
        assert_eq!(b.wait_ms(1_000), 19_000);
        assert_eq!(b.wait_ms(20_000), 0);
    }
}
