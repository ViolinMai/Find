#!/usr/bin/env python3
import os
import sys
import time
import json
import socket
import shutil
import hashlib
import subprocess
import threading
import fcntl
import requests
from pathlib import Path
from urllib.parse import unquote, urlparse

HTTP_SESSION = requests.Session()


def _dispatch_jellyfin_sync_worker(jf_meta: dict, action: str, pos_sec: float, dur_sec: float, is_paused: bool = False):
    if not jf_meta or not isinstance(jf_meta, dict):
        return
    api_url = str(jf_meta.get("api_url") or "").rstrip("/")
    token = str(jf_meta.get("api_token") or "").strip()
    user_id = str(jf_meta.get("user_id") or "").strip()
    item_id = str(jf_meta.get("item_id") or "").strip()
    if not api_url or not token or not item_id:
        return

    ticks = int(max(0.0, float(pos_sec)) * 10_000_000)
    media_source_id = str(jf_meta.get("media_source_id") or item_id)
    play_session_id = str(jf_meta.get("play_session_id") or "find_session")
    headers = {
        "Authorization": f'MediaBrowser Client="Find", Device="Linux PC", DeviceId="Find-Linux-PC", Version="2.0.0", Token="{token}"',
        "X-Emby-Token": token
    }
    payload = {
        "ItemId": item_id,
        "MediaSourceId": media_source_id,
        "PlaySessionId": play_session_id,
        "PositionTicks": ticks,
        "IsPaused": bool(is_paused),
        "IsMuted": False,
        "VolumeLevel": 100,
        "PlayMethod": "DirectPlay",
        "RepeatMode": "RepeatNone",
        "EventName": "TimeUpdate"
    }
    try:
        if action == "start":
            HTTP_SESSION.post(f"{api_url}/Sessions/Playing", json=payload, headers=headers, timeout=2.5)
        elif action == "progress":
            HTTP_SESSION.post(f"{api_url}/Sessions/Playing/Progress", json=payload, headers=headers, timeout=2.5)
            if user_id:
                HTTP_SESSION.post(
                    f"{api_url}/Users/{user_id}/PlayingItems/{item_id}/Progress",
                    params={"PositionTicks": ticks},
                    headers=headers,
                    timeout=2.5
                )
                played_now = bool(dur_sec > 0 and (pos_sec / dur_sec) >= 0.90)
                HTTP_SESSION.post(
                    f"{api_url}/Users/{user_id}/Items/{item_id}/UserData",
                    json={"PlaybackPositionTicks": 0 if played_now else ticks, "Played": played_now},
                    headers=headers,
                    timeout=2.5
                )
        elif action == "stop":
            payload["EventName"] = "PlaybackStopped"
            HTTP_SESSION.post(f"{api_url}/Sessions/Playing/Stopped", json=payload, headers=headers, timeout=2.5)
            if user_id:
                played = bool(dur_sec > 0 and (pos_sec / dur_sec) >= 0.90)
                final_ticks = 0 if played else ticks
                HTTP_SESSION.post(
                    f"{api_url}/Users/{user_id}/Items/{item_id}/UserData",
                    json={"PlaybackPositionTicks": final_ticks, "Played": played},
                    headers=headers,
                    timeout=2.5
                )
    except Exception:
        pass


def post_jellyfin_playback_event(jf_meta: dict, action: str, pos_sec: float, dur_sec: float, is_paused: bool = False):
    """Non-blocking async sender so MPV local tracking is NEVER delayed by HTTP calls."""
    if not jf_meta or not isinstance(jf_meta, dict) or not jf_meta.get("item_id"):
        return
    t = threading.Thread(
        target=_dispatch_jellyfin_sync_worker,
        args=(dict(jf_meta), action, float(pos_sec), float(dur_sec), bool(is_paused)),
        daemon=True
    )
    t.start()


def get_runtime_dir() -> Path:
    xdg_run = os.environ.get("XDG_RUNTIME_DIR", "")
    if xdg_run and os.path.isdir(xdg_run):
        rt = Path(xdg_run) / "find"
    else:
        rt = Path("/tmp") / f"find_runtime_{os.getuid()}"
    rt.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(rt, 0o700)
    except OSError:
        pass
    return rt


