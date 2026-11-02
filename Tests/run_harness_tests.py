"""Real official Harness runtime + local Messages fixture. Never uses real keys or API credit."""
import http.server
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time
import unittest
import uuid

ROOT = Path(__file__).resolve().parent.parent
PYTHON = Path(os.environ.get('DAFEIYU_TEST_PYTHON', str(Path.home()/'Library/Application Support/BaifanYu/AgentRuntime/.venv/bin/python')))
WORKER = ROOT/'AgentRuntime/worker.py'
SECRET = 'fixture-harness-secret-do-not-persist'
spec = importlib.util.spec_from_file_location('harness_worker', ROOT/'AgentRuntime/harness_worker.py')
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        assert self.path == '/anthropic/v1/messages', self.path
        assert self.headers.get('x-api-key') == SECRET
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        messages = body['messages']
        task = next(b['text'] for m in messages if m['role'] == 'user'
                    for b in m['content'] if b.get('type') == 'text' and b.get('text', '').startswith('TASK:'))[5:]
        results = [b for m in messages if m['role'] == 'user' for b in m['content'] if b.get('type') == 'tool_result']
        calls = [b for m in messages if m['role'] == 'assistant' for b in m['content'] if b.get('type') == 'tool_use']
        if task == 'FAIL':
            self.send_response(401)
            self.end_headers()
            return
        call = None
        if task == 'SEARCH_BOUNDARY' and not results:
            call = ('grep', {'pattern': 'OUTSIDE_MUST_NOT_READ', 'path': '.'})
        elif task in ('READ', 'BOUNDARY', 'SYMLINK', 'SECRET') and not results:
            call = ('read', {'file_path': {'READ': 'hello.txt', 'BOUNDARY': '../outside.txt', 'SYMLINK': 'escape/outside.txt', 'SECRET': '.env'}[task]})
        elif task in ('WRITE', 'REJECT', 'RESUME'):
            if not calls:
                call = ('read', {'file_path': task.lower()+'.txt'})
            elif calls[-1]['name'] == 'read' or (task == 'RESUME' and results[-1].get('is_error')):
                call = ('write', {'file_path': task.lower()+'.txt', 'content': 'written by harness'})
        elif task in ('COMMAND', 'CANCEL', 'ENV', 'PYTHON') and not results:
            command = {'COMMAND': 'printf harness-command-ok', 'CANCEL': 'sleep 4; printf bad > must-not-exist.txt', 'ENV': 'env', 'PYTHON': "python3 -c 'import sys; print(sys.executable)'"}[task]
            call = ('bash', {'description': 'Run the local test command', 'command': command, 'timeoutMs': 20000})
        if call:
            name, args = call
            blocks = [{'type': 'tool_use', 'id': 'call_'+str(len(calls)+1), 'name': name, 'input': args}]
            stop = 'tool_use'
        else:
            result = results[-1].get('content', '') if results else 'hello'
            if isinstance(result, list):
                result = ''.join(b.get('text', '') for b in result)
            blocks = [{'type': 'text', 'text': 'DONE: '+result}]
            stop = 'end_turn'
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.end_headers()
        def send(name, event):
            self.wfile.write(('event: '+name+'\ndata: '+json.dumps(event)+'\n\n').encode())
            self.wfile.flush()
        send('message_start', {'type': 'message_start', 'message': {'id': 'fixture', 'type': 'message', 'role': 'assistant',
            'model': 'deepseek-flash', 'content': [], 'stop_reason': None, 'usage': {'input_tokens': 50, 'output_tokens': 0}}})
        for index, block in enumerate(blocks):
            initial = dict(block)
            if block['type'] == 'text':
                initial['text'] = ''
            else:
                initial['input'] = {}
            send('content_block_start', {'type': 'content_block_start', 'index': index, 'content_block': initial})
            if block['type'] == 'text':
                text = block['text']
                for offset in range(0, len(text), 128):
                    send('content_block_delta', {'type': 'content_block_delta', 'index': index,
                         'delta': {'type': 'text_delta', 'text': text[offset:offset+128]}})
            else:
                send('content_block_delta', {'type': 'content_block_delta', 'index': index,
                     'delta': {'type': 'input_json_delta', 'partial_json': json.dumps(block['input'])}})
            send('content_block_stop', {'type': 'content_block_stop', 'index': index})
        send('message_delta', {'type': 'message_delta', 'delta': {'stop_reason': stop}, 'usage': {'output_tokens': 10}})
        send('message_stop', {'type': 'message_stop'})


class HarnessTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        worker.dsh_command()
        cls.server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.work = self.root/'workspace'
        self.work.mkdir()
        (self.work/'hello.txt').write_text('hello from disk')
        (self.root/'outside.txt').write_text('OUTSIDE_MUST_NOT_READ')
        outside = self.root/'outside';outside.mkdir();(outside/'outside.txt').write_text('OUTSIDE_MUST_NOT_READ')
        (self.work/'escape').symlink_to(outside, target_is_directory=True)
        (self.work/'.env').write_text('SECRET_FILE_MUST_NOT_READ')
        self.processes = []
        self.events = []

    def tearDown(self):
        for process in self.processes:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)
            process.stdin.close(); process.stdout.close(); process.stderr.close()
        self.temp.cleanup()

    def start(self, task, ident=None, resume=False):
        ident = ident or str(uuid.uuid4())
        request = {'id': ident, 'state_dir': str(self.root/ident), 'workspace': str(self.work),
            'endpoint': f'http://127.0.0.1:{self.server.server_port}/v1/chat/completions', 'model': 'deepseek-flash',
            'key': SECRET, 'prompt': 'TASK:'+task, 'engine': 'harness', 'resume': resume}
        p = subprocess.Popen([str(PYTHON), str(WORKER)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, text=True, bufsize=1)
        self.processes.append(p)
        p.stdin.write(json.dumps(request)+'\n'); p.stdin.flush()
        return p, ident

    def event(self, process, kind, timeout=45):
        deadline = time.monotonic()+timeout
        while time.monotonic() < deadline:
            lines = []
            thread = threading.Thread(target=lambda: lines.append(process.stdout.readline()), daemon=True)
            thread.start(); thread.join(max(0, deadline-time.monotonic()))
            if thread.is_alive(): self.fail('Timed out waiting for '+kind)
            if not lines[0]: self.fail('Worker exited: '+process.stderr.read()[-2000:])
            event = json.loads(lines[0]); self.events.append(event)
            if event['type'] == 'error' and kind != 'error': self.fail(str(event))
            if event['type'] == kind: return event
        self.fail('Missing '+kind)

    def decide(self, process, approved):
        process.stdin.write(json.dumps({'type': 'decision', 'approved': approved})+'\n');process.stdin.flush()

    def test_read_and_stream(self):
        p, _ = self.start('READ')
        self.event(p, 'reply_delta')
        self.assertIn('hello from disk', self.event(p, 'done')['text'])
        self.assertTrue(any(e['type'] == 'tool' and e['name'] == 'read' for e in self.events))

    def test_write_approval(self):
        p, _ = self.start('WRITE')
        action = self.event(p, 'approval')['actions'][0]
        self.assertEqual(action['name'], 'write')
        self.assertEqual(action['arguments']['content'], 'written by harness')
        self.assertFalse((self.work/'write.txt').exists())
        self.decide(p, True)
        self.event(p, 'done')
        self.assertEqual((self.work/'write.txt').read_text(), 'written by harness')

    def test_reject_write(self):
        p, _ = self.start('REJECT')
        self.event(p, 'approval');self.decide(p, False);self.event(p, 'done')
        self.assertFalse((self.work/'reject.txt').exists())

    def test_command_approval(self):
        p, _ = self.start('COMMAND')
        self.assertEqual(self.event(p, 'approval')['actions'][0]['name'], 'bash')
        self.decide(p, True)
        self.assertIn('harness-command-ok', self.event(p, 'done')['text'])

    def test_commands_use_the_bridge_python(self):
        p, _ = self.start('PYTHON')
        self.event(p, 'approval'); self.decide(p, True)
        self.assertIn(str(PYTHON.parent), self.event(p, 'done')['text'])

    def test_cancel_command(self):
        p, _ = self.start('CANCEL')
        self.event(p, 'approval'); self.decide(p, True); self.event(p, 'status')
        time.sleep(0.5);p.terminate();p.wait(timeout=10);time.sleep(4)
        self.assertFalse((self.work/'must-not-exist.txt').exists())

    def test_workspace_boundary(self):
        p, _ = self.start('BOUNDARY')
        result = self.event(p, 'done')['text']
        self.assertNotIn('OUTSIDE_MUST_NOT_READ', result)
        self.assertIn('workspace', result.lower())

    def test_symlink_and_secret_boundaries(self):
        for task in ('SYMLINK', 'SECRET'):
            with self.subTest(task=task):
                p, _ = self.start(task)
                result = self.event(p, 'done')['text']
                self.assertNotIn('OUTSIDE_MUST_NOT_READ', result)
                self.assertNotIn('SECRET_FILE_MUST_NOT_READ', result)

    def test_search_does_not_follow_outside_symlinks(self):
        p, _ = self.start('SEARCH_BOUNDARY')
        result = self.event(p, 'done')['text']
        self.assertNotIn('OUTSIDE_MUST_NOT_READ', result)

    def test_no_key_in_environment_or_state(self):
        p, _ = self.start('ENV')
        self.event(p, 'approval'); self.decide(p, True)
        self.assertNotIn(SECRET, self.event(p, 'done')['text'])
        p.wait(timeout=10)
        for file in self.root.rglob('*'):
            if file.is_file(): self.assertNotIn(SECRET.encode(), file.read_bytes(), str(file))

    def test_provider_failure(self):
        p, _ = self.start('FAIL')
        self.assertIn('401', self.event(p, 'error')['text'])

    def test_resume_pending_action(self):
        p, ident = self.start('RESUME')
        self.event(p, 'approval');p.terminate();p.wait(timeout=10)
        p, _ = self.start('RESUME', ident=ident, resume=True)
        self.event(p, 'approval')
        self.assertFalse((self.work/'resume.txt').exists())
        self.decide(p, True);self.event(p, 'done')
        self.assertEqual((self.work/'resume.txt').read_text(), 'written by harness')

    def test_endpoint_mapping(self):
        self.assertEqual(worker.messages_endpoint('https://api.deepseek.com/v1/chat/completions'),
                         'https://api.deepseek.com/anthropic/v1/messages')
        for endpoint in ['https://evil.test/chat/completions', 'https://api.deepseek.com.evil.test/chat/completions']:
            with self.assertRaises(worker.HarnessError): worker.messages_endpoint(endpoint)


if __name__ == '__main__': unittest.main(verbosity=2)
