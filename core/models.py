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

    def __init__(self, parent=None):
        super().__init__(parent)
        self._entries = []

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
        }

    def set_entries(self, entries):
        self.beginResetModel()
        self._entries = entries
        self.endResetModel()

    def update_thumbnail(self, file_path, thumb_path):
        for idx, entry in enumerate(self._entries):
            if entry["path"] == file_path:
                entry["thumb"] = thumb_path
                model_idx = self.index(idx, 0)
                self.dataChanged.emit(model_idx, model_idx, [self.ThumbRole])
                break
