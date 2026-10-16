import sys
import os
import argparse
from urllib.parse import unquote, urlparse
from pathlib import Path
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtCore import QUrl
from PySide6.QtQuick import QQuickWindow
from PySide6.QtQuickControls2 import QQuickStyle
from core.backend import FileManagerBackend


def _normalize_cli_target(raw_arg: str) -> str:
    if not raw_arg:
        return ""
    s = str(raw_arg).strip()
    if s in ("recent://", "trash://"):
        return s
    if s.startswith("file://"):
        parsed = urlparse(s)
        s = unquote(parsed.path) or s[7:]
    return os.path.abspath(os.path.expanduser(os.path.expandvars(s)))


def main():
    os.environ["QT_QPA_PLATFORM"] = "wayland;xcb"

    QQuickWindow.setDefaultAlphaBuffer(True)
    QQuickStyle.setStyle("Basic")

    parser = argparse.ArgumentParser(description="Find - Modern Linux Wayland File Manager & Picker")
    parser.add_argument("--picker", action="store_true", help="Launch in File/Folder Picker mode")
    parser.add_argument("--folder", action="store_true", help="Select directory only")
    parser.add_argument("--save", action="store_true", help="Launch in Save File Picker mode (e.g. Firefox downloads)")
    parser.add_argument("--save-name", type=str, default="", help="Suggested filename when saving")
    parser.add_argument("--multiple", action="store_true", help="Allow selecting multiple files")
    parser.add_argument("--select", action="store_true", help="Highlight/select the target file in its parent folder")
    parser.add_argument("--filter", type=str, default="", help="File extension pattern (e.g., '*.png;*.jpg')")
    parser.add_argument("--title", type=str, default="", help="Dialog window title")
    parser.add_argument("paths", nargs="*", help="Initial path(s) or URI(s)")

    args, unknown = parser.parse_known_args()

    app = QGuiApplication(sys.argv)
    app.setApplicationName("Find")
    app.setOrganizationName("Find")
    app.setDesktopFileName("find")

    engine = QQmlApplicationEngine()
    backend = FileManagerBackend(app)

    cleaned_paths = [_normalize_cli_target(p) for p in (args.paths or []) if p]

    if args.picker or args.folder or args.save:
        backend._launched_as_picker = True
        if args.save:
            mode = "save"
        elif args.folder:
            mode = "folder"
        elif args.multiple:
            mode = "multi_file"
        else:
            mode = "file"

        default_title = (
            "Save File As" if mode == "save"
            else ("Select Folder" if mode == "folder" else "Select File")
        )
        title = args.title if args.title else default_title
        suggested_name = args.save_name

        if cleaned_paths:
            first_p = cleaned_paths[0]
            if os.path.isdir(first_p):
                backend.navigateTo(first_p)
            else:
                parent_d = os.path.dirname(first_p)
                if os.path.isdir(parent_d):
                    backend.navigateTo(parent_d)
                if not suggested_name:
                    suggested_name = os.path.basename(first_p)

        backend.openInternalPicker(mode, args.filter, title, suggested_name)
    elif cleaned_paths:
        first_p = cleaned_paths[0]
        if os.path.isdir(first_p):
            backend.navigateTo(first_p)
            for extra_p in cleaned_paths[1:]:
                if os.path.isdir(extra_p):
                    backend.addTab(extra_p)
        elif os.path.exists(first_p):
            parent_d = os.path.dirname(first_p)
            if os.path.isdir(parent_d):
                backend.navigateTo(parent_d)
                backend.selectMultiplePaths(cleaned_paths)

    engine.rootContext().setContextProperty("backend", backend)

    qml_dir = Path(__file__).resolve().parent / "ui"
    engine.addImportPath(str(qml_dir))
    main_qml = qml_dir / "main.qml"
    engine.load(QUrl.fromLocalFile(str(main_qml)))

    if not engine.rootObjects():
        sys.exit(-1)

    exit_code = app.exec()
    del engine
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
