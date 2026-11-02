"""Official DSH SDK stdio bridge. No model key in argv, environment, profiles or logs."""
from __future__ import annotations

import http.server
import json
import os
from pathlib import Path
import secrets
import selectors
import shutil
import signal
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

SECRET = ''
OUTPUT_LOCK = threading.Lock()


class HarnessError(Exception):
    pass


def scrub(value):
    if isinstance(value, str):
        return value.replace(SECRET, '[redacted]') if SECRET else value
    if isinstance(value, list):
        return [scrub(item) for item in value]
    if isinstance(value, dict):
        return {key: scrub(item) for key, item in value.items()}
    return value


def emit(kind, **payload):
    with OUTPUT_LOCK:
        print(json.dumps(scrub({'type': kind, **payload}), ensure_ascii=False), flush=True)


def dsh_command():
    managed = os.environ.get('DAFEIYU_DSH_BIN')
    if managed:
        if Path(managed).is_file() and os.access(managed, os.X_OK):
            return [managed]
        raise HarnessError('已下载的后台不完整，请重新启用工作能力。')
    bundled = Path('/Applications/DeepSeek Harness.app/Contents/Resources/runtime/cli/bin/dsh')
    local = Path.home() / 'Library/Application Support/BaifanYu/AgentRuntime/harness/node_modules/.bin/dsh'
    for path in (bundled, local):
        if path.is_file() and os.access(path, os.X_OK):
            return [str(path)]
    external = shutil.which('dsh')
    if external:
        return [external]
    raise HarnessError('未找到 DeepSeek Harness。请先安装官方 DeepSeek Harness 应用，或点击准备工作能力。')


def check_runtime():
    try:
        command = dsh_command()
        # Help does not run an agent, read the user's DSH home, or access a provider.
        env = {'HOME': str(Path.home()), 'PATH': '/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin',
               'DSH_HOME': str(Path.home() / 'Library/Application Support/BaifanYu/Harness')}
        result = subprocess.run(command + ['--profile', 'sdk', '--help'], env=env,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)
        if result.returncode:
            raise HarnessError('DeepSeek Harness 后台无法启动，请检查安装。')
        emit('ready', engine='harness')
    except Exception:
        emit('error', text='DeepSeek Harness runtime is unavailable.')
        sys.exit(1)


def messages_endpoint(endpoint):
    url = urllib.parse.urlsplit(endpoint)
    if url.username or url.password or url.query or url.fragment:
        raise HarnessError('模型接口地址不能包含凭据或查询参数。')
    if url.scheme == 'https' and url.hostname == 'api.deepseek.com' and url.port in (None, 443):
        return 'https://api.deepseek.com/anthropic/v1/messages'
    if url.scheme == 'http' and url.hostname in ('localhost', '127.0.0.1', '::1'):
        return urllib.parse.urlunsplit((url.scheme, url.netloc, '/anthropic/v1/messages', '', ''))
    raise HarnessError('Harness 工作模式目前需要 DeepSeek 官方连接；请在聊天设置中使用 api.deepseek.com。普通聊天仍支持其他兼容接口。')


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *_args, **_kwargs):
        return None


class ModelBridge(http.server.ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, request):
        self.upstream = messages_endpoint(request['endpoint'])
        self.key = request.get('key', '')
        self.token = secrets.token_urlsafe(32)
        self.cancelled = threading.Event()
        self.last_http_error = None
        self.approvals = []
        self.approval_lock = threading.Lock()
        super().__init__(('127.0.0.1', 0), ModelHandler)


class ModelHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        if self.headers.get('x-api-key') != self.server.token or self.path not in ('/anthropic/v1/messages', '/approval'):
            self.send_error(403)
            return
        length = int(self.headers.get('Content-Length', 0))
        if not 0 < length <= 8_000_000:
            self.send_error(413)
            return
        body = self.rfile.read(length)
        if self.path == '/approval':
            request = json.loads(body)
            name = request.get('toolName', 'operation')
            reason = request.get('reason', '')
            try:
                parsed = json.loads(reason)
                args = parsed.get('arguments', {'description': reason})
            except (ValueError, TypeError):
                args = {'description': reason}
            pending = {'action': {'name': name, 'arguments': args}, 'event': threading.Event(), 'outcome': 'cancelled'}
            with self.server.approval_lock:
                self.server.approvals.append(pending)
                if len(self.server.approvals) == 1:
                    emit('approval', actions=[pending['action']])
            while not pending['event'].wait(0.2):
                if self.server.cancelled.is_set(): break
            try:
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({'outcome': pending['outcome']}).encode())
            except (BrokenPipeError, ConnectionResetError): pass
            return
        headers = {'Content-Type': 'application/json', 'anthropic-version': '2023-06-01'}
        if self.server.key:
            headers['x-api-key'] = self.server.key
        if self.headers.get('anthropic-beta'):
            headers['anthropic-beta'] = self.headers['anthropic-beta']
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
        request = urllib.request.Request(self.server.upstream, data=body, headers=headers, method='POST')
        reply_id = str(uuid.uuid4())
        try:
            with opener.open(request, timeout=120) as response:
                self.send_response(response.status)
                self.send_header('Content-Type', response.headers.get('Content-Type', 'text/event-stream'))
                self.end_headers()
                for line in response:
                    if self.server.cancelled.is_set():
                        break
                    self.wfile.write(line)
                    self.wfile.flush()
                    if line.startswith(b'data:'):
                        try:
                            event = json.loads(line[5:])
                            delta = event.get('delta', {})
                            # Forward only public text. Thinking and signatures never leave the runtime.
                            if event.get('type') == 'content_block_delta' and delta.get('type') == 'text_delta':
                                emit('reply_delta', id=reply_id, text=delta.get('text', ''))
                        except (ValueError, TypeError):
                            pass
        except urllib.error.HTTPError as error:
            self.server.last_http_error = error.code
            self.send_response(error.code)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'type': 'error', 'error': {
                'type': 'api_error', 'message': f'Provider returned HTTP {error.code}'}}).encode())
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception:
            self.server.last_http_error = 502
            try:
                self.send_error(502, 'Model connection failed')
            except OSError:
                pass


def public_text(blocks):
    if not isinstance(blocks, list):
        return ''
    return ''.join(block.get('text', '') for block in blocks
                   if isinstance(block, dict) and block.get('type') == 'text')


