import os
import subprocess
from pathlib import Path
from urllib.parse import unquote, urlparse
from PySide6.QtCore import QObject, Signal


def uri_to_local_path(uri_or_path: str) -> str:
    if not uri_or_path:
        return ""
    s = str(uri_or_path).strip()
    if s.startswith("file://"):
        parsed = urlparse(s)
        return os.path.abspath(unquote(parsed.path))
    return os.path.abspath(os.path.expanduser(s))


def local_path_to_uri(path_str: str) -> str:
    p = os.path.abspath(path_str)
    return Path(p).as_uri()


class SystemIntegrationBridge(QObject):
    showItemsRequested = Signal(list)
    showFoldersRequested = Signal(list)
    portalPickerRequested = Signal(str, str, str, str, str)

    def __init__(self, backend, parent=None):
        super().__init__(parent)
        self.backend = backend
        self.showItemsRequested.connect(self._on_show_items)
        self.showFoldersRequested.connect(self._on_show_folders)
        self.portalPickerRequested.connect(self._on_portal_picker)
        self._active_portal_Finish = None
        self._dbus_ready = False
        self._init_dbus_services()

    def _init_dbus_services(self):
        try:
            from PySide6.QtDBus import QDBusConnection, QDBusObjectPath
            bus = QDBusConnection.sessionBus()
            if not bus.isConnected():
                return

            # Register standard FreeDesktop FileManager1 service (Used by Firefox "Show in Folder", etc.)
            bus.registerService("org.freedesktop.FileManager1")
            bus.registerObject(
                "/org/freedesktop/FileManager1",
                self,
                QDBusConnection.RegisterOption.ExportAllSlots
            )
            self._dbus_ready = True
        except Exception:
            self._dbus_ready = False

    def _on_show_items(self, uris: list):
        paths = [uri_to_local_path(u) for u in uris if u]
        valid = [p for p in paths if os.path.exists(p)]
        if not valid:
            return
        first = valid[0]
        parent_dir = first if os.path.isdir(first) else os.path.dirname(first)
        self.backend.navigateTo(parent_dir)
        self.backend.selectMultiplePaths(valid)

    def _on_show_folders(self, uris: list):
        paths = [uri_to_local_path(u) for u in uris if u]
        valid = [p for p in paths if os.path.exists(p)]
        if not valid:
            return
        target = valid[0] if os.path.isdir(valid[0]) else os.path.dirname(valid[0])
        self.backend.navigateTo(target)

    def _on_portal_picker(self, mode: str, filter_str: str, title: str, initial_dir: str, save_name: str):
        if initial_dir and os.path.isdir(initial_dir):
            self.backend.navigateTo(initial_dir)
        self.backend.openInternalPicker(mode, filter_str, title, save_name)


def install_desktop_and_set_default(main_script_path: str) -> bool:
    try:
        xdg_data = os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local" / "share"))
        apps_dir = Path(xdg_data) / "applications"
        apps_dir.mkdir(parents=True, exist_ok=True)
        desktop_file = apps_dir / "find.desktop"

        python_bin = os.path.abspath(os.sys.executable)
        script_abs = os.path.abspath(main_script_path)

        content = (
            "[Desktop Entry]\n"
            "Type=Application\n"
            "Name=Find\n"
            "GenericName=File Manager\n"
            "Comment=Modern Linux Wayland File Manager & Picker\n"
            f"Exec=\"{python_bin}\" \"{script_abs}\" %U\n"
            "Icon=system-file-manager\n"
            "Terminal=false\n"
            "StartupNotify=true\n"
            "Categories=System;FileTools;FileManager;Utility;\n"
            "MimeType=inode/directory;x-scheme-handler/file;\n"
            "Actions=new-window;\n\n"
            "[Desktop Action new-window]\n"
            "Name=Open New Window\n"
            f"Exec=\"{python_bin}\" \"{script_abs}\"\n"
        )
        desktop_file.write_text(content, encoding="utf-8")

        subprocess.run(
            ["xdg-mime", "default", "find.desktop", "inode/directory"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=3
        )
        subprocess.run(
            ["update-desktop-database", str(apps_dir)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=3
        )
        return True
    except Exception:
        return False


def is_default_file_manager() -> bool:
    try:
        res = subprocess.run(
            ["xdg-mime", "query", "default", "inode/directory"],
            capture_output=True,
            text=True,
            timeout=2
        )
        if res.returncode == 0:
            return "find.desktop" in res.stdout.strip().lower()
    except Exception:
        pass
    return False
