import os
import re
import time
import json
import uuid
import requests
from io import BytesIO
from pathlib import Path
from PIL import Image, ImageDraw, ImageOps
from PySide6.QtCore import QObject, Signal, QRunnable


class JellyfinSignals(QObject):
    folderMetadataReady = Signal(str, dict)
    itemDetailsReady = Signal(str, dict)
    connectionTested = Signal(bool, str)


FIELDS = (
    "Overview,PrimaryImageAspectRatio,ProductionYear,OriginalTitle,UserData,ParentId,"
    "SeriesId,SeasonId,Path,MediaSources,DateCreated,Chapters,ProviderIds,"
    "CommunityRating,ImageTags"
)


def _save_smooth_rounded_poster(raw_bytes: bytes, dest_png: Path, zoom_crop_pct: float = 0.035):
    with Image.open(BytesIO(raw_bytes)) as im:
        im_rgba = im.convert("RGBA")
        w, h = im_rgba.size
        if zoom_crop_pct > 0 and w > 40 and h > 40:
            dx = int(w * zoom_crop_pct)
            dy = int(h * zoom_crop_pct)
            im_rgba = im_rgba.crop((dx, dy, w - dx, h - dy))
        target_w, target_h = 360, 520
        im_fitted = ImageOps.fit(im_rgba, (target_w, target_h), method=Image.Resampling.LANCZOS)
        scale = 2
        mask = Image.new("L", (target_w * scale, target_h * scale), 0)
        draw = ImageDraw.Draw(mask)
        radius = int(min(target_w, target_h) * 0.085) * scale
        draw.rounded_rectangle(
            (0, 0, target_w * scale - 1, target_h * scale - 1),
            radius=radius,
            fill=255
        )
        mask = mask.resize((target_w, target_h), Image.Resampling.LANCZOS)
        im_fitted.putalpha(mask)
        im_fitted.save(str(dest_png), "PNG", optimize=True)


