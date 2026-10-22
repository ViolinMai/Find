from PySide6.QtCore import Qt, QAbstractListModel, QModelIndex, QObject


class FileListModel(QAbstractListModel):
    NameRole = Qt.ItemDataRole.UserRole + 1
    PathRole = Qt.ItemDataRole.UserRole + 2
    IsDirRole = Qt.ItemDataRole.UserRole + 3
    SizeRole = Qt.ItemDataRole.UserRole + 4
    ModifiedRole = Qt.ItemDataRole.UserRole + 5
    CreatedRole = Qt.ItemDataRole.UserRole + 6
    IconRole = Qt.ItemDataRole.UserRole + 7
    TypeRole = Qt.ItemDataRole.UserRole + 8
    RawSizeRole = Qt.ItemDataRole.UserRole + 9
    RawModRole = Qt.ItemDataRole.UserRole + 10
    RawCreatedRole = Qt.ItemDataRole.UserRole + 11
    ThumbRole = Qt.ItemDataRole.UserRole + 12
    FolderPreviewsRole = Qt.ItemDataRole.UserRole + 13
    EpisodeNumRole = Qt.ItemDataRole.UserRole + 14
    ProgressRole = Qt.ItemDataRole.UserRole + 15
    IsWatchedRole = Qt.ItemDataRole.UserRole + 16
    IsNewRole = Qt.ItemDataRole.UserRole + 17
    IsMovieItemRole = Qt.ItemDataRole.UserRole + 18
    IsHdrRole = Qt.ItemDataRole.UserRole + 19
    EpisodeTitleRole = Qt.ItemDataRole.UserRole + 20
    OverviewRole = Qt.ItemDataRole.UserRole + 21
    RatingRole = Qt.ItemDataRole.UserRole + 22
    PosterRole = Qt.ItemDataRole.UserRole + 23
    SizeRatioRole = Qt.ItemDataRole.UserRole + 24
    PercentStrRole = Qt.ItemDataRole.UserRole + 25

    FIELD_TO_ROLE = {
        "name": NameRole,
        "path": PathRole,
        "is_dir": IsDirRole,
        "size": SizeRole,
        "modified": ModifiedRole,
        "created": CreatedRole,
        "icon": IconRole,
        "type": TypeRole,
        "raw_size": RawSizeRole,
        "raw_mod": RawModRole,
        "raw_created": RawCreatedRole,
        "thumb": ThumbRole,
        "folder_previews": FolderPreviewsRole,
        "episode_num": EpisodeNumRole,
        "progress": ProgressRole,
        "is_watched": IsWatchedRole,
        "is_new": IsNewRole,
        "is_movie_item": IsMovieItemRole,
        "is_hdr": IsHdrRole,
        "episode_title": EpisodeTitleRole,
        "overview": OverviewRole,
        "rating": RatingRole,
        "poster": PosterRole,
        "size_ratio": SizeRatioRole,
        "percent_str": PercentStrRole,
    }

    def __init__(self, parent=None):
        super().__init__(parent)
        self._entries = []
        self._path_to_row = {}
        self._current_context_key = ""

    def rowCount(self, parent=QModelIndex()):
        return len(self._entries)

    def data(self, index, role=Qt.ItemDataRole.DisplayRole):
        if not index.isValid() or not (0 <= index.row() < len(self._entries)):
            return None

        entry = self._entries[index.row()]
        if role == self.NameRole:
            return entry.get("name", "")
        elif role == self.PathRole:
            return entry.get("path", "")
        elif role == self.IsDirRole:
            return bool(entry.get("is_dir", False))
        elif role == self.SizeRole:
            return entry.get("size", "")
        elif role == self.ModifiedRole:
            return entry.get("modified", "")
        elif role == self.CreatedRole:
            return entry.get("created", "")
        elif role == self.IconRole:
            return entry.get("icon", "")
        elif role == self.TypeRole:
            return entry.get("type", "")
        elif role == self.RawSizeRole:
            return entry.get("raw_size", 0)
        elif role == self.RawModRole:
            return entry.get("raw_mod", 0)
        elif role == self.RawCreatedRole:
            return entry.get("raw_created", 0)
        elif role == self.ThumbRole:
            return entry.get("thumb", "")
        elif role == self.FolderPreviewsRole:
            return entry.get("folder_previews", [])
        elif role == self.EpisodeNumRole:
            return entry.get("episode_num", "")
        elif role == self.ProgressRole:
            return float(entry.get("progress", 0.0))
        elif role == self.IsWatchedRole:
            return bool(entry.get("is_watched", False))
        elif role == self.IsNewRole:
            return bool(entry.get("is_new", False))
        elif role == self.IsMovieItemRole:
            return bool(entry.get("is_movie_item", False))
        elif role == self.IsHdrRole:
            return bool(entry.get("is_hdr", False))
        elif role == self.EpisodeTitleRole:
            return str(entry.get("episode_title", ""))
        elif role == self.OverviewRole:
            return str(entry.get("overview", ""))
        elif role == self.RatingRole:
            return str(entry.get("rating", "")) if entry.get("rating") else ""
        elif role == self.PosterRole:
            return str(entry.get("poster", ""))
        elif role == self.SizeRatioRole:
            return float(entry.get("size_ratio", 0.0))
        elif role == self.PercentStrRole:
            return str(entry.get("percent_str", ""))
        return None

    def roleNames(self):
        return {
            self.NameRole: b"name",
            self.PathRole: b"path",
            self.IsDirRole: b"is_dir",
            self.SizeRole: b"size",
            self.ModifiedRole: b"modified",
            self.CreatedRole: b"created",
            self.IconRole: b"icon",
            self.TypeRole: b"type",
            self.RawSizeRole: b"raw_size",
            self.RawModRole: b"raw_mod",
            self.RawCreatedRole: b"raw_created",
            self.ThumbRole: b"thumb",
            self.FolderPreviewsRole: b"folder_previews",
            self.EpisodeNumRole: b"episode_num",
            self.ProgressRole: b"progress",
            self.IsWatchedRole: b"is_watched",
            self.IsNewRole: b"is_new",
            self.IsMovieItemRole: b"is_movie_item",
            self.IsHdrRole: b"is_hdr",
            self.EpisodeTitleRole: b"episode_title",
            self.OverviewRole: b"overview",
            self.RatingRole: b"rating",
            self.PosterRole: b"poster",
            self.SizeRatioRole: b"size_ratio",
            self.PercentStrRole: b"percent_str",
        }

    def _rebuild_index_map(self):
        self._path_to_row = {e.get("path", ""): idx for idx, e in enumerate(self._entries)}

    @classmethod
    def _diff_entry_roles(cls, old_e: dict, new_e: dict) -> list:
        changed = []
        for k, role in cls.FIELD_TO_ROLE.items():
            if old_e.get(k) != new_e.get(k):
                changed.append(role)
        return changed

    def set_entries(self, entries: list, context_key: str = None, force_reset: bool = False):
        """
        Smart Damage-Tracking In-Place Updater:
        - Only performs a full model reset when switching to a completely different directory (context_key changes)
          or when clearing/initializing from empty.
        - When refreshing the SAME directory (file added, deleted, renamed, or sorted), performs exact
          row removals, row moves, row insertions, and granular role-level dataChanged emissions so scroll position
          and QML Image delegates are 100% preserved without any flashing!
        """
        if context_key is not None and context_key != self._current_context_key:
            self._current_context_key = context_key
            force_reset = True

        if force_reset or not self._entries or not entries:
            self.beginResetModel()
            self._entries = list(entries)
            self._rebuild_index_map()
            self.endResetModel()
            return

        new_paths = [e.get("path", "") for e in entries]
        if len(set(new_paths)) != len(new_paths):
            # Fallback if duplicate paths exist
            self.beginResetModel()
            self._entries = list(entries)
            self._rebuild_index_map()
            self.endResetModel()
            return

        new_path_set = set(new_paths)

        # Step 1: Remove deleted items in-place (backwards so indices remain valid)
        for i in range(len(self._entries) - 1, -1, -1):
            if self._entries[i].get("path", "") not in new_path_set:
                self.beginRemoveRows(QModelIndex(), i, i)
                self._entries.pop(i)
                self.endRemoveRows()

        # Step 2: Reorder surviving items & insert newly added items at their exact target index
        for target_idx, new_entry in enumerate(entries):
            p = new_entry.get("path", "")
            existing_idx = -1
            for scan_i in range(target_idx, len(self._entries)):
                if self._entries[scan_i].get("path", "") == p:
                    existing_idx = scan_i
                    break

            if existing_idx == target_idx:
                old_entry = self._entries[target_idx]
                changed_roles = self._diff_entry_roles(old_entry, new_entry)
                if changed_roles:
                    self._entries[target_idx] = new_entry
                    m_idx = self.index(target_idx, 0)
                    self.dataChanged.emit(m_idx, m_idx, changed_roles)
            elif existing_idx > target_idx:
                self.beginMoveRows(QModelIndex(), existing_idx, existing_idx, QModelIndex(), target_idx)
                moved_entry = self._entries.pop(existing_idx)
                self._entries.insert(target_idx, moved_entry)
                self.endMoveRows()

                changed_roles = self._diff_entry_roles(moved_entry, new_entry)
                if changed_roles:
                    self._entries[target_idx] = new_entry
                    m_idx = self.index(target_idx, 0)
                    self.dataChanged.emit(m_idx, m_idx, changed_roles)
            else:
                self.beginInsertRows(QModelIndex(), target_idx, target_idx)
                self._entries.insert(target_idx, new_entry)
                self.endInsertRows()

        self._rebuild_index_map()

    def update_thumbnail(self, file_path, thumb_path):
        idx = self._path_to_row.get(file_path)
        if idx is not None and 0 <= idx < len(self._entries):
            if self._entries[idx].get("thumb") != thumb_path:
                self._entries[idx]["thumb"] = thumb_path
                model_idx = self.index(idx, 0)
                self.dataChanged.emit(model_idx, model_idx, [self.ThumbRole])

    def update_jellyfin_metadata(
        self,
        file_path: str,
        ep_title: str,
        overview: str,
        progress_val=None,
        is_watched_val=None,
        rating_val=None,
        poster_path: str = ""
    ):
        idx = self._path_to_row.get(file_path)
        if idx is not None and 0 <= idx < len(self._entries):
            changed_roles = []
            if ep_title and self._entries[idx].get("episode_title") != ep_title:
                self._entries[idx]["episode_title"] = ep_title
                changed_roles.append(self.EpisodeTitleRole)
            if overview and self._entries[idx].get("overview") != overview:
                self._entries[idx]["overview"] = overview
                changed_roles.append(self.OverviewRole)
            if rating_val is not None:
                r_str = str(rating_val) if rating_val else ""
                if self._entries[idx].get("rating") != r_str:
                    self._entries[idx]["rating"] = r_str
                    changed_roles.append(self.RatingRole)
            if poster_path and self._entries[idx].get("poster") != poster_path:
                self._entries[idx]["poster"] = poster_path
                changed_roles.append(self.PosterRole)
            if progress_val is not None:
                f_prog = float(progress_val)
                if abs(float(self._entries[idx].get("progress", 0.0)) - f_prog) > 0.0005:
                    self._entries[idx]["progress"] = f_prog
                    changed_roles.append(self.ProgressRole)
            if is_watched_val is not None:
                b_watched = bool(is_watched_val)
                if bool(self._entries[idx].get("is_watched", False)) != b_watched:
                    self._entries[idx]["is_watched"] = b_watched
                    if b_watched:
                        self._entries[idx]["is_new"] = False
                    changed_roles.extend([self.IsWatchedRole, self.IsNewRole])
            if changed_roles:
                model_idx = self.index(idx, 0)
                self.dataChanged.emit(model_idx, model_idx, changed_roles)

    def update_hdr_status(self, file_path: str, is_hdr: bool):
        idx = self._path_to_row.get(file_path)
        if idx is not None and 0 <= idx < len(self._entries):
            if self._entries[idx].get("is_hdr") != bool(is_hdr):
                self._entries[idx]["is_hdr"] = bool(is_hdr)
                model_idx = self.index(idx, 0)
                self.dataChanged.emit(model_idx, model_idx, [self.IsHdrRole])

    def update_folder_previews(self, folder_path, previews):
        idx = self._path_to_row.get(folder_path)
        if idx is not None and 0 <= idx < len(self._entries):
            if self._entries[idx].get("folder_previews") != previews:
                self._entries[idx]["folder_previews"] = previews
                model_idx = self.index(idx, 0)
                self.dataChanged.emit(model_idx, model_idx, [self.FolderPreviewsRole])

    def update_media_progress(self, file_path, progress_val, is_watched_val, is_new_val=None):
        idx = self._path_to_row.get(file_path)
        if idx is not None and 0 <= idx < len(self._entries):
            changed_roles = []
            f_prog = float(progress_val)
            b_watched = bool(is_watched_val)
            if abs(float(self._entries[idx].get("progress", 0.0)) - f_prog) > 0.0005:
                self._entries[idx]["progress"] = f_prog
                changed_roles.append(self.ProgressRole)
            if bool(self._entries[idx].get("is_watched", False)) != b_watched:
                self._entries[idx]["is_watched"] = b_watched
                changed_roles.append(self.IsWatchedRole)
            if b_watched and self._entries[idx].get("is_new", False):
                self._entries[idx]["is_new"] = False
                changed_roles.append(self.IsNewRole)
            elif is_new_val is not None and bool(self._entries[idx].get("is_new", False)) != bool(is_new_val):
                self._entries[idx]["is_new"] = bool(is_new_val)
                changed_roles.append(self.IsNewRole)
            if changed_roles:
                model_idx = self.index(idx, 0)
                self.dataChanged.emit(model_idx, model_idx, changed_roles)

    def get_row_for_path(self, item_path: str) -> int:
        return self._path_to_row.get(item_path, -1)

    def get_entry_at(self, row: int):
        if 0 <= row < len(self._entries):
            return self._entries[row]
        return None

    def update_entry_size(self, item_path, size_str, raw_size=0):
        idx = self._path_to_row.get(item_path)
        if idx is not None and 0 <= idx < len(self._entries):
            if self._entries[idx].get("size") != size_str or (raw_size > 0 and self._entries[idx].get("raw_size") != raw_size):
                self._entries[idx]["size"] = size_str
                if raw_size > 0:
                    self._entries[idx]["raw_size"] = raw_size
                model_idx = self.index(idx, 0)
                self.dataChanged.emit(model_idx, model_idx, [self.SizeRole, self.RawSizeRole])


