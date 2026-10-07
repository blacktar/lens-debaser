#!/usr/bin/env python3
"""Preserve unchanged released presets while exposing legacy range defects."""
from pathlib import Path
import importlib.util,json,re,subprocess,sys
repo=Path(__file__).resolve().parent.parent
spec=importlib.util.spec_from_file_location('preset_validator',repo/'scripts/validate-preset.py')
validator=importlib.util.module_from_spec(spec);spec.loader.exec_module(validator)
schema=json.loads(validator.DEFAULT_SCHEMA.read_text())
def blocking_errors(errors,unchanged):
 # Only documented numeric-range defects in byte-identical released files are
 # deferred. Syntax, unknown fields, nonfinite and type errors always block.
 return [e for e in errors if not (unchanged and re.fullmatch(r'line \d+: [A-Za-z_][A-Za-z_0-9]*=[^ ]+ is outside [^ ]+\.\.[^ ]+',e))]
def audit():
 rows=[];blocked=[]
 files=sorted((repo/'presets/demonstrations').glob('*.ldbpreset'))+sorted((repo/'presets/cinematic-lenses').glob('*.ldbpreset'))
 released=subprocess.check_output(['git','ls-tree','-r','--name-only','4bd0dd1','--','presets/demonstrations','presets/cinematic-lenses'],cwd=repo,text=True).splitlines()
 for name in released:
  if name.endswith('.ldbpreset') and not (repo/name).is_file():blocked.append(f'Missing released preset: {name}')
 for path in files:
  name=str(path.relative_to(repo))
  baseline=subprocess.run(['git','show','4bd0dd1:'+name],cwd=repo,capture_output=True)
  unchanged=baseline.returncode==0 and baseline.stdout==path.read_bytes()
  errors,warnings=validator.validate(path,schema)
  blockers=blocking_errors(errors,unchanged)
  blocked.extend(f'{name}: {e}' for e in blockers)
  rows.append(dict(preset=name,unchanged_release=unchanged,status='blocked' if blockers else 'legacy range review' if errors else 'valid',issues=errors,warnings=warnings))
 result=dict(baseline='1.69 / 4bd0dd1',preset_count=len(rows),legacy_issue_presets=sum(r['status']=='legacy range review' for r in rows),blocking_errors=blocked,presets=rows)
 return result
if __name__=='__main__':
 result=audit();destination=Path(sys.argv[1]);destination.parent.mkdir(parents=True,exist_ok=True);destination.write_text(json.dumps(result,indent=2)+'\n')
 for message in result['blocking_errors']:print('ERROR:',message)
 print(f"Factory integration audit: {result['preset_count']} presets; {result['legacy_issue_presets']} unchanged released presets flagged for range review; {len(result['blocking_errors'])} blockers.")
 if result['legacy_issue_presets']:print('Legacy issues are retained for the agreed factory review and displayed in the comparison HTML. New/modified presets require strict validation.')
 raise SystemExit(bool(result['blocking_errors']))