def post_jellyfin_playback_event(jf_meta: dict, action: str, pos_sec: float, dur_sec: float, is_paused: bool = False):
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
    play_session_id = str(jf_meta.get("play_session_id") or "")
    headers = {
        "Authorization": f'MediaBrowser Client="Find", Device="Linux PC", DeviceId="Find-Linux-PC", Version="2.0.0", Token="{token}"',
        "X-Emby-Token": token
    }

    try:
        if action == "start" or not play_session_id:
            if user_id:
                try:
                    pb_res = requests.post(
                        f"{api_url}/Items/{item_id}/PlaybackInfo?UserId={user_id}",
                        headers=headers,
                        json={"UserId": user_id, "MediaSourceId": media_source_id},
                        timeout=2.5
                    )
                    if pb_res.status_code == 200:
                        pb_json = pb_res.json()
                        if pb_json.get("PlaySessionId"):
                            play_session_id = str(pb_json["PlaySessionId"])
                            jf_meta["play_session_id"] = play_session_id
                        sources = pb_json.get("MediaSources") or []
                        if sources and sources[0] and sources[0].get("Id"):
                            media_source_id = str(sources[0]["Id"])
                            jf_meta["media_source_id"] = media_source_id
                except Exception:
                    pass
            if not play_session_id:
                play_session_id = uuid.uuid4().hex
                jf_meta["play_session_id"] = play_session_id

        session_payload = {
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

        if action == "start":
            requests.post(f"{api_url}/Sessions/Playing", json=session_payload, headers=headers, timeout=2.5)
        elif action == "progress":
            requests.post(f"{api_url}/Sessions/Playing/Progress", json=session_payload, headers=headers, timeout=2.5)
            if user_id:
                requests.post(
                    f"{api_url}/Users/{user_id}/PlayingItems/{item_id}/Progress",
                    params={"PositionTicks": ticks},
                    headers=headers,
                    timeout=2.5
                )
                played_now = bool(dur_sec > 0 and (pos_sec / dur_sec) >= 0.90)
                requests.post(
                    f"{api_url}/Users/{user_id}/Items/{item_id}/UserData",
                    json={
                        "PlaybackPositionTicks": 0 if played_now else ticks,
                        "Played": played_now
                    },
                    headers=headers,
                    timeout=2.5
                )
        elif action == "stop":
            session_payload["EventName"] = "PlaybackStopped"
            requests.post(f"{api_url}/Sessions/Playing/Stopped", json=session_payload, headers=headers, timeout=2.5)
            if user_id:
                played = bool(dur_sec > 0 and (pos_sec / dur_sec) >= 0.90)
                final_ticks = 0 if played else ticks
                requests.post(
                    f"{api_url}/Users/{user_id}/Items/{item_id}/UserData",
                    json={"PlaybackPositionTicks": final_ticks, "Played": played},
                    headers=headers,
                    timeout=2.5
                )
    except Exception:
        pass


class JellyfinBridge:
    def __init__(self, config_mgr):
        self.config_mgr = config_mgr
        self.session = requests.Session()
        adapter = requests.adapters.HTTPAdapter(pool_connections=20, pool_maxsize=20)
        self.session.mount("http://", adapter)
        self.session.mount("https://", adapter)

        self.cache_file = self.config_mgr.config_dir / "jellyfin_map.json"
        self.posters_dir = self.config_mgr.cache_dir / "jf_posters_v2"
        self.posters_dir.mkdir(parents=True, exist_ok=True)
        self._path_map = self._load_cache()
        self._server_online = True
        self._last_fail_ts = 0.0

    def _load_cache(self) -> dict:
        if self.cache_file.exists():
            try:
                with open(self.cache_file, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    if isinstance(data, dict):
                        return data
            except Exception:
                pass
        return {}

    def save_cache(self):
        tmp = self.cache_file.with_suffix(".tmp")
        try:
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(self._path_map, f, indent=2)
            os.replace(tmp, self.cache_file)
        except Exception:
            pass

    @property
    def api_url(self) -> str:
        return str(self.config_mgr.get("jellyfin_url", "") or "").strip().rstrip("/")

    @property
    def api_token(self) -> str:
        return str(self.config_mgr.get("jellyfin_token", "") or "").strip()

    @property
    def user_id(self) -> str:
        return str(self.config_mgr.get("jellyfin_user_id", "") or "").strip()

    @property
    def is_enabled(self) -> bool:
        return bool(self.config_mgr.get("jellyfin_enabled", True)) and bool(self.api_url) and bool(self.api_token)

    @property
    def stream_via_server(self) -> bool:
        return bool(self.config_mgr.get("jellyfin_stream_mode", False))

    def _update_headers(self):
        device_id = self.config_mgr.get("jellyfin_device_id", "Find-Linux-FileManager")
        auth_header = (
            f'MediaBrowser Client="Find", Device="Linux Wayland", '
            f'DeviceId="{device_id}", Version="2.0.0", Token="{self.api_token}"'
        )
        self.session.headers.update({
            "Authorization": auth_header,
            "X-Emby-Token": self.api_token
        })

    def _can_attempt_network(self) -> bool:
        if not self.is_enabled:
            return False
        if not self._server_online and (time.time() - self._last_fail_ts) < 15.0:
            return False
        return True

    def ensure_user_id(self) -> str:
        if self.user_id:
            return self.user_id
        if not self._can_attempt_network():
            return ""
        try:
            self._update_headers()
            res = self.session.get(f"{self.api_url}/Users", timeout=2.5)
            if res.status_code == 200:
                users = res.json()
                if isinstance(users, list) and users:
                    uid = str(users[0].get("Id", ""))
                    if uid:
                        self.config_mgr.set("jellyfin_user_id", uid)
                        self._server_online = True
                        return uid
        except Exception:
            self._server_online = False
            self._last_fail_ts = time.time()
        return ""

    def test_connection_sync(self, url: str, token: str) -> tuple:
        clean_url = url.strip().rstrip("/")
        clean_tok = token.strip()
        if not clean_url or not clean_tok:
            return False, "Server URL and API Token are required."
        try:
            headers = {
                "Authorization": f'MediaBrowser Client="Find", Device="Linux Wayland", DeviceId="Find-Linux", Version="2.0.0", Token="{clean_tok}"',
                "X-Emby-Token": clean_tok
            }
            res = self.session.get(f"{clean_url}/Users", headers=headers, timeout=3.5)
            res.raise_for_status()
            users = res.json()
            if isinstance(users, list) and users:
                first_user = users[0]
                uid = str(first_user.get("Id", ""))
                uname = str(first_user.get("Name", "User"))
                self.config_mgr.set("jellyfin_url", clean_url)
                self.config_mgr.set("jellyfin_token", clean_tok)
                self.config_mgr.set("jellyfin_user_id", uid)
                self._server_online = True
                return True, f"✔ Connected to Jellyfin as '{uname}'"
            return False, "Connected, but no users found on server."
        except Exception as e:
            return False, f"⚠️ Connection failed: {e}"

    def get_cached_item(self, file_path: str) -> dict:
        norm = os.path.abspath(file_path) if file_path else ""
        entry = self._path_map.get(norm, {})
        if entry and entry.get("poster") and not os.path.exists(entry["poster"]):
            entry["poster"] = ""
        return entry

    def update_local_cached_progress(self, file_path: str, pos_sec: float, dur_sec: float, watched: bool):
        norm = os.path.abspath(file_path) if file_path else ""
        if norm and norm in self._path_map:
            entry = self._path_map[norm]
            entry["position"] = round(float(pos_sec), 2)
            if dur_sec > 0:
                entry["duration"] = round(float(dur_sec), 2)
                entry["progress"] = 1.0 if watched else round(min(1.0, max(0.0, pos_sec / dur_sec)), 4)
            entry["watched"] = bool(watched)
            entry["server_updated_at"] = round(time.time(), 2)
            self.save_cache()

    @staticmethod
    def _parse_iso_timestamp(iso_str: str) -> float:
        if not iso_str:
            return 0.0
        try:
            import datetime
            s = str(iso_str).strip().replace("Z", "+00:00")
            if "." in s and "+" in s:
                main_p, tz_p = s.split("+", 1)
                sec_p, frac_p = main_p.split(".", 1)
                s = f"{sec_p}.{frac_p[:6]}+{tz_p}"
            return datetime.datetime.fromisoformat(s).timestamp()
        except Exception:
            return 0.0

    @staticmethod
    def is_season_folder_name(name: str) -> bool:
        n_lower = name.lower().strip()
        season_patterns = [
            r'^season\s*\d+', r'^s\s*\d+', r'^part\s*\d+', r'^cour\s*\d+',
            r'^\d+(?:st|nd|rd|th)\s+season', r'^specials?', r'^ova', r'^movies?'
        ]
        return any(re.search(pat, n_lower) for pat in season_patterns)

    def _ensure_poster_cached(self, item_id: str, fallback_series_id: str = "", is_poster_target: bool = True) -> str:
        if not item_id or not is_poster_target:
            return ""
        dest_file = self.posters_dir / f"{item_id}_rounded.png"
        if dest_file.exists() and dest_file.stat().st_size > 200:
            return str(dest_file)
        if not self._can_attempt_network():
            return ""

        candidate_ids = [item_id]
        if fallback_series_id and fallback_series_id != item_id:
            candidate_ids.append(fallback_series_id)

        for cid in candidate_ids:
            try:
                url = f"{self.api_url}/Items/{cid}/Images/Primary?maxWidth=560&quality=92"
                res = self.session.get(url, timeout=2.5)
                if res.status_code == 200 and len(res.content) > 200:
                    _save_smooth_rounded_poster(res.content, dest_file)
                    if dest_file.exists():
                        return str(dest_file)
            except Exception:
                pass
        return ""

    def _extract_item_metadata(self, itm: dict, fetch_poster: bool = True) -> dict:
        iid = str(itm.get("Id", ""))
        item_type = str(itm.get("Type") or "")
        ud = itm.get("UserData") or {}
        ticks = int(ud.get("PlaybackPositionTicks", 0) or 0)
        last_played_ts = self._parse_iso_timestamp(str(ud.get("LastPlayedDate") or ""))

        rt_ticks = int(itm.get("RunTimeTicks", 0) or 0)
        if rt_ticks <= 0 and itm.get("MediaSources"):
            rt_ticks = int(itm["MediaSources"][0].get("RunTimeTicks", 0) or 0)

        pos_sec = round(ticks / 10_000_000.0, 2) if ticks > 0 else 0.0
        dur_sec = round(rt_ticks / 10_000_000.0, 2) if rt_ticks > 0 else 0.0
        played = bool(ud.get("Played", False))
        pct = float(ud.get("PlayedPercentage", 0.0) or 0.0) / 100.0
        if dur_sec > 0 and pos_sec > 0 and pct <= 0.0:
            pct = min(1.0, pos_sec / dur_sec)
        if played:
            pct = 1.0

        raw_chapters = itm.get("Chapters") or []
        chapters = []
        for idx, ch in enumerate(raw_chapters):
            if isinstance(ch, dict):
                st_ticks = int(ch.get("StartPositionTicks", 0) or 0)
                chapters.append({
                    "title": str(ch.get("Name") or f"Chapter {idx + 1}"),
                    "time": round(st_ticks / 10_000_000.0, 3)
                })

        media_source_id = iid
        if itm.get("MediaSources") and isinstance(itm["MediaSources"], list):
            media_source_id = str(itm["MediaSources"][0].get("Id") or iid)

        year_val = itm.get("ProductionYear")
        raw_title = str(itm.get("Name") or "")
        if item_type == "Movie" and year_val and str(year_val) not in raw_title:
            display_title = f"{raw_title} ({year_val})"
        else:
            display_title = raw_title

        should_download_poster = fetch_poster and item_type in ("Movie", "Series", "Season", "BoxSet")
        series_id = str(itm.get("SeriesId") or itm.get("ParentId") or "")
        poster_path = self._ensure_poster_cached(iid, fallback_series_id=series_id, is_poster_target=should_download_poster)

        return {
            "item_id": iid,
            "item_type": item_type,
            "media_source_id": media_source_id,
            "title": display_title,
            "raw_title": raw_title,
            "original_title": str(itm.get("OriginalTitle") or ""),
            "year": year_val,
            "series_name": str(itm.get("SeriesName") or ""),
            "overview": str(itm.get("Overview") or ""),
            "rating": round(float(itm["CommunityRating"]), 1) if itm.get("CommunityRating") else None,
            "poster": poster_path,
            "index_number": itm.get("IndexNumber"),
            "season_number": itm.get("ParentIndexNumber"),
            "position": pos_sec,
            "duration": dur_sec,
            "progress": round(pct, 4),
            "watched": played,
            "server_updated_at": round(last_played_ts, 2),
            "chapters": chapters,
            "updated_ts": time.time()
        }

    def _match_subfolder_to_show(self, sub_abs: str, sub_name: str, all_shows: list, shows_by_path: dict, shows_by_key: dict, uid: str):
        # Guard: If this is explicitly a season folder (e.g. "Season 1", "S2"), do not search as a separate anime show
        if self.is_season_folder_name(sub_name):
            parent_dir = os.path.dirname(sub_abs)
            return self._match_subfolder_to_show(parent_dir, Path(parent_dir).name, all_shows, shows_by_path, shows_by_key, uid)

        if sub_abs in shows_by_path:
            return shows_by_path[sub_abs]

        sub_norm_slash = sub_abs.rstrip("/") + "/"
        sub_basename_lower = Path(sub_abs).name.lower()
        for sp, sh in shows_by_path.items():
            if sp.startswith(sub_norm_slash) or sub_abs.startswith(sp.rstrip("/") + "/"):
                return sh
            if Path(sp).name.lower() == sub_basename_lower:
                return sh

        full_key = self._normalize_match_key(sub_name, strip_season=False)
        base_key = self._normalize_match_key(sub_name, strip_season=True)

        if full_key and full_key in shows_by_key:
            return shows_by_key[full_key]
        if base_key and base_key in shows_by_key:
            return shows_by_key[base_key]

        best_match = None
        best_score = 0.0
        query_tokens = set(base_key.split()) if base_key else set()

        for cand_key, sh in shows_by_key.items():
            if not cand_key:
                continue
            if len(base_key) >= 4 and (base_key in cand_key or cand_key in base_key):
                score = min(len(base_key), len(cand_key)) / max(len(base_key), len(cand_key))
                if score > best_score and score >= 0.40:
                    best_score = score
                    best_match = sh
            if query_tokens:
                cand_tokens = set(cand_key.split())
                if cand_tokens:
                    inter = len(query_tokens & cand_tokens)
                    union = len(query_tokens | cand_tokens)
                    t_score = inter / union
                    if t_score > best_score and t_score >= 0.45:
                        best_score = t_score
                        best_match = sh

        if best_match is not None:
            return best_match

        for search_q in (self._clean_search_title(sub_name, strip_season=True), self._clean_search_title(sub_name, strip_season=False)):
            if not search_q or len(search_q) < 2:
                continue
            try:
                res = self.session.get(
                    f"{self.api_url}/Users/{uid}/Items",
                    params={
                        "SearchTerm": search_q,
                        "IncludeItemTypes": "Series,Movie",
                        "Recursive": "true",
                        "Fields": FIELDS,
                        "Limit": 5
                    },
                    timeout=2.0
                )
                if res.status_code == 200:
                    items = res.json().get("Items", [])
                    if items:
                        return items[0]
            except Exception:
                pass

        return None

    def sync_directory_items_sync(self, folder_path: str, local_entries: list) -> dict:
        if not self._can_attempt_network():
            return {}
        uid = self.ensure_user_id()
        if not uid:
            return {}

        folder_abs = os.path.abspath(folder_path)
        folder_name = Path(folder_abs).name
        local_video_files = {
            os.path.abspath(e["path"]): e["name"]
            for e in local_entries
            if not e.get("is_dir")
        }
        local_subfolders = {
            os.path.abspath(e["path"]): e["name"]
            for e in local_entries
            if e.get("is_dir")
        }
        if not local_video_files and not local_subfolders:
            return {}

        self._update_headers()
        matched_results = {}

        try:
            if local_subfolders:
                sr_res = self.session.get(
                    f"{self.api_url}/Users/{uid}/Items",
                    params={
                        "IncludeItemTypes": "Series,Season,Movie",
                        "Recursive": "true",
                        "Fields": FIELDS,
                        "Limit": 2000
                    },
                    timeout=5.0
                )
                if sr_res.status_code == 200:
                    all_shows = sr_res.json().get("Items", [])
                    shows_by_path = {}
                    shows_by_key = {}

                    for sh in all_shows:
                        sp = str(sh.get("Path") or "").strip()
                        if sp:
                            shows_by_path[os.path.abspath(sp)] = sh

                        for raw_field in (sh.get("Name"), sh.get("OriginalTitle")):
                            if not raw_field:
                                continue
                            k_full = self._normalize_match_key(str(raw_field), strip_season=False)
                            k_base = self._normalize_match_key(str(raw_field), strip_season=True)
                            if k_full and (k_full not in shows_by_key or sh.get("Type") == "Series"):
                                shows_by_key[k_full] = sh
                            if k_base and (k_base not in shows_by_key or sh.get("Type") == "Series"):
                                shows_by_key[k_base] = sh

                    for sub_abs, sub_name in local_subfolders.items():
                        cached_existing = self.get_cached_item(sub_abs)
                        if cached_existing and cached_existing.get("poster") and os.path.exists(cached_existing["poster"]):
                            matched_results[sub_abs] = cached_existing
                            continue

                        matched_sh = self._match_subfolder_to_show(
                            sub_abs, sub_name, all_shows, shows_by_path, shows_by_key, uid
                        )
                        if matched_sh:
                            sub_meta = self._extract_item_metadata(matched_sh, fetch_poster=True)
                            self._path_map[sub_abs] = sub_meta
                            matched_results[sub_abs] = sub_meta

            if local_video_files:
                is_movie_folder = any(e.get("is_movie_item") for e in local_entries if not e.get("is_dir"))
                server_items = []

                if is_movie_folder:
                    m_res = self.session.get(
                        f"{self.api_url}/Users/{uid}/Items",
                        params={
                            "IncludeItemTypes": "Movie",
                            "Recursive": "true",
                            "Fields": FIELDS,
                            "Limit": 1500
                        },
                        timeout=5.0
                    )
                    if m_res.status_code == 200:
                        server_items.extend(m_res.json().get("Items", []))
                else:
                    search_terms = [
                        self._clean_search_title(folder_name, strip_season=True),
                        self._clean_search_title(folder_name, strip_season=False)
                    ]
                    parent_name = Path(folder_abs).parent.name
                    if folder_name.lower().startswith(("season", "s0", "s1", "s2", "specials", "ova", "part")) and parent_name:
                        search_terms.insert(0, self._clean_search_title(parent_name, strip_season=True))

                    seen_terms = set()
                    for clean_term in search_terms:
                        if not clean_term or clean_term in seen_terms:
                            continue
                        seen_terms.add(clean_term)
                        s_res = self.session.get(
                            f"{self.api_url}/Users/{uid}/Items",
                            params={
                                "SearchTerm": clean_term,
                                "IncludeItemTypes": "Series,Movie",
                                "Recursive": "true",
                                "Fields": FIELDS,
                                "Limit": 20
                            },
                            timeout=3.5
                        )
                        if s_res.status_code == 200:
                            candidates = s_res.json().get("Items", [])
                            for cand in candidates:
                                c_path = str(cand.get("Path") or "")
                                c_type = cand.get("Type")
                                if c_path and os.path.abspath(c_path) == folder_abs:
                                    folder_meta = self._extract_item_metadata(cand, fetch_poster=True)
                                    self._path_map[folder_abs] = folder_meta
                                    matched_results[folder_abs] = folder_meta

                                if c_type == "Series":
                                    ep_res = self.session.get(
                                        f"{self.api_url}/Shows/{cand['Id']}/Episodes",
                                        params={"UserId": uid, "Fields": FIELDS},
                                        timeout=4.0
                                    )
                                    if ep_res.status_code == 200:
                                        server_items.extend(ep_res.json().get("Items", []))
                                elif c_type == "Movie":
                                    server_items.append(cand)
                        if server_items:
                            break

                    if not server_items and search_terms:
                        res = self.session.get(
                            f"{self.api_url}/Users/{uid}/Items",
                            params={
                                "SearchTerm": search_terms[0],
                                "IncludeItemTypes": "Episode,Movie",
                                "Recursive": "true",
                                "Fields": FIELDS,
                                "Limit": 150
                            },
                            timeout=3.5
                        )
                        if res.status_code == 200:
                            server_items.extend(res.json().get("Items", []))

                by_exact_path = {}
                by_filename = {}
                by_clean_title = {}
                for itm in server_items:
                    srv_p = str(itm.get("Path") or "").strip()
                    if srv_p:
                        norm_srv = os.path.abspath(srv_p)
                        by_exact_path[norm_srv] = itm
                        by_filename[Path(norm_srv).name] = itm
                    for t_field in (itm.get("Name"), itm.get("OriginalTitle")):
                        if t_field:
                            ck = self._normalize_match_key(str(t_field), strip_season=True)
                            if ck:
                                by_clean_title[ck] = itm

                for loc_abs, loc_name in local_video_files.items():
                    matched_itm = by_exact_path.get(loc_abs) or by_filename.get(loc_name)
                    if not matched_itm and is_movie_folder:
                        stem_key = self._normalize_match_key(Path(loc_name).stem, strip_season=True)
                        matched_itm = by_clean_title.get(stem_key)

                    if matched_itm:
                        meta = self._extract_item_metadata(matched_itm, fetch_poster=is_movie_folder)
                        local_prog = self.config_mgr.get_media_progress(loc_abs)
                        local_pos = float(local_prog.get("position", 0.0) or 0.0)
                        local_dur = float(local_prog.get("duration", 0.0) or 0.0)
                        local_watched = bool(local_prog.get("watched", False))
                        local_ts = float(local_prog.get("updated_at", 0.0) or 0.0)
                        srv_ts = float(meta.get("server_updated_at", 0.0) or 0.0)
                        has_local_record = (local_ts > 0.0 or local_pos > 0.0 or local_watched)

                        # Newest-Wins bidirectional safety reconciliation
                        if has_local_record and local_ts > (srv_ts + 2.0):
                            eff_dur = local_dur if local_dur > 0 else (meta["duration"] if meta["duration"] > 0 else 100.0)
                            meta["position"] = local_pos
                            meta["duration"] = eff_dur
                            meta["watched"] = local_watched
                            meta["progress"] = 1.0 if local_watched else round(min(1.0, max(0.0, local_pos / eff_dur)), 4)
                            self._push_local_state_to_server_sync(uid, meta["item_id"], local_pos, eff_dur, local_watched)
                        elif srv_ts > (local_ts + 2.0):
                            eff_dur = meta["duration"] if meta["duration"] > 0 else (local_dur if local_dur > 0 else 100.0)
                            self.config_mgr.set_media_progress(
                                loc_abs,
                                meta["position"],
                                eff_dur,
                                watched=meta["watched"],
                                updated_at=srv_ts
                            )
                        else:
                            if local_watched != meta["watched"]:
                                if local_ts >= srv_ts and local_ts > 0:
                                    meta["watched"] = local_watched
                                    meta["progress"] = 1.0 if local_watched else 0.0
                                else:
                                    self.config_mgr.set_media_progress(
                                        loc_abs,
                                        meta["position"],
                                        meta["duration"] if meta["duration"] > 0 else 100.0,
                                        watched=meta["watched"],
                                        updated_at=srv_ts if srv_ts > 0 else time.time()
                                    )
                            elif not meta["watched"] and abs(local_pos - meta["position"]) > 3.0:
                                if local_pos > meta["position"]:
                                    eff_dur = local_dur if local_dur > 0 else (meta["duration"] if meta["duration"] > 0 else 100.0)
                                    meta["position"] = local_pos
                                    meta["duration"] = eff_dur
                                    meta["progress"] = round(min(1.0, local_pos / eff_dur), 4)
                                    self._push_local_state_to_server_sync(uid, meta["item_id"], local_pos, eff_dur, False)
                                else:
                                    eff_dur = meta["duration"] if meta["duration"] > 0 else (local_dur if local_dur > 0 else 100.0)
                                    self.config_mgr.set_media_progress(
                                        loc_abs,
                                        meta["position"],
                                        eff_dur,
                                        watched=False,
                                        updated_at=srv_ts if srv_ts > 0 else time.time()
                                    )

                        self._path_map[loc_abs] = meta
                        matched_results[loc_abs] = meta

            if matched_results:
                self.save_cache()
            self._server_online = True
        except Exception:
            self._server_online = False
            self._last_fail_ts = time.time()

        return matched_results

    def resolve_item_for_playback_sync(self, file_path: str) -> dict:
        norm_p = os.path.abspath(file_path)
        cached = self._path_map.get(norm_p, {})

        if self._can_attempt_network():
            uid = self.ensure_user_id()
            if uid:
                self._update_headers()
                try:
                    item_id = cached.get("item_id", "")
                    if item_id:
                        res = self.session.get(
                            f"{self.api_url}/Users/{uid}/Items/{item_id}",
                            params={"Fields": FIELDS},
                            timeout=2.0
                        )
                        if res.status_code == 200:
                            cached = self._extract_item_metadata(res.json(), fetch_poster=False)
                            self._path_map[norm_p] = cached
                            self.save_cache()
                    else:
                        parent_dir = os.path.dirname(norm_p)
                        self.sync_directory_items_sync(parent_dir, [{"path": norm_p, "name": Path(norm_p).name, "is_dir": False}])
                        cached = self._path_map.get(norm_p, {})
                except Exception:
                    self._server_online = False
                    self._last_fail_ts = time.time()

        if not cached or not cached.get("item_id"):
            return {}

        item_id = cached["item_id"]
        media_source_id = str(cached.get("media_source_id") or item_id)
        play_session_id = ""

        if self._can_attempt_network() and self.user_id:
            try:
                self._update_headers()
                pb_res = self.session.post(
                    f"{self.api_url}/Items/{item_id}/PlaybackInfo?UserId={self.user_id}",
                    json={"UserId": self.user_id, "MediaSourceId": media_source_id},
                    timeout=2.5
                )
                if pb_res.status_code == 200:
                    pb_json = pb_res.json()
                    play_session_id = str(pb_json.get("PlaySessionId") or "")
                    sources = pb_json.get("MediaSources") or []
                    if sources and sources[0] and sources[0].get("Id"):
                        media_source_id = str(sources[0]["Id"])
            except Exception:
                pass

        if not play_session_id:
            play_session_id = uuid.uuid4().hex

        stream_url = ""
        if self.is_enabled and self.stream_via_server and self._server_online:
            stream_url = (
                f"{self.api_url}/Videos/{item_id}/stream"
                f"?static=true&MediaSourceId={media_source_id}"
                f"&PlaySessionId={play_session_id}&api_key={self.api_token}"
            )

        return {
            **cached,
            "media_source_id": media_source_id,
            "stream_url": stream_url,
            "api_url": self.api_url,
            "api_token": self.api_token,
            "user_id": self.user_id,
            "play_session_id": play_session_id
        }

    def _push_local_state_to_server_sync(self, uid: str, item_id: str, pos_sec: float, dur_sec: float, watched: bool):
        if not uid or not item_id or not self._can_attempt_network():
            return
        try:
            self._update_headers()
            ticks = 0 if watched else int(max(0.0, float(pos_sec)) * 10_000_000)
            self.session.post(
                f"{self.api_url}/Users/{uid}/Items/{item_id}/UserData",
                json={"PlaybackPositionTicks": ticks, "Played": bool(watched)},
                timeout=2.5
            )
        except Exception:
            pass

    def mark_watched_async(self, file_path: str, watched: bool, thread_pool):
        if not self.is_enabled:
            return
        norm_p = os.path.abspath(file_path)

        def _worker():
            try:
                uid = self.ensure_user_id()
                if not uid:
                    return
                meta = self.get_cached_item(norm_p)
                if not meta or not meta.get("item_id"):
                    parent_dir = os.path.dirname(norm_p)
                    self.sync_directory_items_sync(parent_dir, [{"path": norm_p, "name": Path(norm_p).name, "is_dir": False}])
                    meta = self.get_cached_item(norm_p)
                item_id = (meta or {}).get("item_id", "")
                if not item_id:
                    return

                self._update_headers()
                played_url = f"{self.api_url}/Users/{uid}/PlayedItems/{item_id}"
                userdata_url = f"{self.api_url}/Users/{uid}/Items/{item_id}/UserData"

                if watched:
                    self.session.post(played_url, timeout=3.0)
                    self.session.post(
                        userdata_url,
                        json={"PlaybackPositionTicks": 0, "Played": True},
                        timeout=3.0
                    )
                else:
                    self.session.delete(played_url, timeout=3.0)
                    self.session.post(
                        userdata_url,
                        json={"PlaybackPositionTicks": 0, "Played": False},
                        timeout=3.0
                    )
                    self.session.delete(
                        f"{self.api_url}/Users/{uid}/PlayingItems/{item_id}/Progress",
                        timeout=2.5
                    )

                now_ts = time.time()
                if norm_p in self._path_map:
                    self._path_map[norm_p]["watched"] = bool(watched)
                    self._path_map[norm_p]["position"] = 0.0
                    self._path_map[norm_p]["progress"] = 1.0 if watched else 0.0
                    self._path_map[norm_p]["server_updated_at"] = round(now_ts, 2)
                    self.save_cache()
            except Exception:
                pass

        thread_pool.start(_worker)

    def build_playlist_for_folder(self, clicked_file: str, ordered_local_files: list, base_id: str = "") -> tuple:
        clicked_abs = os.path.abspath(clicked_file)
        if not ordered_local_files:
            ordered_local_files = [clicked_abs]
        try:
            start_idx = ordered_local_files.index(clicked_abs)
        except ValueError:
            ordered_local_files.insert(0, clicked_abs)
            start_idx = 0

        stream_to_local = {}
        m3u_lines = ["#EXTM3U"]
        use_http_stream = bool(self.is_enabled and self.stream_via_server and self._server_online)

        for lp in ordered_local_files:
            c_meta = self._path_map.get(lp, {})
            iid = c_meta.get("item_id", "")
            srv_title = str(c_meta.get("title") or "").strip()
            ep_idx = c_meta.get("index_number")
            is_movie = (c_meta.get("item_type") == "Movie")

            if srv_title:
                if ep_idx is not None and not is_movie:
                    display_title = f"{int(ep_idx):02d} - {srv_title}"
                else:
                    display_title = srv_title
            else:
                display_title = Path(lp).stem

            clean_ext_title = display_title.replace("\n", " ").replace("\r", " ")
            dur_int = int(c_meta.get("duration", -1) or -1) if c_meta.get("duration", 0) > 0 else -1
            m3u_lines.append(f"#EXTINF:{dur_int},{clean_ext_title}")

            if use_http_stream and iid:
                ms_id = c_meta.get("media_source_id", iid)
                s_url = (
                    f"{self.api_url}/Videos/{iid}/stream"
                    f"?static=true&MediaSourceId={ms_id}&api_key={self.api_token}"
                )
                m3u_lines.append(s_url)
                stream_to_local[s_url] = lp
            else:
                m3u_lines.append(lp)

        m3u_name = f"{base_id or ('find_pl_' + str(int(time.time())))}.m3u8"
        m3u_path = os.path.join("/tmp", m3u_name)
        try:
            with open(m3u_path, "w", encoding="utf-8") as f:
                f.write("\n".join(m3u_lines) + "\n")
            return m3u_path, start_idx, stream_to_local
        except Exception:
            return clicked_abs, 0, stream_to_local

    @staticmethod
    def _clean_search_title(raw_name: str, strip_season: bool = True) -> str:
        s = re.sub(r'\[[^\]]*\]|\([^\)]*\)', ' ', raw_name)
        s = re.sub(r'[\._\-]+', ' ', s)
        s = re.sub(
            r'\b(?:1080p|720p|2160p|4K|BD|BDRip|WEB|WEBRip|FLAC|AAC|HEVC|AVC|x265|x264|10bit|Dual\s*Audio)\b',
            ' ',
            s,
            flags=re.I
        )
        if strip_season:
            s = re.sub(
                r'\b(?:Season\s*\d+|S\d+|Part\s*\d+|Cour\s*\d+|\d+(?:st|nd|rd|th)\s+Season)\b',
                ' ',
                s,
                flags=re.I
            )
            s = re.sub(r'\s+\d{1,2}$', '', s.strip())
        return re.sub(r'\s+', ' ', s).strip()

    @classmethod
    def _normalize_match_key(cls, raw_name: str, strip_season: bool = True) -> str:
        cleaned = cls._clean_search_title(raw_name, strip_season=strip_season).lower()
        cleaned = re.sub(r'[^a-z0-9\u0600-\u06ff\u3040-\u30ff\u4e00-\u9fff\s]', ' ', cleaned)
        return re.sub(r'\s+', ' ', cleaned).strip()


class JellyfinFolderSyncTask(QRunnable):
    def __init__(self, bridge: JellyfinBridge, folder_path: str, entries: list, signals: JellyfinSignals):
        super().__init__()
        self.bridge = bridge
        self.folder_path = folder_path
        self.entries = entries
        self.signals = signals

    def run(self):
        results = self.bridge.sync_directory_items_sync(self.folder_path, self.entries)
        if results:
            self.signals.folderMetadataReady.emit(self.folder_path, results)
