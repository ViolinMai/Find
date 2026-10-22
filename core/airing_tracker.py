import os
import re
import time
import json
import shutil
import subprocess
import threading
import requests
from io import BytesIO
from datetime import datetime, timezone
from pathlib import Path
from PIL import Image, ImageDraw, ImageOps


def _save_rounded_airing_poster(raw_bytes: bytes, dest_png: Path):
    try:
        with Image.open(BytesIO(raw_bytes)) as im:
            im_rgba = im.convert("RGBA")
            w, h = im_rgba.size
            if w > 40 and h > 40:
                dx = int(w * 0.03)
                dy = int(h * 0.03)
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
    except Exception:
        pass


class AiringTracker:
    """
    Implements the proven weekly airing tracker logic from MalBot:
    - Fast 100% local cache reads for UI rendering (never blocks Media Hub loading).
    - Background MAL user cache sync every 30 minutes (1800s) with 0.5s pagination sleep.
    - Background AniList airing schedule sync every 6 hours (21600s) with 1.0s sleep between queries.
    - Minute-by-minute local release timer check with automatic +604800s weekly advancement and OS notifications.
    - Persistent poster caching in ~/.cache/find/airing_posters.
    """

    def __init__(self, config_mgr):
        self.config_mgr = config_mgr
        self._lock = threading.RLock()
        self._sync_in_progress = False
        self.session = requests.Session()
        self.session.headers.update({"User-Agent": "FindMediaHub/2.0 (Linux; Wayland)"})

        self.cache_file = self.config_mgr.config_dir / "anime_cache.json"
        self.schedules_file = self.config_mgr.config_dir / "schedules.json"
        self.state_file = self.config_mgr.config_dir / "airing_sync_state.json"
        self.posters_dir = self.config_mgr.cache_dir / "airing_posters"
        self.posters_dir.mkdir(parents=True, exist_ok=True)

    @property
    def mal_username(self) -> str:
        return str(self.config_mgr.get("mal_username", "CriticalweebR18") or "CriticalweebR18").strip()

    @property
    def mal_client_id(self) -> str:
        return str(self.config_mgr.get("mal_client_id", "") or "").strip()

    @property
    def mal_access_token(self) -> str:
        return str(self.config_mgr.get("mal_access_token", "") or "").strip()

    def _load_json(self, path: Path) -> dict:
        if path.exists():
            try:
                with open(path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    if isinstance(data, dict):
                        return data
            except Exception:
                pass
        return {}

    def _save_json(self, path: Path, data: dict):
        self.config_mgr._atomic_write_json(path, data, indent=2)

    def get_cached_poster_path(self, aid: str) -> str:
        """Strictly local check (0ms) — never performs network I/O."""
        if not aid:
            return ""
        dest = self.posters_dir / f"mal_{aid}_rounded.png"
        if dest.exists() and dest.stat().st_size > 200:
            return str(dest)
        return ""

    def ensure_poster_cached(self, aid: str, image_url: str) -> str:
        """Downloads and caches the poster only if not already on disk (used by background worker)."""
        existing = self.get_cached_poster_path(aid)
        if existing:
            return existing
        if not aid or not image_url or not image_url.startswith("http"):
            return ""
        dest = self.posters_dir / f"mal_{aid}_rounded.png"
        try:
            res = self.session.get(image_url, timeout=4.0)
            if res.status_code == 200 and len(res.content) > 200:
                _save_rounded_airing_poster(res.content, dest)
                if dest.exists():
                    return str(dest)
        except Exception:
            pass
        return ""

    def needs_background_sync(self) -> bool:
        state = self._load_json(self.state_file)
        now_ts = time.time()
        last_mal = float(state.get("last_mal_sync", 0.0) or 0.0)
        last_ani = float(state.get("last_anilist_sync", 0.0) or 0.0)
        if not self.cache_file.exists() or not self.schedules_file.exists():
            return True
        if (now_ts - last_mal) >= 1800.0 or (now_ts - last_ani) >= 21600.0:
            return True
        # Also check if any active schedule is missing its cached local poster file
        schedules = self._load_json(self.schedules_file)
        for aid, sdata in schedules.items():
            if isinstance(sdata, dict) and sdata.get("status") == "currently_airing":
                if sdata.get("image") and not self.get_cached_poster_path(str(aid)):
                    return True
        return False

    def sync_mal_cache_sync(self, force: bool = False) -> bool:
        """
        Syncs MAL anime list for CriticalweebR18 every 30 minutes (1800 seconds)
        using the exact pagination and 0.5s rate-limit guard from MalBot.
        """
        state = self._load_json(self.state_file)
        now_ts = time.time()
        last_mal_sync = float(state.get("last_mal_sync", 0.0) or 0.0)
        if not force and (now_ts - last_mal_sync) < 1800.0 and self.cache_file.exists():
            return False

        username = self.mal_username
        token = self.mal_access_token
        client_id = self.mal_client_id

        old_cache = self._load_json(self.cache_file)
        user_items = {}
        active_ids = []
        fetch_succeeded = False

        # Method 1: Official MAL v2 API (if Access Token or Client ID is configured)
        if token or client_id:
            headers = {"Authorization": f"Bearer {token}"} if token else {"X-MAL-CLIENT-ID": client_id}
            offset = 0
            limit = 100
            fetch_failed = False

            while True:
                url = "https://api.myanimelist.net/v2/users/@me/animelist" if token else f"https://api.myanimelist.net/v2/users/{username}/animelist"
                params = {
                    "fields": "list_status,main_picture,status,num_episodes",
                    "limit": limit,
                    "offset": offset,
                    "sort": "list_updated_at"
                }
                try:
                    resp = self.session.get(url, headers=headers, params=params, timeout=8.0)
                    if resp.status_code != 200:
                        fetch_failed = True
                        break
                    data = resp.json()
                    items = data.get("data", [])
                    if not items:
                        break

                    for item in items:
                        node = item.get("node", {})
                        status = item.get("list_status", {})
                        item_id = str(node.get("id", ""))
                        if not item_id:
                            continue

                        current_time = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                        new_status = status.get("status", "")
                        new_score = status.get("score", 0)
                        new_eps = status.get("num_episodes_watched", 0)
                        pic_url = node.get("main_picture", {}).get("large") or node.get("main_picture", {}).get("medium") or ""

                        old_item = old_cache.get(username, {}).get(item_id)
                        if old_item and (
                            old_item.get("status") == new_status and
                            old_item.get("score") == new_score and
                            old_item.get("num_episodes_watched") == new_eps
                        ):
                            item_updated_at = old_item.get("updated_at", current_time)
                        else:
                            item_updated_at = current_time

                        user_items[item_id] = {
                            "title": node.get("title", ""),
                            "status": new_status,
                            "score": new_score,
                            "image": pic_url,
                            "type": "anime",
                            "num_episodes_watched": new_eps,
                            "total_episodes": node.get("num_episodes", 0),
                            "airing_status": node.get("status", ""),
                            "updated_at": item_updated_at
                        }

                        if new_status in ("watching", "plan_to_watch") and node.get("status") == "currently_airing":
                            active_ids.append(item_id)

                    if len(items) < limit:
                        break
                    offset += limit
                    time.sleep(0.5)
                except Exception:
                    fetch_failed = True
                    break

            if not fetch_failed and user_items:
                fetch_succeeded = True

        # Method 2: Public MAL load.json fallback if no token/client_id is set yet
        if not fetch_succeeded:
            offset = 0
            while True:
                pub_url = f"https://myanimelist.net/animelist/{username}/load.json"
                try:
                    resp = self.session.get(pub_url, params={"status": 7, "offset": offset}, timeout=8.0)
                    if resp.status_code != 200:
                        break
                    items = resp.json()
                    if not isinstance(items, list) or not items:
                        break
                    status_map = {1: "watching", 2: "completed", 3: "on_hold", 4: "dropped", 6: "plan_to_watch"}
                    for itm in items:
                        item_id = str(itm.get("anime_id", ""))
                        if not item_id:
                            continue
                        st_code = itm.get("status", 1)
                        new_status = status_map.get(st_code, "watching")
                        air_st = "currently_airing" if itm.get("anime_airing_status") == 1 else "finished_airing"
                        pic_url = str(itm.get("anime_image_path") or "")
                        pic_url = re.sub(r'/r/\d+x\d+/', '/', pic_url).split("?")[0]
                        new_eps = int(itm.get("num_watched_episodes", 0) or 0)
                        user_items[item_id] = {
                            "title": str(itm.get("anime_title") or itm.get("anime_title_eng") or ""),
                            "status": new_status,
                            "score": int(itm.get("score", 0) or 0),
                            "image": pic_url,
                            "type": "anime",
                            "num_episodes_watched": new_eps,
                            "total_episodes": int(itm.get("anime_num_episodes", 0) or 0),
                            "airing_status": air_st,
                            "updated_at": datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                        }
                        if new_status in ("watching", "plan_to_watch") and air_st == "currently_airing":
                            active_ids.append(item_id)
                    if len(items) < 300:
                        break
                    offset += 300
                    time.sleep(0.5)
                except Exception:
                    break
            if user_items:
                fetch_succeeded = True

        # Method 3: Preserve existing anime_cache.json if offline
        if not fetch_succeeded and username in old_cache:
            user_items = old_cache.get(username, {})
            for aid, adata in user_items.items():
                if str(aid).startswith("manga_"):
                    continue
                if adata.get("status") in ("watching", "plan_to_watch"):
                    active_ids.append(str(aid))

        if fetch_succeeded:
            old_cache[username] = user_items
            self._save_json(self.cache_file, old_cache)

        # Ensure posters for active items are cached in the background
        for aid in active_ids:
            img_u = user_items.get(str(aid), {}).get("image", "")
            if img_u and not self.get_cached_poster_path(str(aid)):
                self.ensure_poster_cached(str(aid), img_u)

        state["last_mal_sync"] = now_ts
        if active_ids:
            state["active_airing_ids"] = list(dict.fromkeys(active_ids))
        self._save_json(self.state_file, state)
        return fetch_succeeded

    def sync_anilist_schedules_sync(self, force: bool = False) -> bool:
        """
        Runs AniList GraphQL Schedule Builder every 6 hours (21600s) with 1.0s sleep
        between requests, identical to MalBot's schedule_builder_loop.
        """
        state = self._load_json(self.state_file)
        now_ts = time.time()
        last_ani_sync = float(state.get("last_anilist_sync", 0.0) or 0.0)
        schedules = self._load_json(self.schedules_file)
        cache = self._load_json(self.cache_file)
        user_cache = cache.get(self.mal_username, {})

        active_ids = list(state.get("active_airing_ids", []))
        for aid, adata in user_cache.items():
            if not str(aid).startswith("manga_") and adata.get("status") in ("watching", "plan_to_watch"):
                if adata.get("airing_status", "currently_airing") == "currently_airing" and str(aid) not in active_ids:
                    active_ids.append(str(aid))

        missing_any = any(str(aid) not in schedules for aid in active_ids)
        if not force and not missing_any and (now_ts - last_ani_sync) < 21600.0 and schedules:
            # Even if schedule sync is not due, ensure any missing poster files are downloaded once
            posters_downloaded = False
            for aid, sdata in schedules.items():
                if isinstance(sdata, dict) and sdata.get("status") == "currently_airing":
                    img_u = sdata.get("image") or user_cache.get(str(aid), {}).get("image", "")
                    if img_u and not self.get_cached_poster_path(str(aid)):
                        if self.ensure_poster_cached(str(aid), img_u):
                            posters_downloaded = True
            return posters_downloaded

        if not active_ids:
            return False

        anilist_url = "https://graphql.anilist.co"
        query = """
        query ($id: Int) {
          Media (idMal: $id, type: ANIME) {
            title { romaji }
            coverImage { large }
            status
            episodes
            nextAiringEpisode { airingAt episode }
          }
        }
        """

        updated_any = False
        for aid in active_ids:
            if not str(aid).isdigit():
                continue
            try:
                resp = self.session.post(
                    anilist_url,
                    json={"query": query, "variables": {"id": int(aid)}},
                    timeout=6.0
                )
                if resp.status_code == 200:
                    res = resp.json()
                    media = (res.get("data") or {}).get("Media")
                    if not media:
                        time.sleep(1.0)
                        continue

                    next_data = media.get("nextAiringEpisode")
                    if not next_data:
                        if str(aid) in schedules and schedules[str(aid)].get("status") != "finished":
                            schedules[str(aid)]["status"] = "finished"
                            updated_any = True
                        time.sleep(1.0)
                        continue

                    cover_img = (media.get("coverImage") or {}).get("large") or ""
                    romaji_title = (media.get("title") or {}).get("romaji") or ""

                    schedules[str(aid)] = {
                        "title": romaji_title,
                        "image": cover_img,
                        "next_air_timestamp": int(next_data["airingAt"]),
                        "next_ep": int(next_data["episode"]),
                        "total_eps": media.get("episodes"),
                        "status": "currently_airing",
                        "last_sync": datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                    }
                    updated_any = True

                    if cover_img:
                        self.ensure_poster_cached(str(aid), cover_img)
                elif resp.status_code == 429:
                    time.sleep(5.0)
            except Exception:
                pass
            time.sleep(1.0)

        if updated_any:
            self._save_json(self.schedules_file, schedules)
        state["last_anilist_sync"] = time.time()
        self._save_json(self.state_file, state)
        return updated_any

    def get_notification_config(self) -> dict:
        defaults = self.config_mgr.DEFAULT_CONFIG.get("notification_settings", {})
        raw = self.config_mgr.get("notification_settings", {})
        if isinstance(raw, dict):
            return {**defaults, **raw}
        return dict(defaults)

    def _compute_local_watched_eps(self, aid_str: str, local_ep_overrides: dict, links_map: dict) -> int:
        manual_val = int(local_ep_overrides.get(aid_str, 0) or 0)
        linked_folder = str(links_map.get(aid_str, "") or "")
        folder_max = 0
        if linked_folder and os.path.isdir(linked_folder):
            try:
                for root_d, _, files in os.walk(linked_folder):
                    for fn in files:
                        ext = Path(fn).suffix.lower()
                        if ext in {".mkv", ".mp4", ".webm", ".avi", ".mov", ".m4v"} and not fn.startswith("."):
                            fp = os.path.join(root_d, fn)
                            p_info = self.config_mgr.get_media_progress(fp)
                            if p_info.get("watched", False) or float(p_info.get("progress", 0.0) or 0.0) >= 0.90:
                                m = re.search(r'(?:[Ss]\d+[Ee]|-\s*|[Ee][Pp]?\s*|\[)(\d{1,4})(?:\b|\]|v\d)', Path(fn).stem)
                                if m:
                                    folder_max = max(folder_max, int(m.group(1)))
            except Exception:
                pass
        return max(manual_val, folder_max)

    def dispatch_formatted_notification(
        self,
        aid_str: str,
        title: str,
        ep_num: int,
        watched_eps: int,
        poster_local: str,
        event_type: str,
        event_label: str,
        force_send: bool = False
    ):
        ncfg = self.get_notification_config()
        if not force_send:
            if not ncfg.get("master_enabled", True) or not ncfg.get("os_notifications_enabled", True):
                return
            disabled_ids = {str(x) for x in (ncfg.get("disabled_anime_ids") or [])}
            if str(aid_str) in disabled_ids:
                return

        if not shutil.which("notify-send"):
            return

        behind = max(0, int(ep_num) - int(watched_eps))
        status_str = "Going tight!" if behind <= 0 else f"{behind} ep{'s' if behind > 1 else ''} behind"

        show_ep = bool(ncfg.get("airing_content_show_ep", True))
        show_prog = bool(ncfg.get("airing_content_show_progress", True))
        show_behind = bool(ncfg.get("airing_content_show_behind", True))
        show_poster = bool(ncfg.get("airing_content_show_poster", True))

        title_tpl = str(ncfg.get("airing_title_template") or "🎬 {title} — Episode {ep}")
        body_tpl = str(ncfg.get("airing_body_template") or "{event_label}\nLocal Progress: {watched} eps ({status})")

        ep_str = str(ep_num) if show_ep else ""
        try:
            notif_title = title_tpl.format(
                title=title,
                ep=ep_str,
                watched=watched_eps,
                behind=behind,
                status=status_str,
                event_label=event_label
            ).strip(" —-")
        except Exception:
            notif_title = f"🎬 {title}" + (f" — Ep {ep_num}" if show_ep else "")

        body_lines = [event_label]
        if show_prog and show_behind:
            body_lines.append(f"Local Progress: Watched {watched_eps} eps ({status_str})")
        elif show_prog:
            body_lines.append(f"Local Progress: Watched {watched_eps} eps")
        elif show_behind:
            body_lines.append(f"Status: {status_str}")

        try:
            if body_tpl and "{event_label}" in body_tpl:
                notif_body = body_tpl.format(
                    title=title,
                    ep=ep_num,
                    watched=watched_eps,
                    behind=behind,
                    status=status_str,
                    event_label=event_label
                )
                if not show_prog and not show_behind:
                    notif_body = event_label
            else:
                notif_body = "\n".join(body_lines)
        except Exception:
            notif_body = "\n".join(body_lines)

        urgency = str(ncfg.get("urgency", "normal") or "normal")
        if urgency not in ("low", "normal", "critical"):
            urgency = "normal"
        timeout_ms = int(ncfg.get("display_timeout_ms", 6000) or 6000)

        cmd = [
            "notify-send",
            "-a", "Find Media Hub",
            "-u", urgency,
            "-t", str(max(1500, timeout_ms))
        ]
        if show_poster and poster_local and os.path.exists(poster_local):
            cmd.extend(["-i", poster_local])
        cmd.extend([notif_title, notif_body])
        try:
            subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass

    def check_and_advance_airing_timers_sync(self, send_os_notification: bool = True) -> list:
        """
        Checks:
        1) Pre-airing reminder notifications (e.g., X minutes before episode airs).
        2) On-release airing notifications + automatic +604800s weekly advancement.
        3) Unwatched follow-up reminder notifications (e.g., X hours after episode aired if still unwatched).
        """
        schedules = self._load_json(self.schedules_file)
        if not schedules:
            return []

        cache = self._load_json(self.cache_file)
        user_list = cache.get(self.mal_username, {})
        ignored_ids = set(str(x) for x in (self.config_mgr.get("airing_ignored_ids", []) or []))
        local_ep_overrides = dict(self.config_mgr.get("airing_local_eps", {}) or {})
        links_map = dict(self.config_mgr.get("airing_links", {}) or {})
        state = self._load_json(self.state_file)
        notif_history = dict(state.get("notif_history", {}) or {})

        ncfg = self.get_notification_config()
        pre_enabled = bool(ncfg.get("airing_pre_reminder_enabled", False))
        pre_mins = max(1, int(ncfg.get("airing_pre_reminder_minutes", 30) or 30))
        on_release_enabled = bool(ncfg.get("airing_on_release", True))
        unwatched_enabled = bool(ncfg.get("airing_unwatched_reminder_enabled", True))
        unwatched_hours = max(1, int(ncfg.get("airing_unwatched_reminder_hours", 12) or 12))

        now = datetime.now(timezone.utc).timestamp()
        updated_schedules = False
        updated_state = False
        newly_aired = []

        for aid, data in schedules.items():
            aid_str = str(aid)
            if not isinstance(data, dict) or data.get("status") != "currently_airing":
                continue
            next_ts = float(data.get("next_air_timestamp", 0) or 0)
            if next_ts <= 0:
                continue

            anime_user_data = user_list.get(aid_str, {})
            is_tracked = anime_user_data.get("status", "watching") in ("watching", "plan_to_watch")
            if not is_tracked or aid_str in ignored_ids:
                continue

            title = str(data.get("title") or anime_user_data.get("title") or "Anime")
            upcoming_ep = int(data.get("next_ep", 1) or 1)
            watched_eps = self._compute_local_watched_eps(aid_str, local_ep_overrides, links_map)
            poster_local = self.get_cached_poster_path(aid_str) or self.ensure_poster_cached(aid_str, data.get("image", ""))

            # 1. Pre-Airing Reminder Check (Before episode airs)
            if send_os_notification and pre_enabled and now < next_ts:
                rem_seconds = next_ts - now
                if 0 < rem_seconds <= (pre_mins * 60):
                    pre_key = f"pre_{aid_str}_{upcoming_ep}"
                    if not notif_history.get(pre_key):
                        notif_history[pre_key] = round(now, 1)
                        updated_state = True
                        mins_left = max(1, int(round(rem_seconds / 60.0)))
                        self.dispatch_formatted_notification(
                            aid_str=aid_str,
                            title=title,
                            ep_num=upcoming_ep,
                            watched_eps=watched_eps,
                            poster_local=poster_local,
                            event_type="pre_airing",
                            event_label=f"⏰ Airing in {mins_left} minutes! (Episode {upcoming_ep})"
                        )

            # 2. Episode Release Check & Weekly Advancement
            if now >= next_ts:
                aired_ep = upcoming_ep
                aired_at_ts = next_ts
                total_eps = data.get("total_eps")
                while now >= data["next_air_timestamp"]:
                    if total_eps and data["next_ep"] >= int(total_eps):
                        data["status"] = "finished"
                        break
                    data["next_air_timestamp"] += 604800
                    data["next_ep"] += 1

                data["last_aired_ep"] = aired_ep
                data["last_aired_timestamp"] = aired_at_ts
                updated_schedules = True

                newly_aired.append({
                    "aid": aid_str,
                    "title": title,
                    "episode": aired_ep,
                    "poster": poster_local
                })

                rel_key = f"rel_{aid_str}_{aired_ep}"
                if send_os_notification and on_release_enabled and not notif_history.get(rel_key):
                    notif_history[rel_key] = round(now, 1)
                    updated_state = True
                    self.dispatch_formatted_notification(
                        aid_str=aid_str,
                        title=title,
                        ep_num=aired_ep,
                        watched_eps=watched_eps,
                        poster_local=poster_local,
                        event_type="aired",
                        event_label=f"📡 Episode {aired_ep} Has Just Aired!"
                    )

            # 3. Unwatched Follow-up Reminder Check (If user hasn't watched the latest aired episode after X hours)
            last_aired_ep = int(data.get("last_aired_ep") or max(0, int(data.get("next_ep", 1)) - 1))
            last_aired_ts = float(data.get("last_aired_timestamp") or (float(data.get("next_air_timestamp", 0)) - 604800.0))
            if (
                send_os_notification
                and unwatched_enabled
                and last_aired_ep > 0
                and watched_eps < last_aired_ep
                and last_aired_ts > 0
                and (now - last_aired_ts) >= (unwatched_hours * 3600.0)
                and (now - last_aired_ts) <= 604800.0
            ):
                unw_key = f"unw_{aid_str}_{last_aired_ep}"
                if not notif_history.get(unw_key):
                    notif_history[unw_key] = round(now, 1)
                    updated_state = True
                    hrs_passed = int((now - last_aired_ts) // 3600)
                    self.dispatch_formatted_notification(
                        aid_str=aid_str,
                        title=title,
                        ep_num=last_aired_ep,
                        watched_eps=watched_eps,
                        poster_local=poster_local,
                        event_type="unwatched_reminder",
                        event_label=f"🔔 Reminder: You haven't watched Episode {last_aired_ep} yet ({hrs_passed}h since release)"
                    )

        if updated_schedules:
            self._save_json(self.schedules_file, schedules)
        if updated_state:
            # Keep history compact (last 500 entries)
            if len(notif_history) > 500:
                sorted_k = sorted(notif_history.keys(), key=lambda k: notif_history[k], reverse=True)[:400]
                notif_history = {k: notif_history[k] for k in sorted_k}
            state["notif_history"] = notif_history
            self._save_json(self.state_file, state)
        return newly_aired
