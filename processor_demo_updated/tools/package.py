"""Package the reviewed project, excluding temporary simulation executables."""
from pathlib import Path
import hashlib,json,sys,zipfile
root=Path(__file__).resolve().parents[1]
out=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else root.parent/'processor_demo_verified.zip'
files=sorted(p for p in root.rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.suffix not in ('.vvp','.pyc') and p.name!='MANIFEST_SHA256.json' and p.resolve()!=out)
manifest=root/'MANIFEST_SHA256.json'
manifest.write_text(json.dumps({str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files},indent=2)+'\n')
with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as z:
 for p in files+[manifest]:z.write(p,str(p.relative_to(root)))
with zipfile.ZipFile(out) as z:assert z.testzip() is None
print(f'{out}: {len(files)+1} files, {out.stat().st_size} bytes; ZIP integrity PASS')
