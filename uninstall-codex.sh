#!/bin/bash
set -euo pipefail
exec bash "$(dirname "$0")/scripts/manage.sh" uninstall codex
