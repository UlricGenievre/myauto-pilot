#!/usr/bin/env python3
"""Relais de logs pour l'apercu web (developpement uniquement).

L'app web ne peut pas ecrire de fichier local et ses print() ne sortent que
dans la console du navigateur. Lancee avec
--dart-define=DEV_LOG_URL=http://localhost:8091/log, elle envoie ses
evenements (cf. lib/core/debug/dev_log.dart) a ce serveur, qui les ajoute a
.dev-logs/app.log (gitignore) : lisible directement depuis WSL, sans
copier-coller depuis le navigateur.

Usage : python3 scripts/dev_log_server.py [port]   (defaut 8091)
"""
import datetime
import http.server
import pathlib
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8091
LOG_FILE = pathlib.Path(__file__).resolve().parent.parent / ".dev-logs" / "app.log"


class Handler(http.server.BaseHTTPRequestHandler):
    def _cors(self):
        # L'apercu est servi sur un autre port (8090) : origine differente.
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length).decode("utf-8", errors="replace")
        stamp = datetime.datetime.now().isoformat(timespec="seconds")
        LOG_FILE.parent.mkdir(exist_ok=True)
        with LOG_FILE.open("a", encoding="utf-8") as f:
            f.write(f"{stamp} {body}\n")
        self.send_response(204)
        self._cors()
        self.end_headers()

    def log_message(self, *args):
        pass  # pas de bruit sur stdout, tout va dans le fichier


if __name__ == "__main__":
    print(f"Logs de l'app -> {LOG_FILE} (port {PORT})")
    http.server.ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
