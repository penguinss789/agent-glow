"""Run with python3 tests/test_codex_hook.py /path/to/codex-glow; no UI is shown."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

binary = str(Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory(prefix='codex-glow-test-') as home:
    env = dict(os.environ, CODEX_GLOW_HOME=home, CODEX_GLOW_DRY_RUN='1')
    log = Path(home, 'glow.log')

    def hook(event, turn, expected, **fields):
        payload = dict(hook_event_name=event, session_id='session', turn_id=turn, **fields)
        result = subprocess.run([binary, 'hook'], input=json.dumps(payload),
                                text=True, capture_output=True, env=env, check=True)
        assert result.stdout == '{}\n', result.stdout
        classification = [line for line in log.read_text().splitlines()
                          if 'classification ' in line][-1]
        assert f'kind={expected} ' in classification, classification

    hook('Stop', 'startup', 'none', last_assistant_message='/')
    hook('Stop', 'startup-text', 'none', last_assistant_message='ready')
    hook('UserPromptSubmit', 'empty', 'none')
    hook('Stop', 'empty', 'none', last_assistant_message='')
    # An empty Stop must not consume the completion deduplication marker.
    hook('Stop', 'empty', 'done', last_assistant_message='Finished')
    hook('Stop', 'empty', 'none', last_assistant_message='Finished')
    hook('UserPromptSubmit', 'slash', 'none')
    hook('Stop', 'slash', 'none', last_assistant_message='/')
    hook('UserPromptSubmit', 'plan', 'none')
    hook('Stop', 'plan', 'plan', last_assistant_message='<proposed_plan>实现计划</proposed_plan>')
    hook('UserPromptSubmit', 'placeholder', 'none')
    hook('Stop', 'placeholder', 'done', last_assistant_message='<proposed_plan>…</proposed_plan>')
    hook('UserPromptSubmit', 'question', 'none')
    hook('PreToolUse', 'question', 'decision', tool_name='functions.request_user_input', tool_use_id='q')
    hook('Stop', 'question', 'none', last_assistant_message='Waiting')
    hook('PostToolUse', 'question', 'none', tool_name='functions.request_user_input', tool_use_id='q')
    hook('Stop', 'question', 'decision', last_assistant_message='继续？')

    transcript = Path(home, 'transcript.jsonl')
    rows = [
        dict(type='session_meta', payload=dict(id='session')),
        dict(type='turn_context', payload=dict(turn_id='recorded-plan')),
        dict(type='response_item', payload=dict(type='message', role='assistant', phase='final_answer',
             content=[dict(type='output_text', text='<proposed_plan>Plan body</proposed_plan>')])),
        dict(type='event_msg', payload=dict(type='task_complete', last_agent_message='')),
        dict(type='event_msg', payload=dict(type='task_started', turn_id='next-turn')),
        dict(type='response_item', payload=dict(type='message', role='assistant', phase='commentary',
             content=[dict(type='output_text', text='Working')])),
    ]
    transcript.write_text('\n'.join(map(json.dumps, rows)) + '\n{partial')
    hook('Stop', 'recorded-plan', 'plan', last_assistant_message='', transcript_path=str(transcript))
    hook('Stop', 'next-turn', 'none', last_assistant_message='', transcript_path=str(transcript))
    rows[0]['payload']['id'] = 'other-session'
    rows[1]['payload']['turn_id'] = 'wrong-session'
    transcript.write_text('\n'.join(map(json.dumps, rows)))
    hook('Stop', 'wrong-session', 'none', last_assistant_message='', transcript_path=str(transcript))
    hook('UserPromptSubmit', 'missing-file', 'none')
    hook('Stop', 'missing-file', 'none', transcript_path=str(transcript) + '.missing')
print('Passed: startup, empty/slash replies, plan recovery, turn isolation, deduplication, question waits.')
