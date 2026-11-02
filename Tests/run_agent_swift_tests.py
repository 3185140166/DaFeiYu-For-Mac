import http.server
from pathlib import Path
import subprocess
import tempfile
import threading
from run_harness_tests import Handler

root = Path(__file__).resolve().parent.parent
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    with tempfile.TemporaryDirectory() as temp:
        binary = str(Path(temp) / 'agent-tests')
        subprocess.run(['swiftc', '-swift-version', '6', '-sdk', subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip(),
                        str(root/'Sources/Agent/AgentTaskStore.swift'), str(root/'Sources/Agent/AgentBubbleGeometry.swift'), str(root/'Sources/Agent/AgentRuntimeInstaller.swift'), str(root/'Tests/AgentTaskTests.swift'), '-o', binary], check=True)
        subprocess.run([binary, f'http://127.0.0.1:{server.server_port}/v1/chat/completions'], check=True, timeout=90)
finally:
    server.shutdown()