class MediaHubCardModel(QAbstractListModel):
    """
    Persistent in-place model for a single horizontal Media Hub row.
    Updates individual cards (progress, badge, subtitle, poster, watched state) in-place
    so QML Image delegates NEVER flash, reload, or lose horizontal scroll position!
    """
    NameRole = Qt.ItemDataRole.UserRole + 1
    DisplayTitleRole = Qt.ItemDataRole.UserRole + 2
    SubtitleRole = Qt.ItemDataRole.UserRole + 3
    BadgeRole = Qt.ItemDataRole.UserRole + 4
    PathRole = Qt.ItemDataRole.UserRole + 5
    IsDirRole = Qt.ItemDataRole.UserRole + 6
    SizeRole = Qt.ItemDataRole.UserRole + 7
    ModifiedRole = Qt.ItemDataRole.UserRole + 8
    IconRole = Qt.ItemDataRole.UserRole + 9
    TypeRole = Qt.ItemDataRole.UserRole + 10
    ThumbRole = Qt.ItemDataRole.UserRole + 11
    FolderPreviewsRole = Qt.ItemDataRole.UserRole + 12
    EpisodeNumRole = Qt.ItemDataRole.UserRole + 13
    ProgressRole = Qt.ItemDataRole.UserRole + 14
    IsWatchedRole = Qt.ItemDataRole.UserRole + 15
    IsNewRole = Qt.ItemDataRole.UserRole + 16
    IsMovieItemRole = Qt.ItemDataRole.UserRole + 17
    IsHdrRole = Qt.ItemDataRole.UserRole + 18
    EpisodeTitleRole = Qt.ItemDataRole.UserRole + 19
    OverviewRole = Qt.ItemDataRole.UserRole + 20
    RatingRole = Qt.ItemDataRole.UserRole + 21
    PosterRole = Qt.ItemDataRole.UserRole + 22
    IsRecentlyAddedCardRole = Qt.ItemDataRole.UserRole + 23
    IsAiringCardRole = Qt.ItemDataRole.UserRole + 24
    AiringIdRole = Qt.ItemDataRole.UserRole + 25
    LinkedPathRole = Qt.ItemDataRole.UserRole + 26
    LocalWatchedEpsRole = Qt.ItemDataRole.UserRole + 27
    BehindCountRole = Qt.ItemDataRole.UserRole + 28
    IsGoingTightRole = Qt.ItemDataRole.UserRole + 29
    ArtSourceRole = Qt.ItemDataRole.UserRole + 30

    FIELD_TO_ROLE = {
        "name": NameRole,
        "display_title": DisplayTitleRole,
        "subtitle": SubtitleRole,
        "badge": BadgeRole,
        "path": PathRole,
        "is_dir": IsDirRole,
        "size": SizeRole,
        "modified": ModifiedRole,
        "icon": IconRole,
        "type": TypeRole,
        "thumb": ThumbRole,
        "folder_previews": FolderPreviewsRole,
        "episode_num": EpisodeNumRole,
        "progress": ProgressRole,
        "is_watched": IsWatchedRole,
        "is_new": IsNewRole,
        "is_movie_item": IsMovieItemRole,
        "is_hdr": IsHdrRole,
        "episode_title": EpisodeTitleRole,
        "overview": OverviewRole,
        "rating": RatingRole,
        "poster": PosterRole,
        "is_recently_added_card": IsRecentlyAddedCardRole,
        "is_airing_card": IsAiringCardRole,
        "airing_id": AiringIdRole,
        "linked_path": LinkedPathRole,
        "local_watched_eps": LocalWatchedEpsRole,
        "behind_count": BehindCountRole,
        "is_going_tight": IsGoingTightRole,
        "_art_source": ArtSourceRole,
    }

    def __init__(self, parent=None):
        super().__init__(parent)
        self._cards = []

    @staticmethod
    def _compute_art_source(card: dict) -> str:
        is_dir = bool(card.get("is_dir", False))
        is_movie = bool(card.get("is_movie_item", False))
        is_recent_batch = bool(card.get("is_recently_added_card", False))
        poster = str(card.get("poster") or "")
        thumb = str(card.get("thumb") or "")

        # Recently added episodes, movies, and show directories always take the vertical poster
        if is_recent_batch or is_dir or is_movie:
            if poster:
                return "file://" + poster
            if thumb:
                return "file://" + thumb

        # Direct in-progress episode files (Continue Watching / Next Up) use video thumbnails
        if thumb:
            return "file://" + thumb
        if poster:
            return "file://" + poster

        fps = card.get("folder_previews") or []
        if fps and isinstance(fps[0], dict) and fps[0].get("thumb"):
            return "file://" + str(fps[0]["thumb"])
        return ""

    @staticmethod
    def _card_key(card: dict) -> str:
        if card.get("is_airing_card") and card.get("airing_id"):
            return f"airing:{card['airing_id']}"
        return f"path:{card.get('path', '')}"

    def rowCount(self, parent=QModelIndex()):
        return len(self._cards)

    def data(self, index, role=Qt.ItemDataRole.DisplayRole):
        if not index.isValid() or not (0 <= index.row() < len(self._cards)):
            return None
        c = self._cards[index.row()]
        if role == self.NameRole:
            return str(c.get("name", ""))
        elif role == self.DisplayTitleRole:
            return str(c.get("display_title") or c.get("name") or "")
        elif role == self.SubtitleRole:
            return str(c.get("subtitle") or c.get("name") or "")
        elif role == self.BadgeRole:
            return str(c.get("badge", ""))
        elif role == self.PathRole:
            return str(c.get("path", ""))
        elif role == self.IsDirRole:
            return bool(c.get("is_dir", False))
        elif role == self.SizeRole:
            return str(c.get("size", ""))
        elif role == self.ModifiedRole:
            return str(c.get("modified", ""))
        elif role == self.IconRole:
            return str(c.get("icon", "🎬"))
        elif role == self.TypeRole:
            return str(c.get("type", ""))
        elif role == self.ThumbRole:
            return str(c.get("thumb", ""))
        elif role == self.FolderPreviewsRole:
            return c.get("folder_previews", [])
        elif role == self.EpisodeNumRole:
            return str(c.get("episode_num", ""))
        elif role == self.ProgressRole:
            return float(c.get("progress", 0.0))
        elif role == self.IsWatchedRole:
            return bool(c.get("is_watched", False))
        elif role == self.IsNewRole:
            return bool(c.get("is_new", False))
        elif role == self.IsMovieItemRole:
            return bool(c.get("is_movie_item", False))
        elif role == self.IsHdrRole:
            return bool(c.get("is_hdr", False))
        elif role == self.EpisodeTitleRole:
            return str(c.get("episode_title", ""))
        elif role == self.OverviewRole:
            return str(c.get("overview", ""))
        elif role == self.RatingRole:
            return str(c.get("rating", ""))
        elif role == self.PosterRole:
            return str(c.get("poster", ""))
        elif role == self.IsRecentlyAddedCardRole:
            return bool(c.get("is_recently_added_card", False))
        elif role == self.IsAiringCardRole:
            return bool(c.get("is_airing_card", False))
        elif role == self.AiringIdRole:
            return str(c.get("airing_id", ""))
        elif role == self.LinkedPathRole:
            return str(c.get("linked_path", ""))
        elif role == self.LocalWatchedEpsRole:
            return int(c.get("local_watched_eps", 0) or 0)
        elif role == self.BehindCountRole:
            return int(c.get("behind_count", 0) or 0)
        elif role == self.IsGoingTightRole:
            return bool(c.get("is_going_tight", False))
        elif role == self.ArtSourceRole:
            return str(c.get("_art_source", ""))
        return None

    def roleNames(self):
        return {
            self.NameRole: b"name",
            self.DisplayTitleRole: b"display_title",
            self.SubtitleRole: b"subtitle",
            self.BadgeRole: b"badge",
            self.PathRole: b"path",
            self.IsDirRole: b"is_dir",
            self.SizeRole: b"size",
            self.ModifiedRole: b"modified",
            self.IconRole: b"icon",
            self.TypeRole: b"type",
            self.ThumbRole: b"thumb",
            self.FolderPreviewsRole: b"folder_previews",
            self.EpisodeNumRole: b"episode_num",
            self.ProgressRole: b"progress",
            self.IsWatchedRole: b"is_watched",
            self.IsNewRole: b"is_new",
            self.IsMovieItemRole: b"is_movie_item",
            self.IsHdrRole: b"is_hdr",
            self.EpisodeTitleRole: b"episode_title",
            self.OverviewRole: b"overview",
            self.RatingRole: b"rating",
            self.PosterRole: b"poster",
            self.IsRecentlyAddedCardRole: b"is_recently_added_card",
            self.IsAiringCardRole: b"is_airing_card",
            self.AiringIdRole: b"airing_id",
            self.LinkedPathRole: b"linked_path",
            self.LocalWatchedEpsRole: b"local_watched_eps",
            self.BehindCountRole: b"behind_count",
            self.IsGoingTightRole: b"is_going_tight",
            self.ArtSourceRole: b"art_source",
        }

    def sync_cards(self, new_cards: list):
        prepared = []
        seen_keys = set()
        for raw_c in new_cards:
            c = dict(raw_c)
            c["_art_source"] = self._compute_art_source(c)
            k = self._card_key(c)
            if k in seen_keys:
                k = f"{k}#{len(prepared)}"
            c["_key"] = k
            seen_keys.add(k)
            prepared.append(c)

        if not self._cards and not prepared:
            return

        new_key_set = {c["_key"] for c in prepared}

        # 1. Remove cards that are no longer in this row
        for i in range(len(self._cards) - 1, -1, -1):
            if self._cards[i].get("_key") not in new_key_set:
                self.beginRemoveRows(QModelIndex(), i, i)
                self._cards.pop(i)
                self.endRemoveRows()

        # 2. Move, update in-place, or insert cards
        for target_idx, new_c in enumerate(prepared):
            k = new_c["_key"]
            existing_idx = -1
            for scan_i in range(target_idx, len(self._cards)):
                if self._cards[scan_i].get("_key") == k:
                    existing_idx = scan_i
                    break

            if existing_idx == target_idx:
                old_c = self._cards[target_idx]
                changed_roles = [
                    role for field, role in self.FIELD_TO_ROLE.items()
                    if old_c.get(field) != new_c.get(field)
                ]
                if changed_roles:
                    self._cards[target_idx] = new_c
                    m_idx = self.index(target_idx, 0)
                    self.dataChanged.emit(m_idx, m_idx, changed_roles)
            elif existing_idx > target_idx:
                self.beginMoveRows(QModelIndex(), existing_idx, existing_idx, QModelIndex(), target_idx)
                moved_c = self._cards.pop(existing_idx)
                self._cards.insert(target_idx, moved_c)
                self.endMoveRows()

                changed_roles = [
                    role for field, role in self.FIELD_TO_ROLE.items()
                    if moved_c.get(field) != new_c.get(field)
                ]
                if changed_roles:
                    self._cards[target_idx] = new_c
                    m_idx = self.index(target_idx, 0)
                    self.dataChanged.emit(m_idx, m_idx, changed_roles)
            else:
                self.beginInsertRows(QModelIndex(), target_idx, target_idx)
                self._cards.insert(target_idx, new_c)
                self.endInsertRows()

    def update_thumbnail_in_place(self, file_path: str, thumb_path: str):
        for idx, c in enumerate(self._cards):
            if c.get("path") == file_path and c.get("thumb") != thumb_path:
                c["thumb"] = thumb_path
                new_art = self._compute_art_source(c)
                roles = [self.ThumbRole]
                if c.get("_art_source") != new_art:
                    c["_art_source"] = new_art
                    roles.append(self.ArtSourceRole)
                m_idx = self.index(idx, 0)
                self.dataChanged.emit(m_idx, m_idx, roles)

    def update_folder_previews_in_place(self, folder_path: str, previews: list):
        for idx, c in enumerate(self._cards):
            if c.get("path") == folder_path and c.get("folder_previews") != previews:
                c["folder_previews"] = previews
                new_art = self._compute_art_source(c)
                roles = [self.FolderPreviewsRole]
                if c.get("_art_source") != new_art:
                    c["_art_source"] = new_art
                    roles.append(self.ArtSourceRole)
                m_idx = self.index(idx, 0)
                self.dataChanged.emit(m_idx, m_idx, roles)

    def update_progress_in_place(self, file_path: str, progress_val: float, is_watched_val: bool):
        for idx, c in enumerate(self._cards):
            if c.get("path") == file_path:
                changed_roles = []
                f_prog = round(float(progress_val), 4)
                b_watched = bool(is_watched_val)
                if abs(float(c.get("progress", 0.0)) - f_prog) > 0.0005:
                    c["progress"] = f_prog
                    changed_roles.append(self.ProgressRole)
                if bool(c.get("is_watched", False)) != b_watched:
                    c["is_watched"] = b_watched
                    changed_roles.append(self.IsWatchedRole)
                if changed_roles:
                    m_idx = self.index(idx, 0)
                    self.dataChanged.emit(m_idx, m_idx, changed_roles)

    def update_jellyfin_in_place(self, file_path: str, meta: dict):
        for idx, c in enumerate(self._cards):
            if c.get("path") == file_path:
                changed_roles = []
                poster = meta.get("poster", "")
                if poster and c.get("poster") != poster:
                    c["poster"] = poster
                    changed_roles.append(self.PosterRole)
                    new_art = self._compute_art_source(c)
                    if c.get("_art_source") != new_art:
                        c["_art_source"] = new_art
                        changed_roles.append(self.ArtSourceRole)
                if meta.get("overview") and c.get("overview") != meta["overview"]:
                    c["overview"] = meta["overview"]
                    changed_roles.append(self.OverviewRole)
                if meta.get("rating") is not None:
                    r_str = str(meta["rating"]) if meta["rating"] else ""
                    if c.get("rating") != r_str:
                        c["rating"] = r_str
                        changed_roles.append(self.RatingRole)
                if changed_roles:
                    m_idx = self.index(idx, 0)
                    self.dataChanged.emit(m_idx, m_idx, changed_roles)


