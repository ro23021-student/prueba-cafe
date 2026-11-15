import json
import os
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import recursos  # noqa: E402


class PromFalso(BaseHTTPRequestHandler):
    def do_GET(self):
        q = parse_qs(urlparse(self.path).query)["query"][0]
        if "api-rust" in q and "cpu_usage" in q:
            vals = [["1", "0.5"], ["2", "1.5"]]
        elif "api-rust" in q and "memory_working_set" in q:
            vals = [["1", str(100 * 1048576)], ["2", str(300 * 1048576)]]
        elif "histogram_quantile" in q:
            vals = [["1", "0.004"], ["2", "NaN"], ["3", "0.012"]]
        else:
            vals = []  # servicios del otro perfil: sin datos
        res = [{"metric": {}, "values": vals}] if vals else []
        body = json.dumps({"status": "success", "data": {"resultType": "matrix", "result": res}}).encode()
        self.send_response(200)
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


def test_resumen_de_recursos_con_prometheus_falso(tmp_path):
    srv = HTTPServer(("127.0.0.1", 0), PromFalso)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    try:
        d = recursos.medir(f"http://127.0.0.1:{srv.server_port}", 0, 10)
    finally:
        srv.shutdown()
    rust = d["servicios"]["api-rust"]
    assert rust["cpu_nucleos"]["media"] == 1.0 and rust["cpu_nucleos"]["pico"] == 1.5
    assert rust["ram_mib"]["pico"] == 300.0
    assert d["servicios"]["postgres"]["cpu_nucleos"] is None  # no activo en este perfil
    assert d["backend_rust_p95_escritura_ms"]["pico"] == 12.0  # NaN se descarta
