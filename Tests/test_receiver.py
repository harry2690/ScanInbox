import ftplib
import importlib.util
import io
import json
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "Receiver/vendor"))
spec = importlib.util.spec_from_file_location("receiver", ROOT / "Receiver/receiver.py")
receiver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(receiver)


def unused_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class ReceiverTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.state = self.base / "state"
        self.root_a, self.root_b = self.base / "a", self.base / "b"
        self.config = dict(port=unused_port(), diagnostic=True, printers=[
            dict(id="one", alias="一號機", ip="127.0.0.1", directory=str(self.root_a), enabled=True),
            dict(id="two", alias="二號機", ip="127.0.0.2", directory=str(self.root_b), enabled=True)])
        self.config_path = self.base / "settings.json"
        self.process = None
        self.out = self.base / "events.jsonl"
        self.err = self.base / "errors.log"
        self.handles = []

    def tearDown(self):
        if self.process is not None:
            self.process.terminate()
            self.process.wait(timeout=5)
        for f in self.handles:
            f.close()
        self.temp.cleanup()

    def start(self):
        self.config_path.write_text(json.dumps(self.config))
        self.handles = [self.out.open("w"), self.err.open("w")]
        self.process = subprocess.Popen([sys.executable, "-I", str(ROOT / "Receiver/bootstrap.py"), "--config", str(self.config_path), "--data-dir", str(self.state), "--bind", "127.0.0.1"], stdout=self.handles[0], stderr=self.handles[1])
        for _ in range(100):
            if any(e["type"] == "ready" for e in self.events()):
                return
            if self.process.poll() is not None:
                self.fail(self.err.read_text())
            time.sleep(.03)
        self.fail("接收核心啟動逾時")

    def events(self):
        if not self.out.exists():
            return []
        result = []
        for line in self.out.read_text().splitlines():
            try:
                result.append(json.loads(line))
            except json.JSONDecodeError:
                pass
        return result

    def connect(self):
        ftp = ftplib.FTP()
        try:
            ftp.connect("127.0.0.1", self.config["port"], timeout=3)
            ftp.login("anonymous", "PRIVATE_PASSWORD_SENTINEL")
            return ftp
        except Exception:
            ftp.close()
            raise

    def wait_record(self, filename, status):
        for _ in range(100):
            records = [e["record"] for e in self.events() if e["type"] == "record"]
            for r in records:
                if Path(r["path"]).name == filename and r["status"] == status:
                    return r
            time.sleep(.02)
        self.fail("未收到預期結果：" + repr(self.events()))

    def test_passive_active_history_and_permissions(self):
        self.start()
        ftp = self.connect()
        data = b"%PDF-1.4 test only"
        self.assertTrue(ftp.delete("new.pdf").startswith("250"))
        ftp.storbinary("STOR new.pdf", io.BytesIO(data))
        passive = self.wait_record("new.pdf", "success")
        self.assertEqual(passive["size"], len(data))
        self.assertEqual(passive["printerID"], "one")
        self.assertEqual((self.root_a / "new.pdf").read_bytes(), data)
        self.assertFalse((self.root_b / "new.pdf").exists())
        self.assertEqual((self.root_a / "new.pdf").stat().st_mode & 0o777, 0o600)
        for cmd in ["DELE new.pdf", "RETR new.pdf", "LIST", "RNFR new.pdf", "MKD sub", "REST 1", "APPE new.pdf"]:
            with self.assertRaises(ftplib.error_perm, msg=cmd):
                ftp.sendcmd(cmd)
        with self.assertRaises(ftplib.error_perm):
            ftp.storbinary("STOR new.pdf", io.BytesIO(b"overwrite"))
        self.wait_record("new.pdf", "failed")
        self.assertEqual((self.root_a / "new.pdf").read_bytes(), data)
        ftp.set_pasv(False)
        ftp.storbinary("STOR active.pdf", io.BytesIO(data))
        self.wait_record("active.pdf", "success")
        ftp.quit()
        history = subprocess.check_output([sys.executable, "-I", str(ROOT / "Receiver/bootstrap.py"), "--data-dir", str(self.state), "--history"], text=True)
        self.assertEqual(len(json.loads(history)), 3)
        self.assertNotIn("PRIVATE_PASSWORD_SENTINEL", self.err.read_text())
        self.assertNotIn("Traceback", self.err.read_text())
        begins = [e["transferID"] for e in self.events() if e["type"] == "receiving"]
        ends = [e["transferID"] for e in self.events() if e["type"] == "transferEnded"]
        self.assertCountEqual(begins, ends)

    def test_path_boundary_and_symlinks(self):
        self.start()
        ftp = self.connect()
        ftp.storbinary("STOR ../inside.pdf", io.BytesIO(b"inside"))
        self.wait_record("inside.pdf", "success")
        self.assertFalse((self.base / "inside.pdf").exists())
        outside = self.base / "outside.pdf"
        (self.root_a / "link.pdf").symlink_to(outside)
        with self.assertRaises(ftplib.error_perm):
            ftp.storbinary("STOR link.pdf", io.BytesIO(b"escape"))
        self.assertFalse(outside.exists())
        with self.assertRaises(ftplib.error_perm):
            ftp.delete("link.pdf")
        ftp.quit()

    def test_interrupted_upload_cleanup(self):
        self.start()
        ftp = self.connect()
        channel = ftp.transfercmd("STOR partial.pdf")
        channel.sendall(b"incomplete")
        ftp.putcmd("ABOR")
        self.wait_record("partial.pdf", "failed")
        channel.close()
        ftp.close()
        self.assertFalse((self.root_a / "partial.pdf").exists())
        self.assertNotIn("Traceback", self.err.read_text())

    def test_unknown_source_rejected(self):
        self.config["printers"][0]["enabled"] = False
        self.start()
        with self.assertRaises(ftplib.error_temp):
            self.connect()
        self.assertFalse(list(self.root_b.iterdir()))

    def test_route_selection_for_two_printers(self):
        self.config_path.write_text(json.dumps(self.config))
        _, routes = receiver.load_config(self.config_path, self.state)
        handler = receiver.make_handler(routes, None)
        class Session:
            def __init__(self, ip):
                self.remote_ip = ip
        one, two = Session("127.0.0.1"), Session("127.0.0.2")
        handler.on_connect(one)
        handler.on_connect(two)
        self.assertEqual(one.printer["id"], "one")
        self.assertEqual(two.printer["id"], "two")
        self.assertEqual(one.authorizer.get_home_dir("anonymous"), str(self.root_a.resolve()))
        self.assertEqual(two.authorizer.get_home_dir("anonymous"), str(self.root_b.resolve()))
        self.assertIsNot(one.authorizer, two.authorizer)

    def test_config_rejects_duplicate_and_private_state_roots(self):
        self.config["printers"][1]["ip"] = "127.0.0.1"
        self.config_path.write_text(json.dumps(self.config))
        with self.assertRaises(ValueError):
            receiver.load_config(self.config_path, self.state)
        self.config["printers"][1]["ip"] = "127.0.0.2"
        self.config["printers"][0]["directory"] = str(self.base)
        self.config_path.write_text(json.dumps(self.config))
        with self.assertRaises(ValueError):
            receiver.load_config(self.config_path, self.state)

    def test_retention_only_removes_history(self):
        self.state.mkdir()
        h = receiver.History(self.state)
        keep = self.base / "keep.pdf"
        keep.write_bytes(b"keep")
        h.add(self.config["printers"][0], keep, 4, "success")
        with h.db:
            h.db.execute("UPDATE scans SET time = 0")
        self.assertEqual(h.read(30), [])
        self.assertTrue(keep.exists())
        h.db.close()

if __name__ == "__main__":
    unittest.main()
