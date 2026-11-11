#!/usr/bin/env python3
"""Update only Glow command handlers, preserving other hooks and settings."""
import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import shlex
import shutil
import tempfile


def is_glow(handler, name):
    if not isinstance(handler, dict) or not isinstance(handler.get('command'), str):
        return False
    try:
        words = shlex.split(handler['command'])
    except ValueError:
        return False
    # Older releases allowed environment assignments before the executable.
    while words and '=' in words[0] and not words[0].startswith('/'):
        words.pop(0)
    return bool(words and Path(words[0]).name == name and words[1:] == ['hook'])


def updated(config, target, binary, install):
    if not isinstance(config, dict):
        raise ValueError('configuration must be a JSON object')
    hooks = config.get('hooks', {})
    if not isinstance(hooks, dict):
        raise ValueError("'hooks' must be an object")
    name = target + '-glow'
    for event, groups in list(hooks.items()):
        if not isinstance(groups, list):
            raise ValueError('hook event entries must be arrays')
        kept = []
        for group in groups:
            if not isinstance(group, dict) or not isinstance(group.get('hooks'), list):
                raise ValueError('hook groups must contain a hooks array')
            handlers = group['hooks']
            remaining = [h for h in handlers if not is_glow(h, name)]
            if len(remaining) == len(handlers):
                kept.append(group)
            elif remaining:
                kept.append(dict(group, hooks=remaining))
        if kept:
            hooks[event] = kept
        else:
            hooks.pop(event, None)
    if install:
        events = ({'Stop': None, 'Notification': None,
                   'PreToolUse': 'AskUserQuestion|ExitPlanMode|mcp__ccd_turn__wrap_up'}
                  if target == 'claude' else
                  dict.fromkeys(('PreToolUse', 'PostToolUse', 'PermissionRequest',
                                 'UserPromptSubmit', 'Stop')))
        for event, matcher in events.items():
            group = {'hooks': [{'type': 'command',
                                'command': shlex.quote(str(binary)) + ' hook', 'timeout': 5}]}
            if matcher is not None:
                group['matcher'] = matcher
            hooks.setdefault(event, []).append(group)
    if hooks:
        config['hooks'] = hooks
    else:
        config.pop('hooks', None)
    return config


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('install', 'uninstall', 'check'))
    parser.add_argument('target', choices=('claude', 'codex'))
    parser.add_argument('config', type=Path)
    parser.add_argument('binary', type=Path)
    args = parser.parse_args()
    path = args.config
    config = json.loads(path.read_text(encoding='utf-8')) if path.exists() else {}
    result = updated(config, args.target, args.binary, args.action != 'uninstall')
    if args.action == 'check' or (args.action == 'uninstall' and not path.exists()):
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        backup = path.with_name(path.name + '.bak.' + datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
        shutil.copy2(path, backup)
        print(f'Backup: {backup}')
    fd, temporary = tempfile.mkstemp(prefix='.' + path.name + '.', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as handle:
            json.dump(result, handle, indent=2, ensure_ascii=False)
            handle.write('\n')
        if path.exists():
            os.chmod(temporary, path.stat().st_mode & 0o777)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print(f'Updated: {path}')


if __name__ == '__main__':
    main()
