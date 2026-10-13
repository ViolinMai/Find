import sys
import os
import argparse
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from core.backend import FileManagerBackend


def main():
    os.environ["QT_QPA_PLATFORM"] = "wayland;xcb"

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

    engine = QQmlApplicationEngine()
    backend = FileManagerBackend()

    # CLI Picker Integration
    if args.picker or args.folder:
        backend._launched_as_picker = True
        mode = "folder" if args.folder else ("multi_file" if args.multiple else "file")
        title = args.title if args.title else ("Select Folder" if mode == "folder" else "Select File")
        backend.openInternalPicker(mode, args.filter, title)
        if args.path and os.path.isdir(args.path):
            backend.navigateTo(args.path)

    engine.rootContext().setContextProperty("backend", backend)
    engine.addImportPath(os.path.join(os.path.dirname(__file__), "ui"))
    engine.load("ui/main.qml")

    if not engine.rootObjects():
        sys.exit(-1)

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
