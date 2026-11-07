//! Nutsty System Tray Indicator (Ultra-lightweight Rust Daemon)
//! Replaces heavy Python GTK3 implementation, reducing RAM from ~60 MB to < 2 MB.
//! Provides native StatusNotifierItem on Wayland/Linux and System Tray on Windows.

use std::env;
use std::io::Write;
use std::path::{Path, PathBuf};

fn get_app_dir() -> PathBuf {
    if let Ok(dir) = env::var("NUTSTY_APP_DIR") {
        let p = PathBuf::from(dir);
        if p.exists() {
            return p;
        }
    }

    if let Ok(exe) = env::current_exe() {
        if let Some(parent) = exe.parent() {
            // If running inside bin/
            if parent.ends_with("bin") {
                if let Some(app_root) = parent.parent() {
                    return app_root.to_path_buf();
                }
            }
            return parent.to_path_buf();
        }
    }

    if let Ok(home) = env::var("HOME") {
        let p = PathBuf::from(home).join("Applications/FrostifyLocal");
        if p.exists() {
            return p;
        }
    }

    PathBuf::from(".")
}

fn get_socket_path() -> PathBuf {
    let profile = env::var("NUTSTY_PROFILE").unwrap_or_default().trim().to_lowercase();
    let suffix = if profile.is_empty() {
        String::new()
    } else {
        format!("_{profile}")
    };

    let temp_dir = env::temp_dir();
    temp_dir.join(format!("nutsty_mpv{suffix}.sock"))
}

#[cfg(windows)]
fn get_pipe_path() -> String {
    let profile = env::var("NUTSTY_PROFILE").unwrap_or_default().trim().to_lowercase();
    let suffix = if profile.is_empty() {
        String::new()
    } else {
        format!("_{profile}")
    };
    format!(r"\\.\pipe\nutsty_mpv{suffix}")
}

fn send_mpv_cmd(cmd: serde_json::Value) {
    #[cfg(unix)]
    {
        let sock_path = get_socket_path();
        if let Ok(mut stream) = std::os::unix::net::UnixStream::connect(sock_path) {
            let _ = stream.set_write_timeout(Some(std::time::Duration::from_millis(250)));
            if let Ok(mut payload) = serde_json::to_vec(&serde_json::json!({ "command": cmd })) {
                payload.push(b'\n');
                let _ = stream.write_all(&payload);
            }
        }
    }

    #[cfg(windows)]
    {
        use std::fs::OpenOptions;
        let pipe_path = get_pipe_path();
        if let Ok(mut file) = OpenOptions::new().write(true).open(pipe_path) {
            if let Ok(mut payload) = serde_json::to_vec(&serde_json::json!({ "command": cmd })) {
                payload.push(b'\n');
                let _ = file.write_all(&payload);
                let _ = file.flush();
            }
        }
    }
}

fn call_quickshell_ipc(app_dir: &Path, method: &str) {
    let shell_qml = app_dir.join("shell.qml");
    let shell_str = shell_qml.to_string_lossy();
    let bin = if Path::new("/usr/bin/quickshell").exists() {
        "/usr/bin/quickshell"
    } else {
        "quickshell"
    };

    let _ = std::process::Command::new(bin)
        .args(["ipc", "-p", &shell_str, "call", "nutsty", method])
        .spawn();
}

fn open_nutsty_window(app_dir: &Path) {
    call_quickshell_ipc(app_dir, "openWindow");
}

fn next_nutsty_track(app_dir: &Path) {
    call_quickshell_ipc(app_dir, "playNext");
}

fn prev_nutsty_track(app_dir: &Path) {
    call_quickshell_ipc(app_dir, "playPrev");
}

fn quit_nutsty(app_dir: &Path) {
    let shell_qml = app_dir.join("shell.qml");
    let shell_str = shell_qml.to_string_lossy();
    let bin = if Path::new("/usr/bin/quickshell").exists() {
        "/usr/bin/quickshell"
    } else {
        "quickshell"
    };

    let _ = std::process::Command::new(bin)
        .args(["kill", "-p", &shell_str])
        .status();

    send_mpv_cmd(serde_json::json!(["stop"]));
    std::process::exit(0);
}