def get_paths():
    xdg_config = os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))
    config_dir = Path(xdg_config) / "find"
    config_dir.mkdir(parents=True, exist_ok=True)
    rt_dir = get_runtime_dir()
    return {
        "config_dir": config_dir,
        "config_file": config_dir / "config.json",
        "progress_file": config_dir / "media_progress.json",
        "runtime_dir": rt_dir,
        "pid_file": rt_dir / "find_media_daemon.pid",
    }


def run_toggle_hdr(arg: str):
    candidates = [
        shutil.which("toggle-hdr.sh"),
        str(Path.home() / ".local" / "bin" / "toggle-hdr.sh"),
    ]
    script_path = next((c for c in candidates if c and os.path.exists(c)), None)
    if not script_path:
        return
    try:
        subprocess.run(
            [script_path, arg],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=4
        )
    except Exception:
        pass


def load_json_safe(path: Path) -> dict:
    if path.exists():
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, dict):
                    return data
        except Exception:
            pass
    return {}


def save_json_atomic(path: Path, data: dict):
    lock_path = path.with_suffix(path.suffix + ".lock")
    tmp = path.with_suffix(f".tmp.{os.getpid()}.{threading.get_ident()}")
    snapshot = dict(data)
    try:
        with open(lock_path, "w", encoding="utf-8") as lf:
            fcntl.flock(lf, fcntl.LOCK_EX)
            try:
                with open(tmp, "w", encoding="utf-8") as f:
                    json.dump(snapshot, f, indent=2)
                    f.flush()
                    os.fsync(f.fileno())
                os.replace(tmp, path)
            finally:
                fcntl.flock(lf, fcntl.LOCK_UN)
    except Exception:
        if tmp.exists():
            try:
                tmp.unlink()
            except OSError:
                pass


SUBTITLE_EXTS = {".srt", ".ass", ".ssa", ".sub", ".vtt", ".idx", ".sup", ".smi"}


def find_matching_external_subs(video_file_path: str) -> list:
    """
    Finds all external subtitle files on disk matching the local video file's exact stem
    (or stem.lang.ass / stem_ar.srt, plus Subs/Subtitles subfolders), ensuring external subs
    always load even when Jellyfin integration or M3U8 playlists are active.
    """
    if not video_file_path or not os.path.isfile(video_file_path):
        return []
    vp = Path(video_file_path)
    parent = vp.parent
    stem = vp.stem
    stem_low = stem.lower()
    matched = []
    seen = set()

    search_dirs = [parent]
    for sd_name in ("Subs", "subs", "Subtitles", "subtitles", stem):
        sd = parent / sd_name
        if sd.is_dir():
            search_dirs.append(sd)

    for sdir in search_dirs:
        try:
            with os.scandir(str(sdir)) as it:
                for entry in it:
                    if not entry.is_file():
                        continue
                    sp = Path(entry.name)
                    if sp.suffix.lower() not in SUBTITLE_EXTS:
                        continue
                    sub_stem_low = sp.stem.lower()
                    if (
                        sub_stem_low == stem_low
                        or sub_stem_low.startswith(stem_low + ".")
                        or sub_stem_low.startswith(stem_low + "_")
                        or sub_stem_low.startswith(stem_low + "-")
                        or sub_stem_low.startswith(stem_low + " ")
                    ):
                        abs_sub = os.path.abspath(entry.path)
                        if abs_sub not in seen:
                            seen.add(abs_sub)
                            matched.append(abs_sub)
        except OSError:
            pass

    def _sub_prio(p_str: str):
        nl = Path(p_str).stem.lower()
        is_ar = any(x in nl for x in (".ar", "_ar", "-ar", "arabic", "ara"))
        is_ass = p_str.lower().endswith((".ass", ".ssa"))
        return (0 if is_ar else 1, 0 if is_ass else 1, p_str)

    matched.sort(key=_sub_prio)
    return matched


def resolve_mpv_path(raw_path: str, fallback_dir: str) -> str:
    if not raw_path:
        return ""
    p = str(raw_path).strip()
    if p.startswith("file://"):
        parsed = urlparse(p)
        p = unquote(parsed.path) or p[7:]
    if not os.path.isabs(p):
        p = os.path.abspath(os.path.join(fallback_dir, p))
    else:
        p = os.path.abspath(p)
    return p


