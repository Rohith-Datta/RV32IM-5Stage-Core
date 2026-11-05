from pathlib import Path
import numpy as np
import random,struct
rng=random.Random(20261103)
edge=[0,0x80000000,1,2,0x7fffff,0x800000,0x80800000,0x7f7fffff,0xff7fffff,0x7f800000,0xff800000,0x7fc00000,0x3f800000,0x33800000]
def f(x):return np.frombuffer(struct.pack('<I',x),dtype='<f4')[0]
rows=[]
with np.errstate(all='ignore'):
 for op in [0,4,8,12]:
  pairs=[(a,b) for a in edge for b in edge]+[(rng.getrandbits(32),rng.getrandbits(32)) for _ in range(500)]
  for a,b in pairs:
   x,y=f(a),f(b)
   z={0:np.add,4:np.subtract,8:np.multiply,12:np.divide}[op](x,y,dtype=np.float32)
   bits=0x7fc00000 if np.isnan(z) else struct.unpack('<I',z.tobytes())[0]
   rows.append(f'{op:02x}{a:08x}{b:08x}{bits:08x}\n')
Path('tests/fp_vectors.mem').write_text(''.join(rows))
print(len(rows))
