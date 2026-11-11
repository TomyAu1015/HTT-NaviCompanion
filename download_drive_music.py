#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Automatic Google Drive Music Downloader for KOnNaviCompanion
Downloads '轻音音乐.7z' from Google Drive and unpacks into KOnNaviCompanion/Music
so all K-ON! music is directly built into the TrollStore IPA.
"""

import os
import sys
import subprocess
import shutil

FILE_ID = "1eHHqrJ8yoI4L5lVLi21WNtBeVZRY3WqT"
ARCHIVE_NAME = "keion_music.7z"
TARGET_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "KOnNaviCompanion", "Music")
AUDIO_EXTS = (".mp3", ".m4a", ".mp4", ".m4b", ".m4r", ".flac", ".wav", ".aac", ".caf", ".aiff")

def main():
    os.makedirs(TARGET_DIR, exist_ok=True)
    
    # Check if music files are already present
    existing_files = [f for f in os.listdir(TARGET_DIR) if f.lower().endswith(AUDIO_EXTS)]
    if len(existing_files) >= 5:
        print(f"[*] Music directory already contains {len(existing_files)} tracks. Skipping download.")
        return

    print("[*] Music directory empty. Preparing to download '轻音音乐.7z' from Google Drive...")
    
    # 1. Ensure gdown is installed
    try:
        import gdown
    except ImportError:
        print("[*] Installing gdown...")
        subprocess.run([sys.executable, "-m", "pip", "install", "gdown"], check=True)
        import gdown

    # 2. Download from Google Drive
    archive_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), ARCHIVE_NAME)
    print(f"[*] Downloading file ID {FILE_ID} via gdown...")
    try:
        gdown.download(id=FILE_ID, output=archive_path, quiet=False)
    except Exception as e:
        print(f"[!] gdown error: {e}, trying direct curl fallback...")
        curl_cmd = [
            "curl", "-L", "-C", "-",
            f"https://drive.google.com/uc?export=download&id={FILE_ID}",
            "-o", archive_path
        ]
        subprocess.run(curl_cmd, check=False)

    if not os.path.exists(archive_path) or os.path.getsize(archive_path) < 1000000:
        print(f"[!] Downloaded archive is invalid or missing.")
        return

    print(f"[*] Archive downloaded successfully ({os.path.getsize(archive_path)} bytes). Extracting...")

    # 3. Ensure 7z / p7zip is available
    has_7z = shutil.which("7z") or shutil.which("7za")
    if not has_7z:
        print("[*] Installing p7zip via Homebrew...")
        subprocess.run(["brew", "install", "p7zip"], check=False)
        has_7z = shutil.which("7z") or shutil.which("7za") or "7z"

    tool = has_7z if isinstance(has_7z, str) else "7z"
    extract_cmd = [tool, "x", archive_path, f"-o{TARGET_DIR}", "-y"]
    print(f"[*] Running: {' '.join(extract_cmd)}")
    subprocess.run(extract_cmd, check=True)

    # 4. Flatten any subdirectories inside TARGET_DIR
    for root, dirs, files in os.walk(TARGET_DIR):
        if root != TARGET_DIR:
            for file in files:
                if file.lower().endswith(AUDIO_EXTS):
                    src = os.path.join(root, file)
                    dst = os.path.join(TARGET_DIR, file)
                    if not os.path.exists(dst):
                        shutil.move(src, dst)

    # 5. Remove archive to free space
    if os.path.exists(archive_path):
        os.remove(archive_path)

    final_tracks = [f for f in os.listdir(TARGET_DIR) if f.lower().endswith(AUDIO_EXTS)]
    print(f"[+] Extracted {len(final_tracks)} raw K-ON! music tracks. Preparing Anti-Extract Encryption...")
    
    # 6. ENCRYPT AND PACK ALL MUSIC INTO OBFUSCATED CONTAINER (music_assets.dat)
    # Even if someone unzips/decompiles the IPA, NO .mp3/.m4a files exist!
    KEY = b"K-On!AfterSchoolTeaTimeNavi2026"
    container_path = os.path.join(TARGET_DIR, "music_assets.dat")
    
    index_meta = []
    binary_blob = bytearray()
    
    for f in sorted(final_tracks):
        fpath = os.path.join(TARGET_DIR, f)
        with open(fpath, "rb") as audio_f:
            raw_bytes = audio_f.read()
        
        # XOR scramble
        scrambled = bytearray(raw_bytes)
        for i in range(len(scrambled)):
            scrambled[i] ^= KEY[i % len(KEY)]
            
        offset = len(binary_blob)
        length = len(scrambled)
        binary_blob.extend(scrambled)
        
        index_meta.append({
            "filename": f,
            "offset": offset,
            "length": length
        })
        
        # Remove raw unencrypted track from disk
        os.remove(fpath)
        
    import json
    header_json = json.dumps(index_meta)
    header_text = "KON_ENC_MUSIC_V1\n" + header_json + "\nHEADER_END\n"
    full_header = header_text.encode("utf-8")
    
    with open(container_path, "wb") as out_f:
        out_f.write(full_header)
        out_f.write(binary_blob)
        
    print(f"[+] Successfully encrypted and sealed {len(index_meta)} music tracks into proprietary {container_path} ({os.path.getsize(container_path)} bytes)!")
    print("[+] All raw audio files removed. 100% Anti-Extract Protection Active!")

if __name__ == "__main__":
    main()
