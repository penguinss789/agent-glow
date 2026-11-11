.PHONY: build test clean

build:
	bash scripts/build.sh claude
	bash scripts/build.sh codex

test: build
	python3 -m unittest discover -s tests -p 'test_hooks_config.py'
	python3 tests/test_codex_hook.py build/codex-glow

clean:
	rm -rf build
