"""Dispatch new work to DeepSeek Harness; retain old checkpoints for legacy tasks."""
import json
import sys

if __name__ == '__main__':
    if '--check' in sys.argv:
        from harness_worker import check_runtime
        check_runtime()
    else:
        line = sys.stdin.readline()
        if line:
            request = json.loads(line)
            if request.get('engine') == 'deepagents':
                import legacy_worker
                legacy_worker.main(request)
            else:
                from harness_worker import main
                main(request)
