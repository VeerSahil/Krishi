"""Start the local Krishi backend and open its admin interface (no deployment)."""
import argparse
import importlib.util
import json
from pathlib import Path
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
import webbrowser

ROOT = Path(__file__).resolve().parents[1]
HTTP = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def ready(base_url):
    try:
        with HTTP.open(base_url + "/", timeout=2) as response:
            if json.load(response).get("message") != "Agro AI Backend":
                return False
        with HTTP.open(base_url + "/admin/", timeout=2) as response:
            return response.status == 200 and b"<html" in response.read().lower()
    except (OSError, ValueError, urllib.error.URLError):
        return False


def open_admin(url, no_browser):
    print(f"Admin panel: {url}", flush=True)
    print("Sign in with your existing Firebase admin account.", flush=True)
    if not no_browser:
        try:
            if not webbrowser.open(url):
                print("Open the address above in your browser.", flush=True)
        except webbrowser.Error:
            print("Open the address above in your browser.", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--no-browser", action="store_true")
    parser.add_argument("--check", action="store_true", help="Check readiness without starting or opening anything")
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("port must be between 1 and 65535")
    base_url = f"http://127.0.0.1:{args.port}"
    if ready(base_url):
        print("Krishi backend is already running; reusing it.", flush=True)
        open_admin(base_url + "/admin/", args.no_browser or args.check)
        return 0

    with socket.socket() as connection:
        if connection.connect_ex(("127.0.0.1", args.port)) == 0:
            print(f"Port {args.port} is occupied by another service or an unready backend.")
            print("Try build.bat --port 8001, or inspect the existing server console.")
            return 1

    dependencies = ("uvicorn", "fastapi", "firebase_admin", "google.genai", "dotenv",
                    "pydantic", "sklearn", "pandas", "numpy", "joblib")
    missing = []
    for name in dependencies:
        try:
            if importlib.util.find_spec(name) is None:
                missing.append(name)
        except ModuleNotFoundError:
            missing.append(name)
    if missing:
        print("Missing Python packages: " + ", ".join(missing))
        print(f'Install them using: "{sys.executable}" -m pip install -r "{ROOT / "requirements.txt"}"')
        return 1
    if args.check:
        print("Python dependencies are available. Run build.bat to start the admin panel.")
        return 0

    print("Starting Krishi locally. Keep this window open; Ctrl+C stops this server.", flush=True)
    server = subprocess.Popen(
        [sys.executable, "-m", "uvicorn", "main:app", "--host", "127.0.0.1", "--port", str(args.port)],
        cwd=ROOT,
    )
    try:
        deadline = time.monotonic() + 60
        while not ready(base_url):
            if server.poll() is not None:
                print("The backend could not start. See the error above.", flush=True)
                return server.returncode or 1
            if time.monotonic() >= deadline:
                print("The backend did not become ready within 60 seconds. See the console above.", flush=True)
                return 1
            time.sleep(0.5)
        open_admin(base_url + "/admin/", args.no_browser)
        return server.wait()
    except KeyboardInterrupt:
        print("\nStopping the local Krishi server.", flush=True)
        return 0
    finally:
        if server.poll() is None:
            server.terminate()
            try:
                server.wait(timeout=10)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait()


if __name__ == "__main__":
    raise SystemExit(main())
