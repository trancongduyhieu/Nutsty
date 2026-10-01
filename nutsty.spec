# -*- mode: python ; coding: utf-8 -*-
import os
import sys

block_cipher = None

added_datas = [
    ('compat', 'compat'),
    ('components', 'components'),
    ('assets', 'assets'),
    ('backend', 'backend'),
    ('shell.qml', '.'),
    ('bin', 'bin'),
]

# Do not bundle local developer's library.json into Windows portable release

try:
    from PyInstaller.utils.hooks import collect_data_files, collect_submodules
    added_datas += collect_data_files('ytmusicapi')
except Exception:
    pass

hidden_imports = [
    'PySide6.QtCore',
    'PySide6.QtGui',
    'PySide6.QtWidgets',
    'PySide6.QtQml',
    'PySide6.QtQuick',
    'PySide6.QtQuickControls2',
    'PySide6.QtQuickLayouts',
    'PySide6.QtMultimedia',
    'yt_dlp',
    'http',
    'http.server',
    'http.client',
    'email',
    'email.message',
    'email.parser',
    'html',
    'ssl',
    'socket',
    'threading',
    'subprocess',
    'ctypes',
    'ctypes.wintypes',
    'mutagen',
    'ytmusicapi',
    'syncedlyrics',
    'syncedlyrics.providers',
    'syncedlyrics.providers.base',
    'syncedlyrics.providers.lrclib',
    'syncedlyrics.providers.netease',
    'syncedlyrics.providers.musixmatch',
    'syncedlyrics.providers.deezer',
    'syncedlyrics.providers.genius',
    'syncedlyrics.providers.megalobiz',
    'syncedlyrics.providers.spotify',
    'bs4',
    'beautifulsoup4',
    'rapidfuzz',
    'requests',
    'sqlite3',
    'uuid',
    'random',
    'datetime',
    'base64',
    'shutil',
    'tempfile',
    'pathlib',
    'urllib.request',
    'urllib.error',
    'urllib.parse',
    'auth_server',
    'cloud_relay_client',
    'social_routes',
    'music_routes',
    'player_daemon',
    'download_manager',
    'library',
    'palette_extractor',
    'lyrics_helper',
    'playlist_manager',
    'ytmusic_helper',
    'social_notes',
    'platform_compat',
    'browser_login',
    'spotify_importer',
    'websockets',
    'websockets.client',
    'websockets.exceptions',
    'websockets.legacy',
    'websockets.legacy.client',
    'certifi',
    'urllib3',
]

try:
    hidden_imports += collect_submodules('ytmusicapi')
    hidden_imports += collect_submodules('syncedlyrics')
except Exception:
    pass

try:
    import certifi
    certifi_dir = os.path.dirname(certifi.__file__)
    if os.path.exists(certifi_dir):
        added_datas.append((certifi_dir, 'certifi'))
except Exception:
    pass

a = Analysis(
    ['launcher_win.py'],
    pathex=['.', 'backend'],
    binaries=[],
    datas=added_datas,
    hiddenimports=hidden_imports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=['tkinter', 'matplotlib', 'scipy', 'numpy'],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='Nutsty',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon='assets/icons/nutsty.ico' if os.path.exists('assets/icons/nutsty.ico') else None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='Nutsty',
)
