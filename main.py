import sys
import os
import json
import logging
import traceback
import argparse
from urllib.parse import unquote, urlparse
from pathlib import Path
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtCore import QUrl, QObject, QEvent, Qt, QTimer, qInstallMessageHandler
from PySide6.QtQuick import QQuickWindow, QQuickItem
from PySide6.QtQuickControls2 import QQuickStyle
from PySide6.QtNetwork import QLocalSocket, QLocalServer
from core.backend import FileManagerBackend


def _setup_logging():
    xdg_cache = os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))
    log_dir = Path(xdg_cache) / "find"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / "error.log"
    logging.basicConfig(
        filename=str(log_file),
        level=logging.WARNING,
        format="%(asctime)s [%(levelname)s] %(message)s"
    )

    def _handle_exception(exc_type, exc_value, exc_tb):
        if issubclass(exc_type, KeyboardInterrupt):
            sys.__excepthook__(exc_type, exc_value, exc_tb)
            return
        logging.error("Uncaught exception:\n%s", "".join(traceback.format_exception(exc_type, exc_value, exc_tb)))
        sys.__excepthook__(exc_type, exc_value, exc_tb)

    sys.excepthook = _handle_exception


def _get_ipc_server_name() -> str:
    return f"find_fm_single_instance_{os.getuid()}"


def _try_send_to_existing_instance(paths: list, select_mode: bool) -> bool:
    sock = QLocalSocket()
    sock.connectToServer(_get_ipc_server_name())
    if not sock.waitForConnected(250):
        return False
    payload = json.dumps({
        "action": "select" if select_mode else "open",
        "paths": paths
    }).encode("utf-8") + b"\n"
    sock.write(payload)
    sock.flush()
    if sock.state() == QLocalSocket.LocalSocketState.ConnectedState:
        sock.waitForBytesWritten(300)
    if sock.state() != QLocalSocket.LocalSocketState.ConnectedState:
        sock.abort()
        return False
    # Wait for explicit ACK from the active window so a hung/closing background instance never blocks launching a new window!
    if not sock.waitForReadyRead(400):
        sock.abort()
        return False
    ack = bytes(sock.readAll()).decode("utf-8", errors="ignore").strip()
    sock.disconnectFromServer()
    return ack == "OK"


def _normalize_cli_target(raw_arg: str) -> str:
    if not raw_arg:
        return ""
    s = str(raw_arg).strip()
    if s in ("recent://", "trash://", "favorites://", "mediahub://") or s.startswith("analyzer://"):
        return s
    if s.startswith("trash:///") or s.startswith("trash:/"):
        return "trash://"
    if s.startswith("file://"):
        parsed = urlparse(s)
        s = unquote(parsed.path) or s[7:]
    elif "://" in s:
        return s
    return os.path.abspath(os.path.expanduser(os.path.expandvars(s)))


def _qt_message_filter(mode, context, message):
    if "qt.qpa.wayland.textinput" in message or "disableSurface" in message:
        return
    sys.stderr.write(f"{message}\n")


