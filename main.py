import sys
import os
import argparse
from pathlib import Path
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtCore import QUrl
from PySide6.QtQuick import QQuickWindow
from PySide6.QtQuickControls2 import QQuickStyle
from core.backend import FileManagerBackend


def main():
    os.environ["QT_QPA_PLATFORM"] = "wayland;xcb"

    QQuickWindow.setDefaultAlphaBuffer(True)
    QQuickStyle.setStyle("Basic")

    parser = argparse.ArgumentParser(description="Find - Modern Linux Wayland File Manager & Picker")
    parser.add_argument("--picker", action="store_true", help="Launch in File/Folder Picker mode")
    parser.add_argument("--folder", action="store_true", help="Select directory only")
    parser.add_argument("--multiple", action="store_true", help="Allow selecting multiple files")
    parser.add_argument("--filter", type=str, default="", help="File extension pattern (e.g., '*.png;*.jpg')")
    parser.add_argument("--title", type=str, default="", help="Dialog window title")
    parser.add_argument("path", nargs="?", default="", help="Initial path")

    args, unknown = parser.parse_known_args()

    app = QGuiApplication(sys.argv)
    app.setApplicationName("Find")
    app.setOrganizationName("Find")
    app.setDesktopFileName("find")

    engine = QQmlApplicationEngine()
    backend = FileManagerBackend(app)

    if args.picker or args.folder:
        backend._launched_as_picker = True
        mode = "folder" if args.folder else ("multi_file" if args.multiple else "file")
        title = args.title if args.title else ("Select Folder" if mode == "folder" else "Select File")
        backend.openInternalPicker(mode, args.filter, title)
        if args.path and os.path.isdir(args.path):
            backend.navigateTo(args.path)
    elif args.path and os.path.isdir(args.path):
        backend.navigateTo(args.path)

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