class MediaHubSectionModel(QAbstractListModel):
    """
    Top-level persistent model for Media Hub sections (Continue Watching, Recently Added, Next Up, Airing).
    Holds a persistent MediaHubCardModel per section ID so rows and cards never flash or destroy their QML views!
    """
    SectionIdRole = Qt.ItemDataRole.UserRole + 1
    TitleRole = Qt.ItemDataRole.UserRole + 2
    SubtitleRole = Qt.ItemDataRole.UserRole + 3
    ItemCountRole = Qt.ItemDataRole.UserRole + 4
    CardsModelRole = Qt.ItemDataRole.UserRole + 5

    def __init__(self, parent=None):
        super().__init__(parent)
        self._sections = []
        self._card_models = {}

    def rowCount(self, parent=QModelIndex()):
        return len(self._sections)

    def data(self, index, role=Qt.ItemDataRole.DisplayRole):
        if not index.isValid() or not (0 <= index.row() < len(self._sections)):
            return None
        sec = self._sections[index.row()]
        if role == self.SectionIdRole:
            return sec["id"]
        elif role == self.TitleRole:
            return sec["title"]
        elif role == self.SubtitleRole:
            return sec["subtitle"]
        elif role == self.ItemCountRole:
            return sec["count"]
        elif role == self.CardsModelRole:
            return sec["cards_model"]
        return None

    def roleNames(self):
        return {
            self.SectionIdRole: b"section_id",
            self.TitleRole: b"title",
            self.SubtitleRole: b"subtitle",
            self.ItemCountRole: b"item_count",
            self.CardsModelRole: b"cards_model",
        }

    def sync_sections(self, new_sections: list):
        new_ids = [s.get("id", "") for s in new_sections if s.get("id")]
        new_id_set = set(new_ids)

        # 1. Remove hidden/removed sections in-place
        for i in range(len(self._sections) - 1, -1, -1):
            if self._sections[i]["id"] not in new_id_set:
                self.beginRemoveRows(QModelIndex(), i, i)
                self._sections.pop(i)
                self.endRemoveRows()

        # 2. Reorder, update, or insert sections while keeping each section's MediaHubCardModel alive!
        for target_idx, s_data in enumerate(new_sections):
            sid = s_data.get("id", "")
            if not sid:
                continue
            if sid not in self._card_models:
                self._card_models[sid] = MediaHubCardModel(self)
            card_model = self._card_models[sid]
            items_list = s_data.get("items") or []
            card_model.sync_cards(items_list)

            new_sec_entry = {
                "id": sid,
                "title": str(s_data.get("title", "")),
                "subtitle": str(s_data.get("subtitle", "")),
                "count": len(items_list),
                "cards_model": card_model,
            }

            existing_idx = -1
            for scan_i in range(target_idx, len(self._sections)):
                if self._sections[scan_i]["id"] == sid:
                    existing_idx = scan_i
                    break

            if existing_idx == target_idx:
                old_sec = self._sections[target_idx]
                changed_roles = []
                if old_sec["title"] != new_sec_entry["title"]:
                    changed_roles.append(self.TitleRole)
                if old_sec["subtitle"] != new_sec_entry["subtitle"]:
                    changed_roles.append(self.SubtitleRole)
                if old_sec["count"] != new_sec_entry["count"]:
                    changed_roles.append(self.ItemCountRole)
                self._sections[target_idx] = new_sec_entry
                if changed_roles:
                    m_idx = self.index(target_idx, 0)
                    self.dataChanged.emit(m_idx, m_idx, changed_roles)
            elif existing_idx > target_idx:
                self.beginMoveRows(QModelIndex(), existing_idx, existing_idx, QModelIndex(), target_idx)
                moved_sec = self._sections.pop(existing_idx)
                self._sections.insert(target_idx, moved_sec)
                self.endMoveRows()
                self._sections[target_idx] = new_sec_entry
                m_idx = self.index(target_idx, 0)
                self.dataChanged.emit(m_idx, m_idx, [self.TitleRole, self.SubtitleRole, self.ItemCountRole])
            else:
                self.beginInsertRows(QModelIndex(), target_idx, target_idx)
                self._sections.insert(target_idx, new_sec_entry)
                self.endInsertRows()

    def update_thumbnail_in_place(self, file_path: str, thumb_path: str):
        for cm in self._card_models.values():
            cm.update_thumbnail_in_place(file_path, thumb_path)

    def update_folder_previews_in_place(self, folder_path: str, previews: list):
        for cm in self._card_models.values():
            cm.update_folder_previews_in_place(folder_path, previews)

    def update_progress_in_place(self, file_path: str, progress_val: float, is_watched_val: bool):
        for cm in self._card_models.values():
            cm.update_progress_in_place(file_path, progress_val, is_watched_val)

    def update_jellyfin_in_place(self, file_path: str, meta: dict):
        for cm in self._card_models.values():
            cm.update_jellyfin_in_place(file_path, meta)
