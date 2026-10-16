#!/usr/bin/env python3
import os
import sys
import time
import json
import socket
import shutil
import hashlib
import subprocess
from pathlib import Path
from urllib.parse import unquote, urlparse


def get_paths():
    xdg_config = os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))
    config_dir = Path(xdg_config) / "find"
    config_dir.mkdir(parents=True, exist_ok=True)
    return {
        "config_dir": config_dir,
        "config_file": config_dir / "config.json",
        "progress_file": config_dir / "media_progress.json",
        "pid_file": Path("/tmp") / f"find_media_daemon_{os.getuid()}.pid",
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
    tmp = path.with_suffix(".tmp")
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
        os.replace(tmp, path)
    except Exception:
        pass


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
    while b"\n" not in buf:
        chunk = sock.recv(4096)
        if not chunk:
            break
        buf += chunk
    for line in buf.decode("utf-8", errors="ignore").splitlines():
        try:
            msg = json.loads(line)
            if msg.get("request_id") == req_id and msg.get("error") == "success":
                return msg.get("data")
        except Exception:
            pass
    return None


def send_ipc_cmd(sock: socket.socket, cmd_list: list, req_id: int = 99):
    try:
        payload = json.dumps({"command": cmd_list, "request_id": req_id}) + "\n"
        sock.sendall(payload.encode("utf-8"))
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
    if data.get(file_path) != new_entry:
        data[file_path] = new_entry
        save_json_atomic(progress_file, data)


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

    try:
        while True:
            # Discover active find_mpv_*.sock files in /tmp
            tmp_dir = Path("/tmp")
            meta_files = list(tmp_dir.glob("find_mpv_*.json"))
            for mf in meta_files:
                sock_name = mf.stem + ".sock"
                sock_path = str(tmp_dir / sock_name)
                if sock_path not in sessions:
                    meta = load_json_safe(mf)
                    if meta:
                        init_file = os.path.abspath(meta.get("file_path", ""))
                        hdr_mode = bool(meta.get("hdr_mode", False))
                        init_pos = float(meta.get("initial_pos", 0.0) or 0.0)
                        sessions[sock_path] = {
                            "meta_file": str(mf),
                            "active_file": init_file,
                            "base_dir": os.path.dirname(init_file) if init_file else "",
                            "hdr_mode": hdr_mode,
                            "initial_pos": init_pos,
                            "initial_seek_done": False,
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

                        cur_mpv_path = query_ipc(s, "path", 4)
                        resolved = resolve_mpv_path(cur_mpv_path, st["base_dir"])

                        if resolved and os.path.exists(resolved) and resolved != st["active_file"]:
                            if st["duration"] > 0 and st["last_pos"] > 0:
                                prev_done = st["eof_reached"] or (st["last_pos"] / st["duration"] >= 0.88)
                                update_progress_entry(progress_file, st["active_file"], st["last_pos"], st["duration"], prev_done)
                            st["prev_final_pos"] = st["last_pos"]
                            st["active_file"] = resolved
                            st["base_dir"] = os.path.dirname(resolved)
                            st["last_pos"] = 0.0
                            st["duration"] = 0.0
                            st["eof_reached"] = False
                            st["last_sub"] = ""
                            st["switch_ts"] = time.time()

                            all_prog = load_json_safe(progress_file)
                            saved_next = all_prog.get(resolved, {})
                            if isinstance(saved_next, dict):
                                next_sub = saved_next.get("ext_sub", "")
                                if next_sub and os.path.exists(next_sub):
                                    send_ipc_cmd(s, ["sub-add", next_sub, "select"], 10)
                                    st["last_sub"] = next_sub
                                if not saved_next.get("watched", False) and saved_next.get("position", 0.0) > 5.0:
                                    send_ipc_cmd(s, ["set_property", "time-pos", float(saved_next["position"])], 11)
                                else:
                                    send_ipc_cmd(s, ["set_property", "time-pos", 0.0], 11)
                            continue

                        dur_val = query_ipc(s, "duration", 2)
                        pos_val = query_ipc(s, "time-pos", 1)
                        eof_val = query_ipc(s, "eof-reached", 3)

                        if isinstance(dur_val, (int, float)) and dur_val > 0:
                            st["duration"] = float(dur_val)
                            if not st["initial_seek_done"]:
                                st["initial_seek_done"] = True
                                if st["initial_pos"] > 5.0 and st["initial_pos"] < st["duration"] * 0.95:
                                    send_ipc_cmd(s, ["set_property", "time-pos", st["initial_pos"]], 12)
                                    pos_val = st["initial_pos"]

                        if isinstance(pos_val, (int, float)) and pos_val >= 0:
                            if st["switch_ts"] > 0 and (time.time() - st["switch_ts"]) < 2.0:
                                if st["prev_final_pos"] > 30.0 and abs(float(pos_val) - st["prev_final_pos"]) < 5.0:
                                    continue
                            st["last_pos"] = float(pos_val)

                        if eof_val is True:
                            st["eof_reached"] = True

                        ext_sub = detect_external_sub(s, st["base_dir"])
                        if ext_sub and ext_sub != st["last_sub"]:
                            st["last_sub"] = ext_sub
                            update_progress_entry(
                                progress_file,
                                st["active_file"],
                                st["last_pos"],
                                st["duration"],
                                None,
                                ext_sub=ext_sub
                            )

                        if st["duration"] > 0 and st["last_pos"] > 0:
                            is_done = st["eof_reached"] or (st["last_pos"] / st["duration"] >= 0.90)
                            update_progress_entry(progress_file, st["active_file"], st["last_pos"], st["duration"], is_done)

                except (ConnectionRefusedError, FileNotFoundError, OSError):
                    if st["connected_once"] or (time.time() - st["created_ts"] > 4.0):
                        dead_sockets.append(sock_path)
                except Exception:
                    pass

            for sp in dead_sockets:
                st = sessions.pop(sp, None)
                if not st:
                    continue
                if st["duration"] > 0 and st["last_pos"] > 0:
                    is_done = st["eof_reached"] or (st["last_pos"] / st["duration"] >= 0.90)
                    update_progress_entry(progress_file, st["active_file"], st["last_pos"], st["duration"], is_done)
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
