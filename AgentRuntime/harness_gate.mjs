import fs from 'node:fs';
import path from 'node:path';

// A normal DSH tools/pre-execute extension: keep the embedding's one-shot review policy.
export default function apply(ctx) {
  const root = fs.realpathSync(process.env.DAFEIYU_WORKSPACE);
  // Use the public approval seam, including desktop releases predating SDK approval RPC.
  ctx.on('approval/request', async req => {
    try {
      const response = await fetch(process.env.DAFEIYU_BRIDGE + '/approval', {
        method: 'POST', signal: req.signal,
        headers: {'content-type': 'application/json', 'x-api-key': process.env.DEEPSEEK_API_KEY},
        body: JSON.stringify({toolName: req.toolName, callId: req.callId, reason: req.reason})
      });
      if (!response.ok) return 'unavailable';
      const result = await response.json();
      return ['allowed-once', 'rejected', 'cancelled'].includes(result.outcome) ? result.outcome : 'unavailable';
    } catch { return req.signal?.aborted ? 'cancelled' : 'unavailable'; }
  });
  const reads = new Set(['read', 'read_image', 'glob', 'grep', 'working_directory', 'todo_write', 'get_goal', 'job_list', 'job_output', 'job_kill', 'list_agents', 'interrupt_agent']);
  function checkFile(value) {
    if (typeof value !== 'string') return;
    if (value.startsWith('~') || /^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(value)) throw new Error('Use a workspace-relative file path');
    const candidate = path.resolve(root, value);
    let parent = candidate;
    while (!fs.existsSync(parent)) {
      const next = path.dirname(parent);
      if (next === parent) break;
      parent = next;
    }
    const actual = path.resolve(fs.realpathSync(parent), path.relative(parent, candidate));
    const relative = path.relative(root, actual);
    if (relative === '..' || relative.startsWith('..' + path.sep) || path.isAbsolute(relative)) {
      throw new Error('Path leaves the selected workspace');
    }
    if ([relative, path.relative(root, candidate)].flatMap(p => p.split(path.sep)).some(p => p === '.git' || p === '.env' || p.startsWith('.env.') || /\.(pem|key)$/i.test(p))) {
      throw new Error('Credential files and .git are excluded');
    }
  }
  ctx.on('tools/pre-execute', async (exec, next) => {
    let args = exec.arguments ?? {};
    if (typeof args === 'string') {
      try { args = JSON.parse(args); }
      catch { return {kind: 'deny', reason: 'Invalid tool arguments'}; }
    }
    if (['read', 'read_image', 'write', 'edit', 'glob', 'grep', 'working_directory'].includes(exec.name)) {
      try {
        checkFile(args.file_path ?? args.path ?? args.cd ?? '.');
        if (exec.name === 'glob') {
          if (String(args.pattern ?? '').split(/[\\/]/).includes('..')) throw new Error('Glob pattern leaves the selected workspace');
          checkFile(String(args.pattern ?? '').split(/[*?\[{}]/, 1)[0] || '.');
        }
      } catch (error) { return {kind: 'deny', reason: error.message}; }
    }
    const decision = await next();
    if (decision.kind !== 'allow' || reads.has(exec.name)) return decision;
    return {kind: 'ask', reason: JSON.stringify({tool: exec.name, arguments: args})};
  });
}
