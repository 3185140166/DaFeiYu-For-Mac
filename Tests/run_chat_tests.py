"""Run actual ChatStore against a local SSE fixture; never uses real credentials."""
import http.server
import json
import pathlib
import subprocess
import tempfile
import threading
import time

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        assert body['stream'] is True
        assert body['model'] == 'mock-model'
        assert body['messages'][0]['role'] == 'system'
        if body['messages'][-1]['content'] == 'NEW_SESSION':
            assert len(body['messages']) == 2, 'Other conversation leaked into request'
        assert self.headers.get('Authorization') is None
        if self.path == '/unauthorized':
            self.send_response(401)
            self.end_headers()
            return
        if self.path == '/redirect':
            self.send_response(302)
            self.send_header('Location', '/success')
            self.end_headers()
            return
        is_summary = body['messages'][0]['content'].startswith('Summarize conversation data')
        if is_summary:
            self.server.summary_calls[self.path] = self.server.summary_calls.get(self.path, 0) + 1
            source = json.loads(body['messages'][1]['content'])
            assert 'older_messages' in source
            assert source['older_messages'][-1]['role'] == 'assistant'
            assert body['max_tokens'] == 600
            if self.path == '/summary-roll':
                assert 'MEMORY_OK' in source['previous_summary'], 'Rolling update forgot old memory'
                assert not any('OLD_ONLY' in m['content'] for m in source['older_messages']), 'Re-summarized covered source'

            if self.path in ['/summary-fail', '/summary-oldfail']:
                self.send_response(500)
                self.end_headers()
                return
        elif self.path == '/summary-ok':
            assert self.server.summary_calls.get(self.path, 0) == 1, 'Repeated summary unnecessarily'
            assert any('MEMORY_OK' in m['content'] for m in body['messages']), 'Saved summary missing'
            assert not any('OLD_ONLY' in m['content'] for m in body['messages']), 'Summarized text duplicated'
        elif self.path == '/summary-cancel':
            assert False, 'Chat request sent after cancellation during summary'
        if self.path == '/summary-fail' and not is_summary:
            assert self.server.summary_calls[self.path] == 1, 'Failed compaction retried immediately'
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.end_headers()
        try:
            if is_summary and self.path == '/summary-cancel':
                time.sleep(2)
            parts = ['MEMORY_OK: 用户喜欢简短回答；当前任务是改进桌宠。'] if is_summary else ['你好，', '白饭鱼 🐟']
            for text in parts:
                event = json.dumps({'choices': [{'delta': {'content': text}}]}, ensure_ascii=False)
                self.wfile.write(('data: ' + event + '\n\n').encode())
                self.wfile.flush()
                if self.path == '/slow':
                    time.sleep(2)
            reason = 'length' if is_summary and self.path == '/summary-truncated' else 'stop'
            self.wfile.write(('data: ' + json.dumps({'choices': [{'delta': {}, 'finish_reason': reason}]}) + '\n\n').encode())
            if body.get('stream_options', {}).get('include_usage'):
                self.wfile.write(b'data: {"choices":[],"usage":{"prompt_tokens":100,"completion_tokens":20,"total_tokens":120,"prompt_cache_hit_tokens":50}}\n\n')
            self.wfile.write(b'data: [DONE]\n\n')
        except (BrokenPipeError, ConnectionResetError):
            pass

root = pathlib.Path(__file__).resolve().parent.parent
sdk = subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip()
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
server.summary_calls = {}
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    with tempfile.TemporaryDirectory() as temp:
        binary = str(pathlib.Path(temp) / 'chat-tests')
        subprocess.run(['swiftc', '-swift-version', '6', '-sdk', sdk,
                        str(root / 'Sources/Chat/ChatStore.swift'), str(root / 'Tests/ChatTests.swift'),
                        '-o', binary], check=True)
        subprocess.run([binary, f'http://127.0.0.1:{server.server_port}'], check=True, timeout=30)
finally:
    server.shutdown()
