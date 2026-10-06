#!/usr/bin/env bash
set -Eeuo pipefail
if [[ ${1:-} == --help ]]; then
    printf 'Usage: tests/check-skill.sh\nDeveloper checks: metadata, local links, source hygiene, shell syntax/lint. Requires Python 3 and ShellCheck.\n'
    exit 0
fi
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
python3 - <<'PY'
from pathlib import Path
import json,re
root=Path.cwd()
skill=(root/'SKILL.md').read_text()
assert skill.startswith('---\n'), 'missing frontmatter'
fm,body=skill[4:].split('\n---\n',1)
keys=re.findall(r'^([a-z_-]+):',fm,re.M)
assert set(keys)=={'name','description'}, 'unexpected platform-specific metadata'
assert re.search(r'^name: xray-dual-node$',fm,re.M)
assert len(skill.splitlines())<=200, 'entrypoint must remain concise'
assert re.fullmatch(r'\d+\.\d+\.\d+(?:-[a-zA-Z0-9.-]+)?\n?',(root/'VERSION').read_text())
state=json.loads((root/'references/upstream-state.json').read_text())
assert state['pinned_tag'] in (root/'versions.env').read_text()
errors=[]
for path in root.rglob('*.md'):
 if '.git' in path.parts:continue
 text=path.read_text()
 for ref in re.findall(r'\[[^\]\n]*\]\(([^)\n]+)\)',text):
  ref=ref.strip('<>').split('#')[0]
  if not ref or re.match(r'^[a-z]+:',ref):continue
  if not (path.parent/ref).exists():errors.append(str(path.relative_to(root))+': missing '+ref)
assert not errors,'\n'.join(errors)
print('[PASS] skill metadata, version and relative references')
PY
while IFS= read -r file; do
    bash -n "$file"
    "$root/$file" --help >/dev/null
done < <(rg --files scripts tools tests -g '*.sh' -g xrayctl)
shellcheck -x scripts/*.sh scripts/xrayctl tools/poc/*.sh tests/*.sh tests/unit/*.sh
git diff --check
printf '[PASS] auxiliary script syntax/help/lint and whitespace\n'