class HarnessRun:
    def __init__(self, request):
        self.request = request
        self.process = None
        self.proxy = None
        self.pending = []
        self.calls = {}
        self.last_answer = ''
        self.turn_reason = None
        self.stopped = False

    def stop(self, *_):
        self.stopped = True
        if self.proxy:
            self.proxy.cancelled.set()
        if self.process and self.process.poll() is None:
            # DSH owns native command/job cleanup. Give its signal handler a bounded drain.
            self.process.terminate()
            try:
                self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(self.process.pid, signal.SIGKILL)
                self.process.wait(timeout=2)

    def send(self, message):
        self.process.stdin.write((json.dumps(message) + '\n').encode())
        self.process.stdin.flush()

    def rpc(self, ident, method, params):
        self.send({'jsonrpc': '2.0', 'id': ident, 'method': method, 'params': params})

    def event(self, params):
        if params.get('sessionId') != self.request['id']:
            return
        event = params.get('event', {})
        kind, data = event.get('type'), event.get('data', {})
        if kind == 'tool/call':
            call = data.get('call', data)
            name = call.get('name', call.get('toolName', 'tool'))
            args = call.get('arguments', call.get('input', {}))
            if isinstance(args, str):
                try: args = json.loads(args)
                except ValueError: args = {'raw': args}
            if not isinstance(args, dict): args = {}
            call_id = call.get('id', call.get('callId'))
            if call_id:
                self.calls[call_id] = (name, args)
            emit('tool', name=name, target=str(args.get('file_path', args.get('path', ''))))
            if name == 'todo_write' and isinstance(args.get('todos'), list):
                emit('plan', steps=args['todos'])
            emit('log', text=f'Tool: {name}')
        elif kind == 'tool/result':
            message = data.get('message', {})
            emit('log', text=public_text(message.get('content', []))[:6000])
            emit('progress', phase='reviewing')
        elif kind == 'assistant/message':
            text = public_text(data.get('message', {}).get('content', []))
            if text:
                self.last_answer = text
        elif kind == 'turn/end':
            self.turn_reason = data.get('reason', {}).get('kind')

    def approval(self, frame):
        params = frame.get('params', {})
        name = params.get('toolName', 'operation')
        args = self.calls.get(params.get('callId'), (name, {}))[1]
        reason = params.get('reason', '')
        try:
            parsed = json.loads(reason)
            if isinstance(parsed, dict) and 'arguments' in parsed:
                args = parsed['arguments']
        except (ValueError, TypeError):
            if not args:
                args = {'description': reason}
        self.pending.append((frame['id'], {'name': name, 'arguments': args}))
        # Each native approval is reviewed separately, even when tools are concurrent.
        if len(self.pending) == 1:
            emit('approval', actions=[self.pending[0][1]])

    def decision(self, value):
        if value.get('type') != 'decision' or not isinstance(value.get('approved'), bool):
            return
        with self.proxy.approval_lock:
            if self.proxy.approvals:
                pending = self.proxy.approvals.pop(0)
                pending['outcome'] = 'allowed-once' if value['approved'] else 'rejected'
                pending['event'].set()
                if self.proxy.approvals:
                    emit('approval', actions=[self.proxy.approvals[0]['action']])
                else:
                    emit('status', text='running')
                return
        if not self.pending: return
        ident, _ = self.pending.pop(0)
        self.send({'jsonrpc': '2.0', 'id': ident, 'result': {
            'outcome': 'allowed-once' if value['approved'] else 'rejected'}})
        if self.pending:
            emit('approval', actions=[self.pending[0][1]])
        else:
            emit('status', text='running')

    def run(self):
        workspace = Path(self.request['workspace']).resolve(strict=True)
        if not workspace.is_dir():
            raise HarnessError('请选择可访问的工作文件夹。')
        state = Path(self.request['state_dir']).resolve()
        state.mkdir(parents=True, exist_ok=True, mode=0o700)
        home = state / 'harness'
        home.mkdir(exist_ok=True, mode=0o700)
        os.chmod(state, 0o700)
        self.proxy = ModelBridge(self.request)
        threading.Thread(target=self.proxy.serve_forever, daemon=True).start()
        # Only app-owned composition and ephemeral local proxy coordinates are persisted.
        patch = [
            {'id': 'approval', 'config': {'policy': 'ask'}},
            {'id': 'system-prompt', 'config': {'personaPrefix':
                'You are 大肥鱼 (DaFeiYu), a desktop work assistant powered by DeepSeek Harness. '
                'Use the user\'s language. For a project overview, read the README and a few entry points, '
                'then give an initial useful summary; do not inspect every subpackage. '
                'Report actual work and limitations. Respect rejected operations. '
                'Do not create schedules, goals or subagents unless the task needs them. '
                'Do not use background jobs for work that can finish synchronously.'}},
            {'id': 'tool-plugin-manager', 'disabled': True},
            {'id': 'session-telemetry-otel', 'disabled': True},
            {'insert': [{'id': 'dafeiyu-gate', 'name': str(Path(__file__).with_name('harness_gate.mjs'))}]},
        ]
        patch_file = state / 'harness-patch.json'
        patch_file.write_text(json.dumps(patch), encoding='utf-8')
        os.chmod(patch_file, 0o600)
        env = {'HOME': str(Path.home()), 'PATH': str(Path(sys.executable).parent) + ':/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin',
               'DSH_HOME': str(home), 'DSH_PERMISSION_MODE': 'workspace-write',
               'DAFEIYU_WORKSPACE': str(workspace),
               'DAFEIYU_BRIDGE': f'http://127.0.0.1:{self.proxy.server_port}', 'DSH_MAX_TOKENS_AS_SUCCESS': 'false',
               'DEEPSEEK_BASE_URL': f'http://127.0.0.1:{self.proxy.server_port}/anthropic',
               'DEEPSEEK_API_KEY': self.proxy.token, 'TZ': 'Asia/Shanghai'}
        self.process = subprocess.Popen(dsh_command() + ['--profile', 'sdk', '--patch', str(patch_file)],
            cwd=workspace, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, start_new_session=True)
        signal.signal(signal.SIGTERM, self.stop)
        signal.signal(signal.SIGINT, self.stop)
        emit('status', text='running')
        self.rpc(1, 'initialize', {'cwd': str(workspace), 'provider': 'deepseek-official',
                                 'model': self.request['model'], 'maxTokens': 8192, 'approvalRequests': False})
        selector = selectors.DefaultSelector()
        selector.register(self.process.stdout, selectors.EVENT_READ, 'runtime')
        selector.register(sys.stdin, selectors.EVENT_READ, 'host')
        buffers = {'runtime': b'', 'host': b''}
        started = time.monotonic()
        initialized = False
        try:
            while not self.stopped:
                if time.monotonic() - started > (1800 if initialized else 30):
                    raise HarnessError('工作超时，已停止；已完成的改动会保留。')
                for key, _ in selector.select(timeout=0.25):
                    chunk = os.read(key.fd, 65536)
                    if not chunk:
                        if key.data == 'host':
                            self.stop()
                            return
                        raise HarnessError('Harness 后台意外退出，请检查安装或模型连接。')
                    buffers[key.data] += chunk
                    if len(buffers[key.data]) > 8_000_000:
                        raise HarnessError('Harness 返回的数据过大，任务已停止。')
                    while b'\n' in buffers[key.data]:
                        line, buffers[key.data] = buffers[key.data].split(b'\n', 1)
                        try:
                            frame = json.loads(line)
                        except ValueError:
                            continue
                        if key.data == 'host':
                            self.decision(frame)
                            continue
                        if 'method' in frame:
                            method = frame['method']
                            if method == 'approval/request' and 'id' in frame:
                                self.approval(frame)
                            elif method == 'session.event':
                                self.event(frame.get('params', {}))
                            elif 'id' in frame:
                                # No unsupported request may grant an operation implicitly.
                                self.send({'jsonrpc': '2.0', 'id': frame['id'],
                                           'error': {'code': -32601, 'message': 'Unsupported client request'}})
                            continue
                        if 'error' in frame:
                            code = self.proxy.last_http_error
                            suffix = f'（HTTP {code}）' if code else ''
                            raise HarnessError('Harness 执行失败' + suffix + '。请检查模型连接或展开执行详情。')
                        ident = frame.get('id')
                        if ident == 1:
                            initialized = True
                            if self.request.get('resume'):
                                self.rpc(4, 'session/resume', {'sessionId': self.request['id']})
                            else:
                                self.prompt(self.request['prompt'])
                        elif ident == 4:
                            self.prompt('Continue the previous task. Recheck its state first. Any pending action needs a fresh approval; do not replay previous commands automatically.')
                        elif ident == 2:
                            self.rpc(3, 'session/wait', {'sessionId': self.request['id']})
                        elif ident == 3:
                            if self.turn_reason != 'completed':
                                code = self.proxy.last_http_error
                                suffix = f'（HTTP {code}）' if code else ''
                                raise HarnessError('Harness 未正常完成任务' + suffix + '，已保留执行记录。')
                            if not self.last_answer:
                                raise HarnessError('Harness 没有返回文字回复。')
                            emit('done', text=self.last_answer[:100_000])
                            return
        finally:
            selector.close()
            self.stop()
            self.proxy.shutdown()
            self.proxy.server_close()

    def prompt(self, text):
        self.rpc(2, 'session/prompt', {'sessionId': self.request['id'],
                                     'contentBlocks': [{'type': 'text', 'text': text}]})


def main(request):
    global SECRET
    SECRET = request.get('key', '')
    os.umask(0o077)
    task = HarnessRun(request)
    signal.signal(signal.SIGTERM, task.stop)
    signal.signal(signal.SIGINT, task.stop)
    try:
        if not task.stopped:
            task.run()
    except Exception as error:
        task.stop()
        text = str(error) if isinstance(error, HarnessError) else 'Harness 后台无法完成任务，请检查运行环境。'
        emit('error', text=text)
        sys.exit(1)
