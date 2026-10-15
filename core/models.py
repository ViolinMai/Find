from PySide6.QtCore import Qt, QAbstractListModel, QModelIndex


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

    def __init__(self, parent=None):
        super().__init__(parent)
        self._entries = []
        self._path_to_row = {}

    def rowCount(self, parent=QModelIndex()):
        return len(self._entries)

    def data(self, index, role=Qt.ItemDataRole.DisplayRole):
        if not index.isValid() or not (0 <= index.row() < len(self._entries)):
            return None

        entry = self._entries[index.row()]
        if role == self.NameRole:
            return entry["name"]
        elif role == self.PathRole:
            return entry["path"]
        elif role == self.IsDirRole:
            return entry["is_dir"]
        elif role == self.SizeRole:
            return entry["size"]
        elif role == self.ModifiedRole:
            return entry["modified"]
        elif role == self.CreatedRole:
            return entry.get("created", "")
        elif role == self.IconRole:
            return entry["icon"]
        elif role == self.TypeRole:
            return entry["type"]
        elif role == self.RawSizeRole:
            return entry["raw_size"]
        elif role == self.RawModRole:
            return entry["raw_mod"]
        elif role == self.RawCreatedRole:
            return entry.get("raw_created", 0)
        elif role == self.ThumbRole:
            return entry.get("thumb", "")
        elif role == self.FolderPreviewsRole:
            return entry.get("folder_previews", [])
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
        }

    def set_entries(self, entries):
        self.beginResetModel()
        self._entries = entries
        self._path_to_row = {e["path"]: idx for idx, e in enumerate(entries)}
        self.endResetModel()

    def update_thumbnail(self, file_path, thumb_path):
        idx = self._path_to_row.get(file_path)
        if idx is not None and 0 <= idx < len(self._entries):
            self._entries[idx]["thumb"] = thumb_path
            model_idx = self.index(idx, 0)
            self.dataChanged.emit(model_idx, model_idx, [self.ThumbRole])

    def update_folder_previews(self, folder_path, previews):
        idx = self._path_to_row.get(folder_path)
        if idx is not None and 0 <= idx < len(self._entries):
            self._entries[idx]["folder_previews"] = previews
            model_idx = self.index(idx, 0)
            self.dataChanged.emit(model_idx, model_idx, [self.FolderPreviewsRole])

    def update_entry_size(self, item_path, size_str, raw_size=0):
        idx = self._path_to_row.get(item_path)
        if idx is not None and 0 <= idx < len(self._entries):
            self._entries[idx]["size"] = size_str
            if raw_size > 0:
                self._entries[idx]["raw_size"] = raw_size
            model_idx = self.index(idx, 0)
            self.dataChanged.emit(model_idx, model_idx, [self.SizeRole, self.RawSizeRole])
