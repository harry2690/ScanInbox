#!/usr/bin/env python3
"""SharpScanner：依來源 IPv4 分流的上傳接收核心。"""
import argparse
import atexit
import ipaddress
import json
import logging
from logging.handlers import RotatingFileHandler
import os
from pathlib import Path
import signal
import sqlite3
import sys
import time
import uuid
from pyftpdlib.authorizers import DummyAuthorizer
from pyftpdlib.filesystems import AbstractedFS
from pyftpdlib.handlers import FTPHandler
from pyftpdlib.servers import FTPServer


def emit(kind, **fields):
    print(json.dumps(dict(type=kind, **fields), ensure_ascii=False), flush=True)


class History:
    def __init__(self, directory):
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.db = sqlite3.connect(directory / "history.sqlite3")
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("CREATE TABLE IF NOT EXISTS scans (id TEXT PRIMARY KEY, time REAL NOT NULL, data TEXT NOT NULL)")
        self.db.execute("CREATE INDEX IF NOT EXISTS scan_time ON scans(time)")
        self.db.commit()

    def add(self, printer, file, size, status, error=""):
        record = dict(id=str(uuid.uuid4()), printerID=printer["id"], alias=printer["alias"],
                      ip=printer["ip"], path=str(file), size=size, status=status,
                      time=time.time(), error=error)
        with self.db:
            self.db.execute("INSERT INTO scans VALUES (?, ?, ?)", (record["id"], record["time"], json.dumps(record, ensure_ascii=False)))
        emit("record", record=record)
        return record

    def read(self, days):
        if days > 0:
            with self.db:
                self.db.execute("DELETE FROM scans WHERE time < ?", (time.time() - days * 86400,))
        return [json.loads(row[0]) for row in self.db.execute("SELECT data FROM scans ORDER BY time DESC LIMIT 5000")]


def load_config(path, state_dir):
    data = json.loads(Path(path).read_text())
    port = data.get("port", 4687)
    if type(port) is not int or not 1024 <= port <= 65535 or 50000 <= port <= 50009:
        raise ValueError("接收連接埠必須為 1024–65535，並避開 50000–50009")
    routes = {}
    seen = set()
    ids = set()
    for printer in data["printers"]:
        address = str(ipaddress.IPv4Address(printer["ip"]))
        if address == "0.0.0.0" or address in seen or printer["id"] in ids:
            raise ValueError("印表機 IP 與識別碼不可重複或使用 0.0.0.0")
        seen.add(address)
        ids.add(printer["id"])
        if not printer["alias"].strip():
            raise ValueError("印表機別名不可空白")
        root = Path(printer["directory"]).expanduser().resolve()
        state = state_dir.resolve()
        if root in (Path("/"), Path.home()) or state == root or state.is_relative_to(root) or root.is_relative_to(state):
            raise ValueError("輸出資料夾必須獨立於家目錄根層與程式資料目錄")
        if not printer["enabled"]:
            continue
        root.mkdir(parents=True, exist_ok=True, mode=0o700)
        auth = DummyAuthorizer()
        auth.add_anonymous(str(root), perm="ew")
        routes[address] = dict(printer=printer, authorizer=auth)
    return data, routes


class UploadFS(AbstractedFS):
    def open(self, filename, mode):
        if mode != "wb":
            raise PermissionError("Only new uploads allowed")
        def opener(path, flags):
            return os.open(path, flags | getattr(os, "O_NOFOLLOW", 0), 0o600)
        return open(filename, "xb", opener=opener)