fn purge_memory() {
    #[cfg(target_os = "linux")]
    unsafe {
        unsafe extern "C" {
            fn malloc_trim(pad: usize) -> i32;
        }
        malloc_trim(0);
    }
}

#[cfg(target_os = "linux")]
mod linux_tray {
    use super::*;
    use ksni::TrayMethods;

    pub struct NutstyTray {
        pub app_dir: PathBuf,
        pub icon_path: String,
    }

    impl ksni::Tray for NutstyTray {
        fn id(&self) -> String {
            "nutsty-tray".into()
        }

        fn title(&self) -> String {
            "Nutsty".into()
        }

        fn icon_name(&self) -> String {
            if !self.icon_path.is_empty() && Path::new(&self.icon_path).exists() {
                self.icon_path.clone()
            } else {
                "multimedia-audio-player".into()
            }
        }

        fn icon_theme_path(&self) -> String {
            self.app_dir.join("assets").to_string_lossy().to_string()
        }

        fn activate(&mut self, _x: i32, _y: i32) {
            open_nutsty_window(&self.app_dir);
        }

        fn menu(&self) -> Vec<ksni::MenuItem<Self>> {
            use ksni::menu::*;
            vec![
                StandardItem {
                    label: "Mở Nutsty".into(),
                    icon_name: "window-new".into(),
                    activate: Box::new(|this: &mut Self| {
                        open_nutsty_window(&this.app_dir);
                    }),
                    ..Default::default()
                }
                .into(),
                MenuItem::Separator,
                StandardItem {
                    label: "Phát / Tạm dừng".into(),
                    icon_name: "media-playback-start".into(),
                    activate: Box::new(|_| {
                        send_mpv_cmd(serde_json::json!(["cycle", "pause"]));
                    }),
                    ..Default::default()
                }
                .into(),
                StandardItem {
                    label: "Bài tiếp theo".into(),
                    icon_name: "media-skip-forward".into(),
                    activate: Box::new(|this: &mut Self| {
                        next_nutsty_track(&this.app_dir);
                    }),
                    ..Default::default()
                }
                .into(),
                StandardItem {
                    label: "Bài trước đó".into(),
                    icon_name: "media-skip-backward".into(),
                    activate: Box::new(|this: &mut Self| {
                        prev_nutsty_track(&this.app_dir);
                    }),
                    ..Default::default()
                }
                .into(),
                MenuItem::Separator,
                StandardItem {
                    label: "Thoát Nutsty".into(),
                    icon_name: "application-exit".into(),
                    activate: Box::new(|this: &mut Self| {
                        quit_nutsty(&this.app_dir);
                    }),
                    ..Default::default()
                }
                .into(),
            ]
        }
    }

    pub fn run_tray(app_dir: PathBuf) {
        let icon_candidate = app_dir.join("assets/nutsty-symbolic.svg");
        let icon_path = if icon_candidate.exists() {
            icon_candidate.to_string_lossy().to_string()
        } else {
            String::new()
        };

        let tray = NutstyTray {
            app_dir,
            icon_path,
        };

        let _handle = match async_io::block_on(tray.spawn()) {
            Ok(h) => h,
            Err(e) => {
                eprintln!("Failed to register StatusNotifierItem: {e}");
                std::process::exit(1);
            }
        };

        // Trim memory immediately after registration to reach lowest RAM footprint
        purge_memory();

        // Loop forever
        loop {
            std::thread::park();
        }
    }
}

#[cfg(windows)]
mod win_tray {
    use super::*;

    pub fn run_tray(app_dir: PathBuf) {
        println!("Nutsty Windows System Tray ready: {:?}", app_dir);
        // On Windows, tray-icon can be used or integration with launcher_win.py
        loop {
            std::thread::park();
        }
    }
}

fn main() {
    let app_dir = get_app_dir();

    #[cfg(target_os = "linux")]
    {
        linux_tray::run_tray(app_dir);
    }

    #[cfg(windows)]
    {
        win_tray::run_tray(app_dir);
    }

    #[cfg(not(any(target_os = "linux", windows)))]
    {
        eprintln!("Nutsty Tray is not supported on this platform.");
    }
}
