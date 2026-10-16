import fnmatch
from PySide6.QtCore import QObject, Signal, Property, Slot


class PickerContext(QObject):
    activeChanged = Signal()
    modeChanged = Signal()
    filterChanged = Signal()
    selectedChanged = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._is_active = False
        self._mode = "file"
        self._filter_patterns = []
        self._title = "Select File"
        self._selected_paths = []
        self._filter_display = "All Supported Files"
        self._save_filename = ""

    @Property(str, notify=selectedChanged)
    def saveFilename(self):
        return self._save_filename

    @Slot(str)
    def setSaveFilename(self, name: str):
        if self._save_filename != name:
            self._save_filename = name.strip()
            self.selectedChanged.emit()

    @Property(bool, notify=activeChanged)
    def isActive(self):
        return self._is_active

    @Property(str, notify=modeChanged)
    def mode(self):
        return self._mode

    @Property(str, notify=filterChanged)
    def title(self):
        return self._title

    @Property(str, notify=filterChanged)
    def filterDisplay(self):
        return self._filter_display

    @Property(list, notify=selectedChanged)
    def selectedPaths(self):
        return self._selected_paths

    @Slot(str, str, str)
    @Slot(str, str, str, str)
    def activate(self, mode: str, filter_str: str, title: str, save_filename: str = ""):
        self._is_active = True
        self._mode = mode
        self._title = title if title else ("Save File" if mode == "save" else ("Select Folder" if mode == "folder" else "Select File"))
        self._filter_display = filter_str if filter_str else "All Files (*.*)"
        self._save_filename = save_filename.strip() if save_filename else ""

        if filter_str and "*.*" not in filter_str:
            raw_pats = filter_str.replace(";", " ").replace(",", " ").split()
            cleaned = []
            for p in raw_pats:
                p_clean = p.strip().lower()
                if not p_clean:
                    continue
                if not p_clean.startswith("*") and "." in p_clean:
                    p_clean = f"*{p_clean}" if p_clean.startswith(".") else f"*.{p_clean}"
                cleaned.append(p_clean)
            self._filter_patterns = cleaned
        else:
            self._filter_patterns = []

        self._selected_paths = []
        self.activeChanged.emit()
        self.modeChanged.emit()
        self.filterChanged.emit()
        self.selectedChanged.emit()

    @Slot()
    def deactivate(self):
        self._is_active = False
        self._selected_paths = []
        self.activeChanged.emit()
        self.selectedChanged.emit()

    def matches_filter(self, filename: str, is_dir: bool) -> bool:
        if is_dir:
            return True
        if not self._filter_patterns or "*" in self._filter_patterns:
            return True
        name_lower = filename.lower()
        for pat in self._filter_patterns:
            if fnmatch.fnmatch(name_lower, pat):
                return True
        return False

    @Slot(str, bool)
    def toggleSelect(self, path: str, is_dir: bool):
        if self._mode == "folder":
            if is_dir:
                self._selected_paths = [path]
                self.selectedChanged.emit()
            return

        if is_dir:
            return

        if self._mode == "save":
            self._selected_paths = [path]
            self._save_filename = Path(path).name
            self.selectedChanged.emit()
            return

        if self._mode == "multi_file":
            if path in self._selected_paths:
                self._selected_paths.remove(path)
            else:
                self._selected_paths.append(path)
        else:
            self._selected_paths = [path]
        self.selectedChanged.emit()

    @Slot(str)
    def setSelectedPath(self, path: str):
        self._selected_paths = [path] if path else []
        self.selectedChanged.emit()