def query_ipc(sock: socket.socket, prop: str, req_id: int):
    cmd = json.dumps({"command": ["get_property", prop], "request_id": req_id}) + "\n"
    sock.sendall(cmd.encode("utf-8"))
    buf = b""
    deadline = time.time() + 0.45
    while time.time() < deadline:
        try:
            chunk = sock.recv(4096)
            if not chunk:
                break
            buf += chunk
            for line in buf.decode("utf-8", errors="ignore").splitlines():
                try:
                    msg = json.loads(line)
                    if msg.get("request_id") == req_id:
                        if msg.get("error") == "success":
                            return msg.get("data")
                        return None
                except Exception:
                    pass
        except Exception:
            break
    return None


def send_ipc_cmd(sock: socket.socket, cmd_list: list, req_id: int = 99):
    """Sends an IPC command and drains its ack reply so the socket buffer stays clean."""
    try:
        payload = json.dumps({"command": cmd_list, "request_id": req_id}) + "\n"
        sock.sendall(payload.encode("utf-8"))
        sock.settimeout(0.15)
        try:
            sock.recv(4096)
        except Exception:
            pass
        sock.settimeout(0.6)
    except Exception:
        pass


def detect_external_sub(sock: socket.socket, fallback_dir: str) -> str:
    tracks = query_ipc(sock, "track-list", 5)
    if not isinstance(tracks, list):
        return ""
    for tr in tracks:
        if isinstance(tr, dict) and tr.get("type") == "sub" and tr.get("selected") is True and tr.get("external") is True:
            ext_fn = tr.get("external-filename", "")
            if ext_fn:
                resolved = resolve_mpv_path(ext_fn, fallback_dir)
                if resolved and os.path.exists(resolved):
                    return resolved
    return ""


def update_progress_entry(progress_file: Path, file_path: str, pos: float, dur: float, is_done: bool = None, ext_sub: str = None):
    if not file_path:
        return
    data = load_json_safe(progress_file)
    prev = data.get(file_path, {"position": 0.0, "duration": 0.0, "progress": 0.0, "watched": False, "ext_sub": ""})
    if not isinstance(prev, dict):
        prev = {"position": 0.0, "duration": 0.0, "progress": 0.0, "watched": False, "ext_sub": ""}

    prog = prev.get("progress", 0.0)
    if dur > 0:
        prog = min(1.0, max(0.0, pos / dur))
    watched = prev.get("watched", False)
    if is_done is not None:
        watched = bool(is_done)
    elif prog >= 0.90:
        watched = True
    if watched and prog < 0.90:
        prog = 1.0

    sub_val = ext_sub if ext_sub is not None else prev.get("ext_sub", "")
    new_entry = {
        "position": round(float(pos), 2),
        "duration": round(float(dur), 2),
        "progress": round(float(prog), 4),
        "watched": bool(watched),
        "ext_sub": str(sub_val or "")
    }
    now_ts = round(time.time(), 2)
    old_cmp = {k: v for k, v in data.get(file_path, {}).items() if k != "updated_at"}
    if old_cmp != new_entry:
        new_entry_with_ts = {**new_entry, "updated_at": now_ts}
        data[file_path] = new_entry_with_ts
        save_json_atomic(progress_file, data)
        # Also keep jellyfin_map.json in sync on disk so reopening the file never reads stale 0.0 progress
        jf_map_file = progress_file.parent / "jellyfin_map.json"
        if jf_map_file.exists():
            jf_map = load_json_safe(jf_map_file)
            if file_path in jf_map and isinstance(jf_map[file_path], dict):
                jf_map[file_path]["position"] = new_entry["position"]
                jf_map[file_path]["duration"] = new_entry["duration"]
                jf_map[file_path]["progress"] = new_entry["progress"]
                jf_map[file_path]["watched"] = new_entry["watched"]
                jf_map[file_path]["server_updated_at"] = now_ts
                save_json_atomic(jf_map_file, jf_map)