class FastWheelInterceptor(QObject):
    """
    High-refresh-rate (240Hz/280Hz) smooth inertial wheel animator.
    Instead of teleporting contentY in choppy jumps, accumulates target scroll delta
    and interpolates smoothly every 4ms with exponential easing.
    """
    def __init__(self, backend_ref, parent=None):
        super().__init__(parent)
        self.backend = backend_ref
        self._active_anims = {}  # id(flick) -> {"flick": flick, "horiz": bool, "target": float}
        self._timer = QTimer(self)
        self._timer.setTimerType(Qt.TimerType.PreciseTimer)
        self._timer.setInterval(4)  # ~250 FPS smooth interpolation
        self._timer.timeout.connect(self._tick_smooth_scroll)

    def _is_item_scrollable(self, item: QQuickItem, horiz: bool) -> bool:
        if not item or not item.isVisible() or not item.isEnabled():
            return False
        meta = item.metaObject()
        cls_name = meta.className() if meta else ""
        if not any(k in cls_name for k in ("QQuickListView", "QQuickGridView", "QQuickFlickable")):
            return False
        try:
            if horiz:
                cw = float(item.property("contentWidth") or 0.0)
                w = float(item.width() or 0.0)
                return cw > w + 2.0
            else:
                ch = float(item.property("contentHeight") or 0.0)
                h = float(item.height() or 0.0)
                return ch > h + 2.0
        except Exception:
            return False

    def _find_scrollable_at(self, root_item: QQuickItem, pos, horiz: bool):
        # Scan from deepest visual item upward, or find candidates under cursor
        candidates = []
        def _collect(parent_it, cur_p):
            for child in parent_it.childItems():
                if not child.isVisible():
                    continue
                cp = parent_it.mapToItem(child, cur_p)
                if child.contains(cp):
                    if self._is_item_scrollable(child, horiz):
                        candidates.append((child, cp))
                    _collect(child, cp)

        _collect(root_item, pos)
        if candidates:
            return candidates[-1][0]

        # Upward fallback
        target = root_item
        curr_pt = pos
        while target is not None:
            child = target.childAt(curr_pt.x(), curr_pt.y())
            if child is None or not child.isVisible():
                break
            curr_pt = target.mapToItem(child, curr_pt)
            target = child

        curr = target
        while curr is not None:
            if self._is_item_scrollable(curr, horiz):
                return curr
            curr = curr.parentItem()
        return None

    def _tick_smooth_scroll(self):
        if not self._active_anims:
            self._timer.stop()
            return
        finished_keys = []
        for k, st in list(self._active_anims.items()):
            flick = st["flick"]
            horiz = st["horiz"]
            prop_pos = "contentX" if horiz else "contentY"
            prop_size = "contentWidth" if horiz else "contentHeight"
            try:
                if not flick.isVisible():
                    finished_keys.append(k)
                    continue
                cur = float(flick.property(prop_pos) or 0.0)
                view_dim = float(flick.width() if horiz else flick.height())
                max_pos = max(0.0, float(flick.property(prop_size) or 0.0) - view_dim)
                target = max(0.0, min(max_pos, st["target"]))
                st["target"] = target

                diff = target - cur
                if abs(diff) < 0.6:
                    flick.setProperty(prop_pos, target)
                    finished_keys.append(k)
                else:
                    flick.setProperty(prop_pos, cur + diff * 0.28)
            except Exception:
                finished_keys.append(k)

        for fk in finished_keys:
            self._active_anims.pop(fk, None)
        if not self._active_anims:
            self._timer.stop()

    def eventFilter(self, watched, event):
        if event.type() == QEvent.Type.Wheel and isinstance(watched, QQuickWindow):
            try:
                if event.modifiers() & Qt.KeyboardModifier.ControlModifier:
                    return False
                angle = event.angleDelta()
                dx = angle.x()
                dy = angle.y()
                if dx == 0 and dy == 0:
                    return False

                pos = event.position()
                root_item = watched.contentItem()
                if root_item is None:
                    return False

                horiz_prefer = abs(dx) > abs(dy)
                flick = self._find_scrollable_at(root_item, pos, horiz=horiz_prefer)
                if flick is None and not horiz_prefer:
                    flick = self._find_scrollable_at(root_item, pos, horiz=True)
                    if flick is not None:
                        horiz_prefer = True
                elif flick is None and horiz_prefer:
                    flick = self._find_scrollable_at(root_item, pos, horiz=False)
                    if flick is not None:
                        horiz_prefer = False

                if flick is not None:
                    scale = float(self.backend.uiScaleFactor) if self.backend else 1.35
                    mult = float(self.backend.scrollSpeedMultiplier) if self.backend else 1.25
                    raw_delta = dx if (horiz_prefer and dx != 0) else dy
                    notches = raw_delta / 120.0
                    step = notches * (185.0 * scale * mult)

                    key = (id(flick), horiz_prefer)
                    prop_pos = "contentX" if horiz_prefer else "contentY"
                    prop_size = "contentWidth" if horiz_prefer else "contentHeight"
                    cur_pos = float(flick.property(prop_pos) or 0.0)
                    view_dim = float(flick.width() if horiz_prefer else flick.height())
                    max_pos = max(0.0, float(flick.property(prop_size) or 0.0) - view_dim)

                    base_target = self._active_anims[key]["target"] if key in self._active_anims else cur_pos
                    new_target = max(0.0, min(max_pos, base_target - step))
                    self._active_anims[key] = {
                        "flick": flick,
                        "horiz": horiz_prefer,
                        "target": new_target
                    }
                    if not self._timer.isActive():
                        self._timer.start()
                    event.accept()
                    return True
            except Exception:
                pass
        return False


