import os
import subprocess
from pathlib import Path
from urllib.parse import unquote, urlparse
from PySide6.QtCore import QObject, Signal, Slot, QMetaObject, Qt


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
            from PySide6.QtDBus import QDBusConnection
            bus = QDBusConnection.sessionBus()
            if not bus.isConnected():
                return

            # Register standard FreeDesktop FileManager1 service (Used by Firefox "Show in Folder", etc.)
            ok_srv = bus.registerService("org.freedesktop.FileManager1")
            ok_obj = bus.registerObject(
                "/org/freedesktop/FileManager1",
                self,
                QDBusConnection.RegisterOption.ExportAllSlots
            )
            self._dbus_ready = bool(ok_srv and ok_obj)
        except Exception:
            self._dbus_ready = False

    @Slot("QStringList", "QString")
    def ShowItems(self, uris: list, startup_id: str = ""):
        self.showItemsRequested.emit(list(uris))

    @Slot("QStringList", "QString")
    def ShowFolders(self, uris: list, startup_id: str = ""):
        self.showFoldersRequested.emit(list(uris))

    @Slot("QStringList", "QString")
    def ShowItemProperties(self, uris: list, startup_id: str = ""):
        self.showItemsRequested.emit(list(uris))

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

        # Also create D-Bus service activation file so org.freedesktop.FileManager1 auto-starts Find when closed
        dbus_srv_dir = Path(xdg_data) / "dbus-1" / "services"
        dbus_srv_dir.mkdir(parents=True, exist_ok=True)
        dbus_srv_file = dbus_srv_dir / "org.freedesktop.FileManager1.service"
        dbus_srv_content = (
            "[D-BUS Service]\n"
            "Name=org.freedesktop.FileManager1\n"
            f"Exec=\"{python_bin}\" \"{script_abs}\"\n"
        )
        dbus_srv_file.write_text(dbus_srv_content, encoding="utf-8")

        # Create xdg-desktop-portal-termfilechooser wrapper script for native Portal FileChooser integration
        local_bin = Path.home() / ".local" / "bin"
        local_bin.mkdir(parents=True, exist_ok=True)
        wrapper_bin = local_bin / "find-fm"
        wrapper_bin.write_text(f"#!/usr/bin/env bash\nexec \"{python_bin}\" \"{script_abs}\" \"$@\"\n", encoding="utf-8")
        try:
            os.chmod(wrapper_bin, 0o755)
        except OSError:
            pass

        portal_wrapper = local_bin / "find-portal-wrapper.sh"
        portal_wrapper_code = (
            "#!/usr/bin/env bash\n"
            "# Wrapper for xdg-desktop-portal-termfilechooser\n"
            "multiple=\"$1\"\n"
            "directory=\"$2\"\n"
            "save=\"$3\"\n"
            "path=\"$4\"\n"
            "out=\"$5\"\n"
            "args=(\"--picker\")\n"
            "[ \"$directory\" = \"1\" ] && args+=(\"--folder\")\n"
            "[ \"$multiple\" = \"1\" ] && args+=(\"--multiple\")\n"
            "if [ \"$save\" = \"1\" ]; then\n"
            "    args+=(\"--save\" \"--save-name\" \"$(basename \"$path\")\")\n"
            "    args+=(\"$(dirname \"$path\")\")\n"
            "elif [ -n \"$path\" ]; then\n"
            "    args+=(\"$path\")\n"
            "fi\n"
            f"\"{python_bin}\" \"{script_abs}\" \"${{args[@]}}\" > \"$out\"\n"
        )
        portal_wrapper.write_text(portal_wrapper_code, encoding="utf-8")
        try:
            os.chmod(portal_wrapper, 0o755)
        except OSError:
            pass

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