def run_daemon_loop():
    paths = get_paths()
    pid_file = paths["pid_file"]
    progress_file = paths["progress_file"]

    try:
        with open(pid_file, "w", encoding="utf-8") as f:
            f.write(str(os.getpid()))
    except Exception:
        pass

    sessions = {}
    active_hdr_sockets = set()
    last_airing_daemon_check_ts = 0.0

    # Import ConfigManager & AiringTracker so the background daemon sends OS notifications even when Find is closed!
    airing_tracker_instance = None
    try:
        sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
        from core.config import ConfigManager
        from core.airing_tracker import AiringTracker
        airing_tracker_instance = AiringTracker(ConfigManager())
    except Exception:
        airing_tracker_instance = None

    rt_dir = paths["runtime_dir"]
    try:
        while True:
            now_loop_ts = time.time()
            if airing_tracker_instance is not None and (now_loop_ts - last_airing_daemon_check_ts) >= 60.0:
                last_airing_daemon_check_ts = now_loop_ts
                def _bg_airing_check(tracker=airing_tracker_instance):
                    try:
                        tracker.config_mgr._config = tracker.config_mgr._load()
                        tracker.sync_mal_cache_sync(force=False)
                        tracker.sync_anilist_schedules_sync(force=False)
                        tracker.check_and_advance_airing_timers_sync(send_os_notification=True)
                    except Exception:
                        pass
                threading.Thread(target=_bg_airing_check, daemon=True).start()
            # Discover active find_mpv_*.json files in $XDG_RUNTIME_DIR/find (and /tmp fallback)
            meta_files = list(rt_dir.glob("find_mpv_*.json")) + list(Path("/tmp").glob("find_mpv_*.json"))
            for mf in meta_files:
                sock_name = mf.stem + ".sock"
                sock_path = str(mf.parent / sock_name)
                if sock_path not in sessions:
                    meta = load_json_safe(mf)
                    if meta:
                        init_file = os.path.abspath(meta.get("file_path", ""))
                        hdr_mode = bool(meta.get("hdr_mode", False))
                        init_pos = float(meta.get("initial_pos", 0.0) or 0.0)
                        anon_mode = bool(meta.get("anonymous_mode", False))
                        seek_already_done = bool(meta.get("initial_seek_done", False))
                        jf_meta = {} if anon_mode else (meta.get("jellyfin") if isinstance(meta.get("jellyfin"), dict) else {})
                        stream_map = meta.get("stream_to_local") if isinstance(meta.get("stream_to_local"), dict) else {}
                        sessions[sock_path] = {
                            "meta_file": str(mf),
                            "playlist_file": str(meta.get("playlist_file") or ""),
                            "active_file": init_file,
                            "base_dir": os.path.dirname(init_file) if init_file else "",
                            "hdr_mode": hdr_mode,
                            "initial_pos": init_pos,
                            "anonymous_mode": anon_mode,
                            "initial_seek_done": seek_already_done,
                            "chapters_injected": False,
                            "jellyfin": jf_meta,
                            "stream_to_local": stream_map,
                            "last_jf_sync_ts": 0.0,
                            "jf_started": False,
                            "last_pos": 0.0,
                            "duration": 0.0,
                            "eof_reached": False,
                            "last_sub": "",
                            "switch_ts": 0.0,
                            "prev_final_pos": -1.0,
                            "created_ts": time.time(),
                            "connected_once": False,
                        }
                        if hdr_mode:
                            active_hdr_sockets.add(sock_path)

            dead_sockets = []
            for sock_path, st in list(sessions.items()):
                if not os.path.exists(sock_path):
                    if st["connected_once"] or (time.time() - st["created_ts"] > 4.0):
                        dead_sockets.append(sock_path)
                    continue

                try:
                    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
                        s.settimeout(0.6)
                        s.connect(sock_path)
                        st["connected_once"] = True

                        cur_mpv_path = str(query_ipc(s, "path", 4) or "").strip()
                        is_http_stream = cur_mpv_path.startswith(("http://", "https://"))
                        if is_http_stream:
                            resolved = st.get("stream_to_local", {}).get(cur_mpv_path, st["active_file"])
                        else:
                            resolved = resolve_mpv_path(cur_mpv_path, st["base_dir"])

                        if resolved and os.path.exists(resolved) and resolved != st["active_file"]:
                            if not st.get("anonymous_mode") and st["duration"] > 0 and st["last_pos"] > 0:
                                prev_done = st["eof_reached"] or (st["last_pos"] / st["duration"] >= 0.88)
                                update_progress_entry(progress_file, st["active_file"], st["last_pos"], st["duration"], prev_done)
                                if st.get("jellyfin"):
                                    post_jellyfin_playback_event(st["jellyfin"], "stop", st["last_pos"], st["duration"])
                            st["prev_final_pos"] = st["last_pos"]
                            st["active_file"] = resolved
                            st["base_dir"] = os.path.dirname(resolved)
                            st["last_pos"] = 0.0
                            st["duration"] = 0.0
                            st["eof_reached"] = False
                            st["last_sub"] = ""
                            st["switch_ts"] = time.time()
                            # Load Jellyfin metadata & chapters for the newly switched episode from jellyfin_map.json
                            jf_map_file = paths["config_dir"] / "jellyfin_map.json"
                            jf_map = load_json_safe(jf_map_file)
                            cfg_data = load_json_safe(paths["config_file"])
                            next_jf = jf_map.get(resolved, {})
                            if not st.get("anonymous_mode") and next_jf and cfg_data.get("jellyfin_enabled", True) and cfg_data.get("jellyfin_token"):
                                st["jellyfin"] = {
                                    **next_jf,
                                    "api_url": cfg_data.get("jellyfin_url", ""),
                                    "api_token": cfg_data.get("jellyfin_token", ""),
                                    "user_id": cfg_data.get("jellyfin_user_id", ""),
                                    "play_session_id": f"find_{int(time.time())}"
                                }
                                st["chapters_injected"] = False
                                st["jf_started"] = False
                            else:
                                st["jellyfin"] = {}

                            all_prog = load_json_safe(progress_file)
                            saved_next = all_prog.get(resolved, {})
                            loaded_subs = set()
                            if isinstance(saved_next, dict):
                                next_sub = saved_next.get("ext_sub", "")
                                if next_sub and os.path.exists(next_sub):
                                    send_ipc_cmd(s, ["sub-add", next_sub, "select"], 10)
                                    loaded_subs.add(os.path.abspath(next_sub))
                                    st["last_sub"] = next_sub
                            # Auto-attach any local external subtitle matching the switched episode's real filename!
                            for auto_sub in find_matching_external_subs(resolved):
                                if auto_sub not in loaded_subs:
                                    sel_mode = "select" if not loaded_subs else "auto"
                                    send_ipc_cmd(s, ["sub-add", auto_sub, sel_mode], 10)
                                    loaded_subs.add(auto_sub)

                            if isinstance(saved_next, dict) and not saved_next.get("watched", False) and float(saved_next.get("position", 0.0) or 0.0) > 5.0:
                                target_resume = float(saved_next["position"])
                                send_ipc_cmd(s, ["set_property", "time-pos", target_resume], 11)
                                st["expected_seek_pos"] = target_resume
                            else:
                                send_ipc_cmd(s, ["set_property", "time-pos", 0.0], 11)
                                st["expected_seek_pos"] = 0.0
                            continue

                        dur_val = query_ipc(s, "duration", 2)
                        pos_val = query_ipc(s, "time-pos", 1)
                        eof_val = query_ipc(s, "eof-reached", 3)

                        if isinstance(dur_val, (int, float)) and dur_val > 0:
                            st["duration"] = float(dur_val)
                            # Inject Jellyfin chapters into MPV so built-in MPV Skipper scripts work seamlessly!
                            if not st.get("chapters_injected"):
                                st["chapters_injected"] = True
                                jf_chapters = (st.get("jellyfin") or {}).get("chapters") or []
                                if jf_chapters:
                                    existing_ch = query_ipc(s, "chapter-list", 14)
                                    if not existing_ch:
                                        send_ipc_cmd(s, ["set_property", "chapter-list", jf_chapters], 15)
                                # Attach matching local external subtitles before setting any custom title
                                for idx_sub, auto_sub in enumerate(find_matching_external_subs(st["active_file"])):
                                    send_ipc_cmd(s, ["sub-add", auto_sub, "select" if idx_sub == 0 else "auto"], 18)

                            if not st["initial_seek_done"]:
                                st["initial_seek_done"] = True
                                # Persist initial_seek_done to meta file so daemon restarts NEVER re-seek an active mpv session!
                                mf_p = Path(st.get("meta_file", ""))
                                if mf_p.exists():
                                    m_obj = load_json_safe(mf_p)
                                    if m_obj:
                                        m_obj["initial_seek_done"] = True
                                        save_json_atomic(mf_p, m_obj)
                                if st["initial_pos"] > 5.0 and st["initial_pos"] < st["duration"] * 0.95:
                                    send_ipc_cmd(s, ["set_property", "time-pos", st["initial_pos"]], 12)
                                    pos_val = st["initial_pos"]

                        if isinstance(pos_val, (int, float)) and pos_val >= 0:
                            f_pos = float(pos_val)
                            # Prevent stale time-pos from previous episode bleeding into newly switched episode!
                            if st["switch_ts"] > 0:
                                elapsed_sw = time.time() - st["switch_ts"]
                                if elapsed_sw < 4.5 and st["prev_final_pos"] > 15.0 and abs(f_pos - st["prev_final_pos"]) < 12.0:
                                    continue
                                exp_pos = float(st.get("expected_seek_pos", 0.0) or 0.0)
                                if elapsed_sw < 2.5 and exp_pos == 0.0 and f_pos > 30.0:
                                    continue
                            st["last_pos"] = f_pos

                        if eof_val is True:
                            st["eof_reached"] = True

                        ext_sub = detect_external_sub(s, st["base_dir"])
                        if not st.get("anonymous_mode") and ext_sub and ext_sub != st["last_sub"]:
                            st["last_sub"] = ext_sub
                            update_progress_entry(
                                progress_file,
                                st["active_file"],
                                st["last_pos"],
                                st["duration"],
                                None,
                                ext_sub=ext_sub
                            )

                        if not st.get("anonymous_mode") and st["duration"] > 0 and st["last_pos"] > 0:
                            is_done = st["eof_reached"] or (st["last_pos"] / st["duration"] >= 0.90)
                            update_progress_entry(progress_file, st["active_file"], st["last_pos"], st["duration"], is_done)
                            if st.get("jellyfin"):
                                now_t = time.time()
                                if not st.get("jf_started"):
                                    st["jf_started"] = True
                                    st["last_jf_sync_ts"] = now_t
                                    post_jellyfin_playback_event(st["jellyfin"], "start", st["last_pos"], st["duration"])
                                elif (now_t - st.get("last_jf_sync_ts", 0.0)) >= 2.5:
                                    st["last_jf_sync_ts"] = now_t
                                    paused_val = bool(query_ipc(s, "pause", 17))
                                    post_jellyfin_playback_event(st["jellyfin"], "progress", st["last_pos"], st["duration"], paused_val)

                except (ConnectionRefusedError, FileNotFoundError, OSError):
                    if st["connected_once"] or (time.time() - st["created_ts"] > 4.0):
                        dead_sockets.append(sock_path)
                except Exception:
                    pass

            for sp in dead_sockets:
                st = sessions.pop(sp, None)
                if not st:
                    continue
                if not st.get("anonymous_mode") and st["duration"] > 0 and st["last_pos"] > 0:
                    is_done = st["eof_reached"] or (st["last_pos"] / st["duration"] >= 0.90)
                    update_progress_entry(progress_file, st["active_file"], st["last_pos"], st["duration"], is_done)
                    if st.get("jellyfin"):
                        post_jellyfin_playback_event(st["jellyfin"], "stop", st["last_pos"], st["duration"])
                try:
                    if os.path.exists(sp):
                        os.unlink(sp)
                except OSError:
                    pass
                mf_path = st.get("meta_file", "")
                if mf_path and os.path.exists(mf_path):
                    try:
                        os.unlink(mf_path)
                    except OSError:
                        pass
                pl_path = st.get("playlist_file", "")
                if pl_path and os.path.exists(pl_path):
                    try:
                        os.unlink(pl_path)
                    except OSError:
                        pass
                if sp in active_hdr_sockets:
                    active_hdr_sockets.discard(sp)
                    if not active_hdr_sockets:
                        run_toggle_hdr("--off")

            time.sleep(0.75)
    finally:
        try:
            if pid_file.exists():
                pid_file.unlink()
        except OSError:
            pass


if __name__ == "__main__":
    run_daemon_loop()
