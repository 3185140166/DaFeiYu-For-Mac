"""Exercise the real Deep Agents graph and JSONL worker against a free local fixture."""
import http.server
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import threading
import time
import unittest
import uuid

ROOT = Path(__file__).resolve().parent.parent
PYTHON = Path.home() / 'Library/Application Support/BaifanYu/AgentRuntime/.venv/bin/python'
WORKER = ROOT / 'AgentRuntime/worker.py'
spec = importlib.util.spec_from_file_location('worker', ROOT / 'AgentRuntime/legacy_worker.py')
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        if self.path == '/redirect/chat/completions':
            self.send_response(302)
            self.send_header('Location', '/v1/chat/completions')
            self.end_headers()
            return
        assert self.path == '/v1/chat/completions', self.path
        messages = body['messages']
        prompt = next(m['content'] for m in messages if m['role'] == 'user')
        tool_result = next((m['content'] for m in reversed(messages) if m['role'] == 'tool'), None)
        if tool_result is None or (prompt in ('BUDGET', 'IGNORE_BUDGET') and (body.get('tools') or prompt == 'IGNORE_BUDGET')):
            if prompt == 'PLAN':
                name, arguments = 'write_todos', {'todos': [
                    {'content': 'Inspect project', 'status': 'in_progress'},
                    {'content': 'Report findings', 'status': 'pending'}]}
            elif prompt in ('READ', 'BUDGET', 'IGNORE_BUDGET'):
                name, arguments = 'workspace_read', {'path': 'hello.txt'}
            elif prompt in ('WRITE', 'REJECT', 'RESUME'):
                name, arguments = 'workspace_write', {'path': prompt.lower()+'.txt', 'content': 'written by agent'}
            elif prompt == 'COMMAND':
                name, arguments = 'run_command', {'command': 'printf agent-command-ok'}
            elif prompt == 'CANCEL':
                name, arguments = 'run_command', {'command': 'sleep 4; printf bad > must-not-exist.txt'}
            elif prompt == 'FAIL':
                self.send_response(401)
                self.end_headers()
                return
            else:
                raise AssertionError(prompt)
            content = {'role': 'assistant', 'content': None, 'tool_calls': [
                {'id': 'call_1', 'type': 'function', 'function': {'name': name, 'arguments': json.dumps(arguments)}}]}
            finish = 'tool_calls'
        else:
            content = {'role': 'assistant', 'content': 'DONE: ' + str(tool_result)}
            finish = 'stop'
        payload = {'id': 'fixture', 'object': 'chat.completion', 'created': 1, 'model': 'mock-agent',
                   'choices': [{'index': 0, 'message': content, 'finish_reason': finish}],
                   'usage': {'prompt_tokens': 50, 'completion_tokens': 10, 'total_tokens': 60}}
        if body.get('stream'):
            self.send_response(200)
            self.send_header('Content-Type', 'text/event-stream')
            self.end_headers()
            def chunk(delta, reason=None):
                event = {'id': 'fixture-stream', 'object': 'chat.completion.chunk', 'created': 1,
                         'model': 'mock-agent', 'choices': [{'index': 0, 'delta': delta, 'finish_reason': reason}]}
                self.wfile.write(('data: '+json.dumps(event)+'\n\n').encode())
                self.wfile.flush()
            chunk({'role': 'assistant', 'reasoning_content': 'INTERNAL_REASONING_MUST_NOT_SHOW'})
            if finish == 'tool_calls':
                calls = content['tool_calls']
                chunk({'tool_calls': [dict(call, index=i) for i, call in enumerate(calls)]})
            else:
                text = content['content']
                for offset in range(0, len(text), 8):
                    chunk({'content': text[offset:offset+8]})
            chunk({}, finish)
            self.wfile.write(b'data: [DONE]\n\n')
            self.wfile.flush()
            return
        encoded = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)


class AgentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.workspace = self.root / 'workspace'
        self.workspace.mkdir()
        (self.workspace / 'hello.txt').write_text('hello from disk')
        self.processes = []

    def tearDown(self):
        for process in self.processes:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)
            process.stdin.close()
            process.stdout.close()
            process.stderr.close()
        self.temp.cleanup()

    def start(self, prompt, state=None, resume=False, endpoint=None):
        state = state or str(uuid.uuid4())
        request = {'id': state, 'state_dir': str(self.root / state), 'workspace': str(self.workspace),
                   'endpoint': endpoint or f'http://127.0.0.1:{self.server.server_port}/v1/chat/completions',
                   'engine': 'deepagents', 'model': 'mock-agent', 'key': 'fixture-secret-do-not-persist', 'prompt': prompt, 'resume': resume}
        process = subprocess.Popen([str(PYTHON), str(WORKER)], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
        self.processes.append(process)
        process.stdin.write(json.dumps(request)+'\n')
        process.stdin.flush()
        return process, state

    def event(self, process, kind, timeout=35):
        deadline = time.monotonic()+timeout
        while time.monotonic() < deadline:
            # TextIO buffers lines; use a reader thread rather than select on its fd.
            result = []
            thread = threading.Thread(target=lambda: result.append(process.stdout.readline()), daemon=True)
            thread.start()
            thread.join(max(0, deadline-time.monotonic()))
            if thread.is_alive():
                self.fail('Timed out waiting for '+kind)
            if not result[0]:
                self.fail('Worker exited: '+process.stderr.read()[-3000:])
            event = json.loads(result[0])
            if event['type'] == 'error' and kind != 'error':
                self.fail(str(event))
            if event['type'] == kind:
                return event
        self.fail('No '+kind)

    def decide(self, process, approve):
        process.stdin.write(json.dumps({'type': 'decision', 'approved': approve})+'\n')
        process.stdin.flush()

    def test_read_and_no_secret_persistence(self):
        process, _ = self.start('READ')
        self.assertIn('hello from disk', self.event(process, 'done')['text'])
        process.wait(timeout=10)
        for path in self.root.rglob('*'):
            if path.is_file():
                self.assertNotIn(b'fixture-secret-do-not-persist', path.read_bytes(), str(path))

    def test_write_requires_approval(self):
        process, _ = self.start('WRITE')
        event = self.event(process, 'approval')
        self.assertEqual(event['actions'][0]['name'], 'workspace_write')
        target = self.workspace / 'write.txt'
        self.assertFalse(target.exists())
        self.decide(process, True)
        self.event(process, 'done')
        self.assertEqual(target.read_text(), 'written by agent')

    def test_reject_write(self):
        process, _ = self.start('REJECT')
        self.event(process, 'approval')
        self.decide(process, False)
        self.event(process, 'done')
        self.assertFalse((self.workspace / 'reject.txt').exists())

    def test_restart_pending_approval(self):
        process, state = self.start('RESUME')
        self.event(process, 'approval')
        process.terminate()
        process.wait(timeout=10)
        process, _ = self.start('RESUME', state=state, resume=True)
        self.event(process, 'approval')
        self.assertFalse((self.workspace / 'resume.txt').exists())
        self.decide(process, True)
        self.event(process, 'done')
        self.assertTrue((self.workspace / 'resume.txt').exists())

    def test_command_approval(self):
        process, _ = self.start('COMMAND')
        self.event(process, 'approval')
        self.decide(process, True)
        self.assertIn('agent-command-ok', self.event(process, 'done')['text'])

    def test_cancel_kills_command_children(self):
        process, _ = self.start('CANCEL')
        self.event(process, 'approval')
        self.decide(process, True)
        # Agent emits status before starting the tool. Let the command enter its sleep.
        self.event(process, 'status')
        time.sleep(0.5)
        process.terminate()
        process.wait(timeout=10)
        time.sleep(4)
        self.assertFalse((self.workspace / 'must-not-exist.txt').exists())

    def test_provider_failure(self):
        process, _ = self.start('FAIL')
        self.assertIn('failed', self.event(process, 'error')['text'])

    def test_redirect_refused(self):
        process, _ = self.start('READ', endpoint=f'http://127.0.0.1:{self.server.server_port}/redirect/chat/completions')
        self.event(process, 'error')

    def test_budget_finishes_with_summary(self):
        process, _ = self.start('BUDGET')
        event = self.event(process, 'done')
        self.assertIn('hello from disk', event['text'])
        process.wait(timeout=10)
        self.assertEqual(process.returncode, 0)

    def test_recursion_limit_has_specific_error(self):
        process, _ = self.start('IGNORE_BUDGET')
        event = self.event(process, 'error')
        self.assertEqual(event.get('code'), 'step_limit')
        self.assertNotIn('connection', event['text'].lower())

    def test_public_plan_updates(self):
        process, _ = self.start('PLAN')
        plan = self.event(process, 'plan')
        self.assertEqual(plan['steps'][0]['content'], 'Inspect project')
        self.assertEqual(plan['steps'][0]['status'], 'in_progress')
        self.event(process, 'done')

    def test_streams_public_reply(self):
        process, _ = self.start('READ')
        activity = self.event(process, 'tool')
        self.assertEqual(activity['name'], 'workspace_read')
        delta = self.event(process, 'reply_delta')
        self.assertTrue(delta['text'])
        self.assertNotIn('INTERNAL_REASONING', delta['text'])
        final = self.event(process, 'done')
        self.assertIn('hello from disk', final['text'])
        self.assertEqual(worker.public_text([
            {'type': 'reasoning', 'text': 'private'}, {'type': 'text', 'text': 'public'},
            {'type': 'tool_call', 'text': 'arguments'}]), 'public')

    def test_file_boundaries(self):
        workspace = worker.Workspace(str(self.workspace))
        outside = self.root / 'outside'
        outside.mkdir()
        (self.workspace / 'escape').symlink_to(outside, target_is_directory=True)
        for path in ('../outside/file', '/etc/passwd', 'escape/file', '.env', '.git/config', 'private.key'):
            with self.assertRaises(ValueError, msg=path):
                workspace.path(path)
        self.assertNotIn('escape/', workspace.listing())
        workspace.write('nested/valid.txt', 'works')
        self.assertIn('works', workspace.read('nested/valid.txt'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