def main():
    os.environ["QT_QPA_PLATFORM"] = "wayland;xcb"
    os.environ["QT_LOGGING_RULES"] = "qt.qpa.wayland.textinput=false;qt.qpa.wayland.textinput.warning=false"
    qInstallMessageHandler(_qt_message_filter)

    QQuickWindow.setDefaultAlphaBuffer(True)
    QQuickStyle.setStyle("Basic")

    parser = argparse.ArgumentParser(description="Find - Modern Linux Wayland File Manager & Picker")
    parser.add_argument("--mh", action="store_true", help="Launch directly in standalone MediaHub Window")
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
    _setup_logging()

    is_mediahub_launch = bool(args.mh)
    is_picker_launch = bool(args.picker or args.folder or args.save)
    cleaned_paths = [_normalize_cli_target(p) for p in (args.paths or []) if p]

    app = QGuiApplication(sys.argv)
    app.setApplicationName("Find")
    app.setOrganizationName("Find")
    app.setDesktopFileName("find")

    # Single-instance check for normal file manager launches (skip for standalone picker dialogs and standalone mediahub)
    if not is_picker_launch and not is_mediahub_launch:
        if _try_send_to_existing_instance(cleaned_paths, bool(args.select)):
            sys.exit(0)

    engine = QQmlApplicationEngine()
    backend = FileManagerBackend(app, is_picker_mode=is_picker_launch, is_mediahub_mode=is_mediahub_launch)

    ipc_server = None
    if not is_picker_launch and not is_mediahub_launch:
        srv_name = _get_ipc_server_name()
        QLocalServer.removeServer(srv_name)
        ipc_server = QLocalServer(app)
        if ipc_server.listen(srv_name):
            def _on_new_ipc_conn():
                while ipc_server.hasPendingConnections():
                    client = ipc_server.nextPendingConnection()
                    if client:
                        def _read_client(c=client):
                            try:
                                raw = bytes(c.readAll()).decode("utf-8", errors="ignore").strip()
                                for ln in raw.splitlines():
                                    msg = json.loads(ln)
                                    p_list = msg.get("paths") or []
                                    act = msg.get("action", "open")
                                    backend.handleExternalIpcRequest(p_list, act == "select")
                                if c.state() == QLocalSocket.LocalSocketState.ConnectedState:
                                    c.write(b"OK\n")
                                    c.flush()
                                    if c.state() == QLocalSocket.LocalSocketState.ConnectedState:
                                        c.waitForBytesWritten(100)
                            except Exception:
                                pass
                            finally:
                                c.deleteLater()
                        client.readyRead.connect(_read_client)
            ipc_server.newConnection.connect(_on_new_ipc_conn)

    if is_picker_launch:
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
        if args.select and os.path.exists(first_p):
            parent_d = os.path.dirname(first_p)
            if os.path.isdir(parent_d):
                backend.navigateTo(parent_d)
                backend.selectMultiplePaths(cleaned_paths)
        elif os.path.isdir(first_p) or first_p in ("recent://", "trash://", "favorites://", "mediahub://") or first_p.startswith("analyzer://"):
            backend.navigateTo(first_p)
            for extra_p in cleaned_paths[1:]:
                if os.path.isdir(extra_p) or extra_p in ("recent://", "trash://", "favorites://", "mediahub://") or extra_p.startswith("analyzer://"):
                    backend.addTab(extra_p)
        elif os.path.exists(first_p):
            parent_d = os.path.dirname(first_p)
            if os.path.isdir(parent_d):
                backend.navigateTo(parent_d)
                backend.selectMultiplePaths(cleaned_paths)

    app.setQuitOnLastWindowClosed(is_mediahub_launch or is_picker_launch)
    wheel_filter = FastWheelInterceptor(backend, app)
    app.installEventFilter(wheel_filter)

    engine.rootContext().setContextProperty("backend", backend)

    qml_dir = Path(__file__).resolve().parent / "ui"
    engine.addImportPath(str(qml_dir))
    target_qml = qml_dir / ("MediaHubWindow.qml" if is_mediahub_launch else "main.qml")
    engine.load(QUrl.fromLocalFile(str(target_qml)))
    if is_mediahub_launch:
        backend.navigateTo("mediahub://")

    if not engine.rootObjects():
        sys.exit(-1)

    exit_code = app.exec()
    if ipc_server is not None:
        ipc_server.close()
        QLocalServer.removeServer(_get_ipc_server_name())
    backend.shutdownCleanup()
    del engine
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
