use nutsty_library::{
    add_track, batch_delete_tracks, delete_track, get_grouped_albums, save_library_json,
    scan_all_tracks,
};
use std::env;
use std::path::PathBuf;

fn get_library_json_path() -> PathBuf {
    if let Ok(dir) = env::var("NUTSTY_APP_DIR") {
        return PathBuf::from(dir).join("library.json");
    }
    let cur = PathBuf::from("library.json");
    if cur.exists() {
        return cur;
    }
    if let Ok(exe) = env::current_exe() {
        if let Some(parent) = exe.parent() {
            if parent.ends_with("bin") {
                if let Some(root) = parent.parent() {
                    return root.join("library.json");
                }
            }
            if let Some(target) = parent.parent() {
                if let Some(rs_root) = target.parent() {
                    if let Some(root) = rs_root.parent() {
                        let candidate = root.join("library.json");
                        if candidate.exists() {
                            return candidate;
                        }
                    }
                }
            }
        }
    }
    if let Some(home) = dirs::home_dir() {
        let p = home.join("Applications").join("FrostifyLocal").join("library.json");
        if p.exists() {
            return p;
        }
    }
    cur
}

fn main() {
    // Restrict Rayon worker pool to 4 threads to prevent allocator arena explosion on 32-core systems
    let _ = rayon::ThreadPoolBuilder::new().num_threads(4).build_global();

    let args: Vec<String> = env::args().collect();
    let json_path = get_library_json_path();

    if args.len() > 1 && args[1] == "delete" {
        let target_path = args.get(2).map(|s| s.as_str()).unwrap_or("");
        let filename = args.get(3).map(|s| s.as_str()).unwrap_or("");
        let title = args.get(4).map(|s| s.as_str()).unwrap_or("");
        let res = delete_track(&json_path, target_path, filename, title);
        println!("{}", serde_json::to_string(&res).unwrap_or_default());
    } else if args.len() > 1 && args[1] == "batch_delete" && args.len() > 2 {
        let raw = &args[2];
        let paths: Vec<String> = if let Ok(arr) = serde_json::from_str(raw) {
            arr
        } else {
            vec![raw.clone()]
        };
        let res = batch_delete_tracks(&json_path, &paths);
        println!("{}", serde_json::to_string(&res).unwrap_or_default());
    } else if args.len() > 1 && args[1] == "add" && args.len() > 2 {
        let audio_path = &args[2];
        let title = args.get(3).map(|s| s.as_str()).unwrap_or("");
        let artist = args.get(4).map(|s| s.as_str()).unwrap_or("");
        let vid = args.get(5).map(|s| s.as_str()).unwrap_or("");
        let img = args.get(6).map(|s| s.as_str()).unwrap_or("");
        if let Some(item) = add_track(&json_path, audio_path, title, artist, vid, img) {
            println!(
                "Instantly indexed '{}' into {} (id {})",
                item.title,
                json_path.display(),
                item.id
            );
        } else {
            eprintln!("Failed to add track: {}", audio_path);
            std::process::exit(1);
        }
    } else if args.len() > 1 && args[1] == "albums" {
        let albums = get_grouped_albums(&json_path);
        println!("{}", serde_json::to_string(&albums).unwrap_or_else(|_| "[]".to_string()));
    } else {
        // "scan" or default
        let t_start = std::time::Instant::now();
        let tracks = scan_all_tracks();
        let count = tracks.len();
        if let Err(e) = save_library_json(&json_path, &tracks) {
            eprintln!("Error saving library.json: {}", e);
            std::process::exit(1);
        }
        let elapsed = t_start.elapsed();
        println!(
            "Scanned {} tracks into {} in {:.2?}",
            count,
            json_path.display(),
            elapsed
        );
    }
}
