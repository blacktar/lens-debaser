// Header button adaptation of Amazing Glass, MIT © 2026 Ivan Tomac.
import {Glass,registerBackdrop,backdropChanged} from './vendor/core/index.ts';
import {resolveParams} from './vendor/core/params.ts';
export async function setup(){
 await document.fonts.ready;
 const hero=document.querySelector('.hero');
 const image=new Image();image.src=new URL('images/examples/preset-26-internal-field-edge-fx-iso-after.png',document.baseURI).href;await image.decode();
 const backdrop=document.createElement('canvas');
 Object.assign(backdrop.style,{position:'absolute',inset:'0',width:'100%',height:'100%',pointerEvents:'none',zIndex:'-1'});
 hero.prepend(backdrop);
 const unregisterBackdrop=registerBackdrop(backdrop);
 const elements=[...hero.querySelectorAll('.hero-cta')];
 let enabled=true,variant='lens',overrides={depth:1.34,bezel:.16,dispersion:.30,blur:1.70},buttons=[],resizeFrame=0;
 const params=()=>resolveParams(variant,overrides);
 const states=elements.map(()=>({hover:false,pressed:false}));
 const listeners=[];
 // Keep dimensionless optical settings fixed; scale lengths with button area.
 function scaledParams(el){
  const p={...params()},state=states[elements.indexOf(el)];
  if(state.pressed){p.dispersion=.15;p.blur=1.10;}else if(state.hover){p.blur=9.0;}
  const {width,height}=el.getBoundingClientRect();
  const scale=Math.sqrt(Math.max(1,width)*Math.max(1,height)/(280*72));
  return {...p,blur:p.blur*scale,rimWidth:p.rimWidth*scale,maxBezel:p.maxBezel*scale,
   bezel:p.bezel*scale*72/Math.max(1,Math.min(width,height))};
 }
 function updateButtons(){buttons.forEach((button,i)=>button.setParams(scaledParams(elements[i])));}

 function mount(){
  buttons.forEach(button=>button.destroy());buttons=[];
  if(enabled)buttons=elements.map(el=>new Glass(el,{variant,tone:'light',params:scaledParams(el)}));

 }
 function paintBackdrop(){
  const rect=hero.getBoundingClientRect();
  const dpr=Math.max(1,window.devicePixelRatio||1);
  const width=rect.width,height=rect.height;
  backdrop.width=Math.ceil(width*dpr);backdrop.height=Math.ceil(height*dpr);
  const ctx=backdrop.getContext('2d');ctx.setTransform(dpr,0,0,dpr,0,0);
  ctx.fillStyle='#090b0c';ctx.fillRect(0,0,width,height);
  // Read the actual applied CSS rule; the canvas must never choose a different scale.
  const backgroundSize=getComputedStyle(hero,'::before').backgroundSize.split(',').pop().trim();
  const portrait=backgroundSize==='cover';
  if(portrait){
   // Cover the whole portrait header without stretching, anchored bottom-right.
   const scale=Math.max(width/image.naturalWidth,height/image.naturalHeight);
   const imageWidth=image.naturalWidth*scale,imageHeight=image.naturalHeight*scale;
   ctx.drawImage(image,width-imageWidth,height-imageHeight,imageWidth,imageHeight);
  }else ctx.drawImage(image,-width,-height,width*2,height*2);
  const gradient=ctx.createLinearGradient(0,0,width,0);
  for(const [x,a] of [[0,.94],[.38,.82],[.72,.42],[1,.28]])gradient.addColorStop(x,`rgba(5,8,10,${a})`);
  ctx.fillStyle=gradient;ctx.fillRect(0,0,width,height);
  // Safari can refract registered canvas pixels, not the decorative DOM pseudo-element.
  // Paint that same lettering into the registered scene so it remains visible through glass.
  const lettering=getComputedStyle(hero,'::after');
  const fontSize=parseFloat(lettering.fontSize);
  ctx.font=`${lettering.fontWeight} ${lettering.fontSize} ${lettering.fontFamily}`;
  ctx.fillStyle=lettering.color;
  ctx.textAlign='right';ctx.textBaseline='alphabetic';
  const metrics=ctx.measureText('Ldb');
  const ascent=metrics.fontBoundingBoxAscent??metrics.actualBoundingBoxAscent;
  const descent=metrics.fontBoundingBoxDescent??metrics.actualBoundingBoxDescent;
  const lineHeight=parseFloat(lettering.lineHeight)||fontSize*1.65;
  const bottom=parseFloat(lettering.bottom)||0,right=parseFloat(lettering.right)||0;
  ctx.fillText('Ldb',width-right,height-bottom-lineHeight+(lineHeight-ascent-descent)/2+ascent);
  hero.classList.add('glass-backdrop-ready');
  backdropChanged(backdrop);
 }
 function schedule(){if(!resizeFrame)resizeFrame=requestAnimationFrame(()=>{resizeFrame=0;paintBackdrop();updateButtons();});}
 const observer=new ResizeObserver(schedule);observer.observe(hero);elements.forEach(el=>observer.observe(el));
 elements.forEach((el,i)=>{
  const state=states[i];
  const on=(type,fn)=>{el.addEventListener(type,fn);listeners.push(()=>el.removeEventListener(type,fn));};
  on('pointerenter',e=>{if(e.pointerType!=='touch'){state.hover=true;updateButtons();}});
  on('pointerleave',()=>{state.hover=false;state.pressed=false;updateButtons();});
  on('pointerdown',()=>{state.pressed=true;updateButtons();});
  on('pointerup',()=>{state.pressed=false;updateButtons();});
  on('pointercancel',()=>{state.pressed=false;updateButtons();});
  on('keydown',e=>{if(e.key==='Enter'||e.key===' '){state.pressed=true;updateButtons();}});
  on('keyup',e=>{if(e.key==='Enter'||e.key===' '){state.pressed=false;updateButtons();}});
  on('blur',()=>{state.pressed=false;state.hover=false;updateButtons();});
 });
 paintBackdrop();mount();
 return {
  toggle(){enabled=!enabled;mount();},
  variant(v){variant=v;overrides={};mount();return params();},
  getParams(){return params();},
  setParam(key,value){overrides[key]=Number(value);updateButtons();},
  destroy(){listeners.forEach(remove=>remove());observer.disconnect();cancelAnimationFrame(resizeFrame);buttons.forEach(button=>button.destroy());unregisterBackdrop();backdrop.remove();hero.classList.remove('glass-backdrop-ready');}
 };
}

setup().catch(error=>console.warn('Glass buttons unavailable; links remain usable.',error));
