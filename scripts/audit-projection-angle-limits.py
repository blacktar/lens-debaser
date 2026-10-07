#!/usr/bin/env python3
"""CPU audit of the centered geometry mapping, independent of image sampling."""
import csv, math, sys
from pathlib import Path
angles=[0,1,5,15,35,55,75,82,85,88,89]
root=Path(sys.argv[1]);root.mkdir(parents=True,exist_ok=True)
def mapping(x,y,angle,model,framing,strength,aspect):
 a=math.radians(angle)
 if a==0:return x,y
 qx=(x-.5)*aspect;qy=y-.5
 r=math.hypot(qx,qy)/(.5*math.hypot(aspect,1))
 radius=a if model=='equidistant' else 2*math.tan(a/2)
 theta=r*a if model=='equidistant' else 2*math.atan(r*radius/2)
 norm=(1-framing)*math.tan(a)+framing*radius
 scale=math.tan(theta)/norm/r if r>1e-6 else 1
 return x+strength*(qx*scale/aspect+.5-x),y+strength*(qy*scale+.5-y)
rows=[]
for aspect in [960/540,960/455]:
 for angle in angles:
  for model in ['equidistant','stereographic']:
   for label,f in [('full-frame',0),('balanced',.55),('center-scale',1)]:
    for strength in [1,.2,.45]:
     if strength!=1 and angle not in [1,82,89]:continue
     outside=0;maxdelta=0;count=0
     for j in range(37):
      for i in range(65):
       x=i/64;y=j/36;u,v=mapping(x,y,angle,model,f,strength,aspect)
       assert math.isfinite(u) and math.isfinite(v)
       if angle==0:assert (u,v)==(x,y)
       outside+=u < -1e-8 or v < -1e-8 or u>1+1e-8 or v>1+1e-8
       maxdelta=max(maxdelta,math.hypot(u-x,v-y));count+=1
     # Check radial continuity and monotonicity along a centre-to-corner ray.
     prev=-1;largest_step=0
     for i in range(1001):
      u,v=mapping(.5+.5*i/1000,.5+.5*i/1000,angle,model,f,strength,aspect)
      r=math.hypot((u-.5)*aspect,v-.5)
      assert r>=prev-1e-10,'Non-monotonic centered radial mapping'
      if i:largest_step=max(largest_step,r-prev)
      prev=r
     rows.append([aspect,angle,model,label,strength,outside/count*100,maxdelta,largest_step])
with (root/'mapping-audit.csv').open('w') as f:
 w=csv.writer(f);w.writerow(['aspect','angle_degrees','model','framing','blend','outside_source_percent','max_uv_displacement','max_radial_step_1_over_1000']);w.writerows(rows)
print(f'PASS: {len(rows)} mapping cases finite and radially monotonic; 0 degrees is identity.')
print('Outside-source samples are recorded, not treated as numerical failures. CPU double precision, centered optical axis only; GPU float/render audit remains required.')
