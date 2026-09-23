import http.server
import json
import os
import pathlib
import shutil
import subprocess
import threading
import time

ROOT = pathlib.Path('/data/user/0/com.vibekits.vibekits/files/Vibekits/workspace/whac-a-mole')
OUT = pathlib.Path('/data/local/tmp/vibekits-whac-build')
PREFIX = '/data/data/com.termux/files/usr'
ENV = dict(os.environ, HOME='/data/data/com.termux/files/home', PREFIX=PREFIX,
           PATH=f'{PREFIX}/bin:/system/bin', JAVA_HOME=f'{PREFIX}/lib/jvm/java-21-openjdk')
STATE = {'phase': 'idle', 'steps': [], 'error': None, 'apk': None}
LOCK = threading.Lock()

def step(name, command, cwd=None):
    with LOCK:
        STATE['phase'] = name
    proc = subprocess.run(command, cwd=cwd, env=ENV, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, timeout=120)
    with LOCK:
        STATE['steps'].append({'name': name, 'exitCode': proc.returncode,
                               'output': proc.stdout[-4000:]})
    if proc.returncode:
        raise RuntimeError(f'{name}: {proc.stdout[-1500:]}')

def build():
    try:
        manifest = ROOT / 'app/src/main/AndroidManifest.xml'
        source = ROOT / 'app/src/main/java/com/vibekits/whacdemo/WhacActivity.java'
        icon = ROOT / 'app/src/main/res/drawable/ic_launcher.xml'
        if not all(p.is_file() for p in (manifest, source, icon)):
            raise RuntimeError('PAD Harness game source files missing')
        OUT.mkdir(parents=True, exist_ok=True)
        gen = OUT / 'gen'; gen.mkdir(exist_ok=True)
        classes = OUT / 'classes'; classes.mkdir(exist_ok=True)
        resources = OUT / 'res'
        if resources.exists(): shutil.rmtree(resources)
        shutil.copytree(ROOT / 'app/src/main/res', resources)
        designed_icon = ROOT / 'icon-src/ic_launcher.layerlist.xml'
        if designed_icon.is_file():
            shutil.copy2(designed_icon, resources / 'drawable/ic_launcher.xml')
        android_jar = '/data/local/tmp/pad63-android-35.jar'
        unsigned = OUT / 'unsigned.apk'
        step('compile_resources', [f'{PREFIX}/bin/aapt', 'package', '-f', '-m', '-J', str(gen),
              '-M', str(manifest), '-S', str(resources), '-I', android_jar,
              '-F', str(unsigned)])
        step('compile_java', [f'{PREFIX}/bin/javac', '-source', '8', '-target', '8',
              '-cp', android_jar, '-d', str(classes), str(source)])
        step('create_dex', [f'{PREFIX}/bin/dx', '--dex', f'--output={OUT / "classes.dex"}',
              str(classes)])
        step('package_dex', [f'{PREFIX}/bin/aapt', 'add', str(unsigned), 'classes.dex'], cwd=OUT)
        key = OUT / 'whac-debug.jks'
        if not key.exists():
            step('create_test_key', [f'{PREFIX}/bin/keytool', '-genkeypair', '-noprompt',
                  '-alias', 'whac-test', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '365',
                  '-dname', 'CN=PAD63 Whac Test', '-keystore', str(key),
                  '-storepass', 'pad63testonly', '-keypass', 'pad63testonly'])
        apk = OUT / 'whac-a-mole.apk'
        step('sign_apk', [f'{PREFIX}/bin/apksigner', 'sign', '--ks', str(key),
              '--ks-pass', 'pass:pad63testonly', '--key-pass', 'pass:pad63testonly',
              '--out', str(apk), str(unsigned)])
        step('verify_apk', [f'{PREFIX}/bin/apksigner', 'verify', '--verbose', str(apk)])
        step('install_apk', ['/system/bin/pm', 'install', '-r', str(apk)])
        step('launch_game', ['/system/bin/am', 'start', '--display', '2', '-n',
              'com.vibekits.whacdemo/.WhacActivity'])
        with LOCK:
            STATE.update(phase='completed', apk=str(apk))
    except Exception as exc:
        with LOCK:
            STATE.update(phase='failed', error=str(exc))

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != '/status':
            self.send_error(404); return
        with LOCK:
            body = json.dumps(STATE, ensure_ascii=False).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers(); self.wfile.write(body)

    def do_POST(self):
        if self.path != '/build':
            self.send_error(404); return
        with LOCK:
            if STATE['phase'] not in ('idle', 'failed', 'completed'):
                self.send_error(409); return
            STATE.update(phase='queued', steps=[], error=None, apk=None)
        threading.Thread(target=build, daemon=True).start()
        self.send_response(202); self.end_headers(); self.wfile.write(b'queued')

    def log_message(self, *args):
        pass

http.server.ThreadingHTTPServer(('127.0.0.1', 18473), Handler).serve_forever()
