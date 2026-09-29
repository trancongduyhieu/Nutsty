<div align="center">

# Nutsty

**The Dual-Platform Desktop Music & Streaming Player for Linux Wayland & Windows**

[![Platform](https://img.shields.io/badge/Platform-Linux%20Wayland%20%7C%20Windows-blue?style=flat-square)](#)
[![UI](https://img.shields.io/badge/UI-Qt%206%20%2F%20Quickshell-41CD52?style=flat-square&logo=qt)](#)
[![Engine](https://img.shields.io/badge/Audio-mpv%20IPC%20Daemon-9b59b6?style=flat-square)](#)
[![Cloud](https://img.shields.io/badge/Cloud%20Relay-Cloudflare%20Workers%20%2B%20D1-F38020?style=flat-square&logo=cloudflare)](#)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](#)
[![Version](https://img.shields.io/badge/Release-v1.0.0-gold?style=flat-square)](#)

*Nutsty la trinh phat nhac may tinh de ban hien dai, ket hop hoan hao giua tham my kinh long Liquid Glass thich ung mau sac va bo may am thanh do tre thap.*

---

</div>

## Tinh Nang Noi Bat (Key Highlights)

### 1. Bo May Loi Bai Hat Desktop Dien Anh (Desktop Lyrics Engine)
Tich hop hien thi loi bai hat truc tiep len man hinh desktop (Wayland Layer-Shell native tren Linux va Frameless Overlay tren Windows) voi 4 phong cach nghe thuat:
- **Mau 1: Dien anh Serif (`Cinematic Serif`)**: 1 dong typography *Instrument Serif* nghieng, chuyen nhip so le muot ma va do bong dien anh sau da tang (*Universal Cinematic Shadows*).
- **Mau 2: Apple Music (`Apple Music DoF`)**: Hien thi 5 dong kem chieu sau quang hoc (Optical Depth-of-Field), lam mo mem mai va dong bo karaoke tung am tiet (*Syllable-level Karaoke Sync*).
- **Mau 3: Toi gian luot (`Minimal Glide`)**: 2 dong toi gian voi hieu ung chuyen dong truot muot ma kem vet mo (*Motion Blur*).
- **Mau 4: Do hoa Chuyen dong (`Motion Typography`)**: Khung Bento voi cac chuyen dong do hoa dong luc hoc hien dai.

---

### 2. Bo May Phat Nhac Do Tre Thap (Audiophile Audio Pipeline)
- Trinh dieu khien nen resident daemon giao tiep voi **`mpv`** qua **Unix Domain Socket** (`/tmp/nutsty_mpv.sock` tren Linux) hoac **Named Pipe** (`\\.\pipe\nutsty_mpv` tren Windows).
- Phat truc tuyen tuc thi khong tre (gapless streaming, zero-rebuffer seek).
- Chong chan luong am thanh YouTube Music voi kien truc **Android Client Session Resolver** tu dong.

---

### 3. Chuyen Giao Danh Sach Phat Spotify (Spotify Transfer Stage)
- Ho tro dan link moi playlist Spotify (cong khai hoac chia se ca nhan) de nhap ve Nutsty.
- **San khau Chuyen giao Dia xoay (Arc Gunshot Stage)**: Dia than xoay chuyen vi tri mem mai, cac bai hat xep theo duong cong hinh canh cung va ban thang vao tam dia khi nap xong.
- Tu dong doi soat va khop luong am thanh chat luong cao 256kbps hoan toan mien phi.

---

### 4. Nghe Cung va Mang Xa Hoi Cloudflare Edge (Global Social Sync)
- Kien truc Serverless Edge toan cau chay tren **Cloudflare Workers** ket hop co so du lieu phan tan **Cloudflare D1**.
- **Nghe Cung (Listen Along 1:1)**: Dong bo bai hat, trang thai phat va tien trinh thoi gian thuc giua hai may tinh du o Linux hay Windows.
- **Ghi chu 24h (Stories & Daily Notes)**: Chia se bai hat yeu thich kem suy nghi trong 24 gio.
- **Bong bong chat Danmaku**: Gui tin nhan tuc thi bay qua man hinh khi dang nghe cung ban be.

---

### 5. Kinh Long Liquid Glass va Phoi Mau Thich Ung (Chromatic Salience)
- **Thuat toan OKLAB / OKLCH**: Tu dong trich xuat cac mang mau diem nhan tu hinh nen may tinh va anh bia album de bien doi giao dien thich ung hai hoa theo thoi gian thuc.
- **Nguyen ly Bo goc Dong tam**: $R_{\text{trong}} = R_{\text{ngoai}} - \text{Khoang cach}$ ket hop vien ban trong suot hairline 1px sang trong.
- **Thiet ke Thuan bieu tuong (100% SVG)**: Tuyet doi khong dung ky tu emoji tren toan bo giao dien, ton trong ngon ngu do hoa toi gian va chuyen nghiep.
- **Da ngon ngu Chuan muc (Strict Bimodal Localization)**: Ho tro hoan hao 100% Tieng Viet thuan tuy va Tieng Anh chuan muc.

---

## Cai Dat va Khoi Chay (Quick Start)

### Tren Linux (Wayland / Niri / Hyprland / KDE Wayland)
Yeu cau he thong: `python3 (>= 3.10)`, `quickshell`, `mpv`, `ffmpeg`.

```bash
# Clone repository
git clone https://github.com/nutsty/nutsty.git
cd nutsty

# Cap quyen thuc thi va khoi chay 1-cham (tu dong tao venv va cai phu thuoc)
chmod +x ./run.sh
./run.sh
```

---

### Tren Windows (Windows 10 / 11)
Yeu cau he thong: `Python >= 3.10`, `mpv`.

```bat
:: Khoi chay 1-cham qua batch script
start.bat
```

Hoac dong goi thanh file cai dat doc lap `.exe`:
```bat
build_exe.bat
```

---

## Phim Tat Tien Dung (Shortcuts)

| Phim tat | Chuc nang |
| :--- | :--- |
| <kbd>Space</kbd> | Phat / Tam dung bai hat |
| <kbd>Ctrl</kbd> + <kbd>→</kbd> | Chuyen sang bai tiep theo |
| <kbd>Ctrl</kbd> + <kbd>←</kbd> | Quay lai bai truoc |
| <kbd>M</kbd> | Bat / Tat loi bai hat Desktop noi |
| <kbd>Ctrl</kbd> + <kbd>Q</kbd> | Thoat ung dung hoan toan |

---

## Kien Truc Ma Nguon (System Architecture)

```
Nutsty/
├── shell.qml                       # Cua so chinh & Floating Window QML
├── launcher_win.py                 # PySide6 + System Tray Host tren Windows
├── run.sh / start.bat              # Script khoi chay 1-cham da nen tang
├── backend/
│   ├── player_daemon.py            # Trinh dieu khien nen mpv qua IPC Socket
│   ├── stream_resolver.py          # Bo phan giai stream YouTube Music Android
│   ├── spotify_importer.py         # Trinh chuyen giao playlist Spotify & Arc Stage
│   ├── social_relay_core.py        # SSOT quan ly danh tinh & ket noi ban be
│   ├── catalog_engine.py           # Bo may nap goi y bai hat & ke nhac
│   └── palette_extractor.py        # OKLAB Chromatic Salience phan tich mau sac
├── cloud_relay/                    # Cloudflare Worker & D1 Database bindings
└── components/
    ├── DesktopLyricsWidget.qml     # Universal Desktop Lyrics Harness (Wayland/Win32)
    ├── SpotifyImportModal.qml      # San khau chuyen giao Spotify Arc Gunshot
    ├── ShuffleButton.qml           # Nut tron bai hat thiet ke Liquid Glass
    ├── SettingsModal.qml           # Cai dat he thong, tai khoan & mau loi bai hat
    └── I18n.qml                    # Singleton ban dia hoa song ngu nghiem ngat
```

---

## Ban Quyen (License)

Du an duoc phan phoi duoi giay phep ma nguon mo **MIT License**.
Moi dong gop (Pull Request, Issue bao loi, Y tuong thiet ke) deu duoc hoan nghenh nong nhiet!
