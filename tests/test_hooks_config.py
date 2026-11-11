"""Configuration merge and uninstall regressions; never access real user settings."""
import copy
import importlib.util
import json
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts' / 'hooks.py'
spec = importlib.util.spec_from_file_location('glow_hooks', SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class HookConfigTests(unittest.TestCase):
    def test_mixed_groups_keep_unrelated_handlers_and_metadata(self):
        other = {'type': 'command', 'command': 'audit --label codex-glow'}
        config = {'theme': 'dark', 'hooks': {'Stop': [
            {'matcher': 'custom', 'hooks': [
                {'type': 'command', 'command': '/old/codex-glow hook'}, other]},
            {'hooks': [{'type': 'command', 'command': '/other/claude-glow hook'}]}]}}
        result = module.updated(copy.deepcopy(config), 'codex', Path('/new/codex-glow'), True)
        self.assertEqual(result['theme'], 'dark')
        self.assertEqual(result['hooks']['Stop'][0], {'matcher': 'custom', 'hooks': [other]})
        self.assertEqual(result['hooks']['Stop'][1], config['hooks']['Stop'][1])
        # Reinstalling changes neither unrelated hooks nor the number of Glow entries.
        self.assertEqual(module.updated(copy.deepcopy(result), 'codex', Path('/new/codex-glow'), True), result)

    def test_spaces_and_shell_metacharacters_are_quoted(self):
        binary = Path("/tmp/a b's $HOME/codex-glow")
        result = module.updated({}, 'codex', binary, True)
        command = result['hooks']['Stop'][0]['hooks'][0]['command']
        self.assertEqual(shlex.split(command), [str(binary), 'hook'])
        self.assertEqual(module.updated(result, 'codex', binary, False), {})

    def test_legacy_environment_prefix_and_uninstall(self):
        config = {'extra': True, 'hooks': {'Stop': [{'hooks': [
            {'command': 'CLAUDE_GLOW_ALWAYS=1 /old/claude-glow hook'},
            {'command': 'echo claude-glow hook'}]}]}}
        result = module.updated(config, 'claude', Path('/new/claude-glow'), False)
        self.assertEqual(result['hooks']['Stop'][0]['hooks'], [{'command': 'echo claude-glow hook'}])
        self.assertTrue(result['extra'])

    def test_cli_backups_and_invalid_json(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory, 'settings.json')
            original = '{"theme":"dark"}\n'
            config.write_text(original)
            command = [sys.executable, str(SCRIPT), 'install', 'claude', str(config), '/tmp/claude-glow']
            subprocess.run(command, check=True, capture_output=True)
            backups = list(Path(directory).glob('settings.json.bak.*'))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_text(), original)
            self.assertEqual(json.loads(config.read_text())['theme'], 'dark')
            config.write_text('{broken')
            failed = subprocess.run(command, capture_output=True)
            self.assertNotEqual(failed.returncode, 0)
            self.assertEqual(config.read_text(), '{broken')
            self.assertEqual(len(list(Path(directory).glob('settings.json.bak.*'))), 1)

    def test_invalid_hook_structure_is_rejected(self):
        for value in ([], {'hooks': []}, {'hooks': {'Stop': {}}},
                      {'hooks': {'Stop': [{'hooks': 'invalid'}]}}):
            with self.subTest(value=value), self.assertRaises(ValueError):
                module.updated(value, 'codex', Path('/tmp/codex-glow'), True)


if __name__ == '__main__':
    unittest.main()
