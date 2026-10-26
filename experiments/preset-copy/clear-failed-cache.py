#!/usr/bin/env python3
"""Remove only this test bundle's failed scan record, preserving other cache text."""
from pathlib import Path
import datetime,os,re,shutil,sys,xml.etree.ElementTree as ET
TARGET='/Library/OFX/Plugins/LensDebaserPresetCopyTest.ofx.bundle'
def clear_failed_entry(path):
 if not path.exists():return False
 text=path.read_text();ET.fromstring(text)
 def keep(match):
  node=ET.fromstring(match.group(0));binary=node.find('binary')
  if binary is not None and binary.get('bundle_path')==TARGET and binary.get('status')=='2' and node.find('plugin') is None:return ''
  return match.group(0)
 updated=re.sub(r'<bundle>.*?</bundle>',keep,text,flags=re.S)
 if updated==text:return False
 ET.fromstring(updated)
 stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
 backup=path.with_name(path.name+'.preset-copy-backup-'+stamp);shutil.copy2(path,backup)
 temporary=path.with_name('.'+path.name+'.preset-copy-'+str(os.getpid()))
 try:
  temporary.write_text(updated);os.chmod(temporary,path.stat().st_mode&0o777);os.replace(temporary,path)
 finally:
  if temporary.exists():temporary.unlink()
 print('Removed failed Preset Copy Test scan record from '+path.name+'; backup: '+backup.name)
 return True
if __name__=='__main__':
 directory=Path.home()/'Library/Application Support/Blackmagic Design/DaVinci Resolve'
 for name in ('OFXPluginCache.xml','OFXPluginCacheV2.xml'):clear_failed_entry(directory/name)
