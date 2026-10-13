import re
from PySide6.QtCore import QObject, Signal, Property, Slot


class PickerContext(QObject):
    activeChanged = Signal()
    modeChanged = Signal()
    filterChanged = Signal()
    selectedChanged = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._is_active = False
        self._mode = "file"  # "file", "folder", "multi_file"
        self._filter_patterns = []  # e.g. ["*.png", "*.jpg"]
        self._title = "Select File"
        self._selected_paths = []
        self._filter_display = "All Supported Files"

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
    def activate(self, mode: str, filter_str: str, title: str):
        self._is_active = True
        self._mode = mode
        self._title = title if title else ("Select Folder" if mode == "folder" else "Select File")
        self._filter_display = filter_str if filter_str else "All Files (*.*)"

        # Parse glob filter patterns (e.g., "*.png;*.jpg" or "image/png")
        if filter_str and "*.*" not in filter_str:
            self._filter_patterns = [p.strip().lower() for p in filter_str.replace(";", " ").replace(",", " ").split() if p.strip()]
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
            return True  # Always allow folders so user can navigate
        if not self._filter_patterns:
            return True
        ext = "." + filename.split(".")[-1].lower() if "." in filename else ""
        for pat in self._filter_patterns:
            clean = pat.lstrip("*")
            if clean.startswith(".") and ext == clean:
                return True
            if clean == filename.lower():
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
            return  # In file mode, selecting folder doesn't stage it as return file

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
