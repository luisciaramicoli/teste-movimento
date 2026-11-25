export const steps = [
  {title:'Abdução de ombro', instruction:'De frente para a câmera, eleve os braços até a altura dos ombros e retorne.'},
  {title:'Agachamento', instruction:'Vire o lado direito para a câmera. Agache até uma profundidade confortável e retorne.'}
];
const joints = [
  ['Ombro', 23,11,13], ['Quadril',11,23,25], ['Joelho',23,25,27], ['Tornozelo',25,27,31]
];
export const edges = [[11,12],[11,23],[12,24],[23,24],[11,13],[13,15],[12,14],[14,16],[23,25],[25,27],[27,31],[24,26],[26,28],[28,32]];
export function angles(points,stage) {
  const result = {};
  for (const [label,a,b,c] of joints) {
    for (const side of stage ? [1] : [0,1]) {
      const [p,q,r] = [a,b,c].map(i=>points[i+side]);
      if (![p,q,r].every(v=>v && (v.visibility??1)>=0.25)) continue;
      const u=[p.x-q.x,p.y-q.y], v=[r.x-q.x,r.y-q.y];
      const norm=Math.hypot(...u)*Math.hypot(...v);
      if (norm>0) result[label+(side?' direito':' esquerdo')]=180/Math.PI*Math.acos(Math.max(-1,Math.min(1,(u[0]*v[0]+u[1]*v[1])/norm)));
    }
  }
  return result;
}
export function framing(points,world,stage) {
  if (!points) return 'Posicione-se em frente à câmera.';
  const needed=stage?[0,12,24,26,28]:[0,11,12,23,24,25,26,27,28];
  const body=needed.map(i=>points[i]);
  if(body.some(p=>!p || p.visibility<.25 || p.x<.02 || p.x>.98 || p.y<.02 || p.y>.98)) return 'Mostre o corpo inteiro, da cabeça aos pés.';
  const ys=body.map(p=>p.y), size=(Math.max(...ys)-Math.min(...ys))/.88;
  if(size<.42) return 'Aproxime-se da câmera.';
  if(size>.92) return 'Afaste-se da câmera.';
  if(Math.abs((points[23].x+points[24].x)/2-.5)>.20) return 'Centralize o quadril na imagem.';
  if(world){
    const l=world[11],r=world[12],yaw=Math.atan2(Math.abs(l.z-r.z),Math.abs(l.x-r.x))*180/Math.PI;
    if(!stage && yaw>38) return 'Fique de frente para a câmera.';
    if(stage && (yaw<48 || r.z>l.z)) return 'Mostre o lado direito para a câmera.';
  }
  return '';
}
export class Counter {
  peak=null;
  update(stage,values,time){
    const driver=stage?values['Joelho direito']:(values['Ombro direito']+values['Ombro esquerdo'])/2;
    if(!Number.isFinite(driver)){this.peak=null;return;}
    if(!this.peak){
      if(stage?driver<=130:driver>=70) this.peak={driver,values,start:time};
      return;
    }
    if(stage?driver<this.peak.driver:driver>this.peak.driver) Object.assign(this.peak,{driver,values});
    if(stage?driver>=155:driver<=45){
      const last=this.peak;this.peak=null;
      if(time-last.start>=500) return last.values;
    }
  }
}
// Coordenadas de uma figura articulada em unidades isotrópicas.
export function simulatedPose(stage,t){
  const k=(1-Math.cos(t*2*Math.PI/2600))/2, p=[];
  const put=(i,x,y)=>{p[i]={x,y,visibility:1}};
  const drop=stage?.117*k:0;
  put(0,.5,.15+drop);
  for(const s of [0,1]){
    const sign=s?-1:1, spread=stage?.028:.084;
    const x=.5+spread*sign, hip=.5+spread*.67*sign, y=.29+drop;
    put(11+s,x,y); put(23+s,hip,.54+drop);
    const a=stage?1.25:k*1.59+.08, dir=stage?-1:sign;
    put(13+s,x+dir*.145*Math.sin(a),y+.145*Math.cos(a));
    put(15+s,x+dir*.275*Math.sin(a),y+.275*Math.cos(a));
    put(25+s,hip-(stage?.14*k:0),.72+drop*.35);
    put(27+s,hip,.91);put(31+s,hip+(stage?-.06:sign*.045),.925);
  }
  return p;
}