def make_handler(routes, history, diagnostic=False):
    class Receiver(FTPHandler):
        proto_cmds = {key: value.copy() for key, value in FTPHandler.proto_cmds.items()}
        proto_cmds["DELE"]["perm"] = "w"
        abstracted_fs = UploadFS
        passive_ports = range(50000, 50010)
        permit_foreign_addresses = False
        permit_privileged_ports = False
        timeout = 120
        banner = "SharpScanner ready"
        printer = None
        transfer_id = None

        def on_connect(self):
            route = routes.get(self.remote_ip)
            if route is None:
                logging.warning("拒絕未知來源 %s", self.remote_ip)
                self.respond("421 Source IP not allowed.")
                self.close_when_done()
                return
            self.printer = route["printer"]
            self.authorizer = route["authorizer"]

        def logline(self, msg, logfun=None):
            if diagnostic:
                raw = msg[3:] if msg.startswith("<- ") else msg
                command, _, argument = raw.partition(" ")
                command = command.upper()
                visible = {"STOR", "DELE", "CWD", "PORT", "EPRT", "TYPE", "MODE", "STRU", "OPTS", "REST"}
                safe = command + (" " + argument if command in visible and argument else "")
                logging.info("FTP 來源=%s 指令=%r", self.remote_ip, safe)

        def respond(self, resp, logfun=None):
            if diagnostic:
                logging.info("FTP 來源=%s 回覆=%r", self.remote_ip, resp)
            return super().respond(resp) if logfun is None else super().respond(resp, logfun)

        def ftp_STOR(self, file, mode="w"):
            if mode != "w":
                self.respond("550 Append not allowed.")
                return
            result = super().ftp_STOR(file, mode)
            if result is not None:
                self.transfer_id = str(uuid.uuid4())
                emit("receiving", printerID=self.printer["id"], transferID=self.transfer_id)
            else:
                history.add(self.printer, file, 0, "failed", "上傳遭拒；請確認檔名、目錄與寫入權限")
            return result

        def finish_transfer(self):
            if self.transfer_id:
                emit("transferEnded", printerID=self.printer["id"], transferID=self.transfer_id)
                self.transfer_id = None

        def ftp_DELE(self, file):
            try:
                os.lstat(file)
            except FileNotFoundError:
                self.respond("250 Target absent; no deletion performed.")
            except OSError:
                self.respond("550 Cannot inspect target.")
            else:
                self.respond("550 Existing targets cannot be deleted.")

        def ftp_APPE(self, file):
            self.respond("550 Append not allowed.")

        def ftp_REST(self, arg):
            self.respond("502 Resume not supported.")

        def ftp_STOU(self, arg):
            self.respond("502 Use STOR.")

        def on_file_received(self, file):
            try:
                history.add(self.printer, file, os.path.getsize(file), "success")
                logging.info("完成來源=%s 檔案=%r", self.remote_ip, file)
            finally:
                self.finish_transfer()

        def on_incomplete_file_received(self, file):
            error = "傳輸中斷，已移除未完成檔案"
            try:
                os.unlink(file)
            except FileNotFoundError:
                pass
            except OSError as exc:
                error = "傳輸中斷，殘檔無法移除：" + str(exc)
            try:
                history.add(self.printer, file, 0, "failed", error)
            finally:
                self.finish_transfer()

        def on_disconnect(self):
            self.finish_transfer()

    return Receiver


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config")
    parser.add_argument("--data-dir", required=True)
    parser.add_argument("--history", action="store_true")
    parser.add_argument("--retention-days", type=int, default=30)
    parser.add_argument("--bind", default="0.0.0.0")
    args = parser.parse_args()
    os.umask(0o077)
    state_dir = Path(args.data_dir).expanduser().resolve()
    history = History(state_dir)
    atexit.register(history.db.close)
    if args.history:
        print(json.dumps(history.read(args.retention_days), ensure_ascii=False))
        return
    if hasattr(os, "geteuid") and os.geteuid() == 0:
        parser.error("請勿以 root 執行")
    try:
        data, routes = load_config(args.config, state_dir)
        if not routes:
            raise ValueError("沒有已啟用的印表機")
        logs = state_dir / "Logs"
        logs.mkdir(exist_ok=True, mode=0o700)
        logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s", handlers=[
            logging.StreamHandler(sys.stderr), RotatingFileHandler(logs / "receiver.log", maxBytes=2_000_000, backupCount=3, encoding="utf-8")])
        server = FTPServer((args.bind, data["port"]), make_handler(routes, history, data.get("diagnostic", False)))
        server.max_cons = 16
        server.max_cons_per_ip = 4
        def stop(signum, frame):
            raise KeyboardInterrupt
        signal.signal(signal.SIGTERM, stop)
        emit("ready", port=data["port"])
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
        finally:
            server.close_all()
            emit("stopped")
    except Exception as exc:
        emit("error", message=str(exc))
        logging.exception("接收端無法運作")
        sys.exit(1)


if __name__ == "__main__":
    main()
