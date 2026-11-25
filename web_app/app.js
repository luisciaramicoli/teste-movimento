import {steps,edges,angles,framing,Counter,simulatedPose} from './protocol.js';
const $=id=>document.getElementById(id),video=document.querySelector('video'),canvas=document.querySelector('canvas'),ctx=canvas.getContext('2d');
const key='movimento.web.avaliacoes.v1';
let session=null,stage=0,counter=new Counter(),stream,detector,frame=0,start=performance.now(),lastVideo=-1,view='evaluation';
let lastRecord,storageError=false;
const read=()=>{try {const v=JSON.parse(localStorage.getItem(key)||'[]');return Array.isArray(v)?v:[]}catch{return []}};
const number=n=>Number(n).toLocaleString('pt-BR',{maximumFractionDigits:1});
function paint(points,sim){
  const w=canvas.clientWidth,h=canvas.clientHeight;
  if(!w||!h)return;
  const ratio=Math.min(devicePixelRatio,2),width=Math.round(w*ratio),height=Math.round(h*ratio);
  if(canvas.width!==width||canvas.height!==height){canvas.width=width;canvas.height=height}
  ctx.setTransform(ratio,0,0,ratio,0,0);ctx.clearRect(0,0,w,h);
  if(!points)return;
  const aspect=sim?1:video.videoWidth/video.videoHeight;
  const dh=Math.min(h,w/aspect),dw=dh*aspect;
  const xy=p=>[(w-dw)/2+p.x*dw,(h-dh)/2+p.y*dh];
  ctx.lineWidth=sim?5:3;ctx.lineCap='round';
  for(const [a,b] of edges){
    if(!points[a]||!points[b]||points[a].visibility<.25||points[b].visibility<.25)continue;
    ctx.strokeStyle=a%2?'#d5f8ad':'#78d6b6';ctx.beginPath();ctx.moveTo(...xy(points[a]));ctx.lineTo(...xy(points[b]));ctx.stroke();
  }
  if(sim){ctx.strokeStyle='#daf1db';ctx.beginPath();ctx.arc(...xy(points[0]),dh*.043,0,2*Math.PI);ctx.stroke()}
  for (const i of new Set(edges.flat())){const p=points[i];if(!p||p.visibility<.25)continue;ctx.fillStyle='#e9f4c8';ctx.beginPath();ctx.arc(...xy(p),sim?4.5:3.5,0,Math.PI*2);ctx.fill()}
}
function release(){cancelAnimationFrame(frame);stream?.getTracks().forEach(t=>t.stop());stream=null;video.srcObject=null;video.hidden=true;detector?.close();detector=null;lastVideo=-1}
function reset(){
  session=null;release();stage=0;counter=new Counter();start=performance.now();
  $('setup').hidden=false;$('controls').hidden=true;$('step').textContent='Nova avaliação';
  $('instruction').textContent='Realize três repetições de cada movimento. Use a câmera ou explore o protocolo com dados simulados.';
  $('source').textContent='Simulação';$('monitor-title').textContent='Guia de movimento';
  $('status').textContent='';$('angle').textContent='—';$('metric').textContent=steps[0].title;
  $('s0').className='';$('s1').className='';
}
function route(name){
  reset();view=name;
  $('session').hidden=name!=='evaluation';$('records').hidden=name==='evaluation';
  for(const id of ['evaluation','history']){if(id===name)$(id).setAttribute('aria-current','page');else $(id).removeAttribute('aria-current')}
  $('title').textContent=name==='evaluation'?'Avaliação de mobilidade':'Histórico de avaliações';
  if(name==='evaluation') frame=requestAnimationFrame(loop);else history();
}
function setStep(){
  $('step').textContent=steps[stage].title;$('instruction').textContent=steps[stage].instruction;
  $('metric').textContent=stage?'Joelho direito':'Média dos ombros';
  $('count').textContent=session.reps[stage].length+' / 3 repetições';
  $('s0').className=stage===0?'active':'';$('s1').className=stage===1?'active':'';
}
async function begin(mode){
  const code=$('participant').value.trim();
  if(!/^[\p{L}\p{N}][\p{L}\p{N} ._-]{0,31}$/u.test(code)){ $('status').textContent='Informe um código com até 32 caracteres, começando por letra ou número.';return}
  reset();
  const current=session={code,mode,date:new Date().toISOString(),reps:[[],[]]};
  $('setup').hidden=true;$('controls').hidden=false;$('source').textContent=mode==='demo'?'Dados simulados':'Câmera';
  $('monitor-title').textContent='Captura de movimento';setStep();
  if(mode==='camera'){
    try{
      $('status').textContent='Aguardando permissão para usar a câmera…';
      const acquired=await navigator.mediaDevices.getUserMedia({audio:false,video:{facingMode:'user',width:{ideal:960},height:{ideal:720}}});
      if(session!==current){acquired.getTracks().forEach(t=>t.stop());return}
      stream=acquired;video.srcObject=stream;await video.play();if(session!==current)return;
      video.hidden=false;$('status').textContent='Carregando o detector de pose…';
      const {FilesetResolver,PoseLandmarker}=await import('@mediapipe/tasks-vision');
      if(session!==current)return;
      const wasm=await FilesetResolver.forVisionTasks('/wasm');
      if(session!==current)return;
      const loaded=await PoseLandmarker.createFromOptions(wasm,{baseOptions:{modelAssetPath:'/pose_landmarker_lite.task'},runningMode:'VIDEO',numPoses:1});
      if(session!==current){loaded.close();return}detector=loaded;
    }catch(e){if(session!==current)return;return failure(e)}
  }
  start=performance.now();frame=requestAnimationFrame(loop);
}
function failure(e){
  route('evaluation');
  $('status').textContent=e.name==='NotAllowedError'?'Acesso à câmera negado. Libere a permissão no navegador ou inicie a demonstração.':e.name==='NotFoundError'?'Câmera não encontrada. Conecte uma câmera ou use a demonstração.':'Falha ao iniciar a captura. Verifique a câmera e tente novamente, ou use a demonstração.';
}
function loop(now){
  if(view!=='evaluation')return;
  let p,values,warning='';
  if(!session||session.mode==='demo'){p=simulatedPose(stage,now-start);paint(p,true);values=angles(p,stage)}
  else if(video.readyState>=2 && video.currentTime!==lastVideo){
    lastVideo=video.currentTime;
    try{const result=detector.detectForVideo(video,now);p=result.landmarks[0];warning=framing(p,result.worldLandmarks[0],stage);paint(p,false);
      if(!warning)values=angles(p.map(v=>({...v,x:v.x*video.videoWidth,y:v.y*video.videoHeight})),stage);
    }catch(e){return failure(e)}
  }else{frame=requestAnimationFrame(loop);return}
  if(session){
    $('status').textContent=warning;
    if(warning){counter.peak=null;$('angle').textContent='—'}
    else{
      const driver=stage?values['Joelho direito']:(values['Ombro direito']+values['Ombro esquerdo'])/2;
      $('angle').textContent=Number.isFinite(driver)?number(driver)+'°':'—';
      const rep=counter.update(stage,values,now);
      if(rep){
        session.reps[stage].push(rep);setStep();
        if(session.reps[stage].length===3){
          if(stage===1)return finish();
          stage++;counter=new Counter();start=now;setStep();
        }
      }
    }
  }else $('angle').textContent=number(values['Ombro direito'])+'°';
  frame=requestAnimationFrame(loop);
}
function finish(){
  lastRecord=session;storageError=false;
  try{localStorage.setItem(key,JSON.stringify([session,...read()]))}catch{storageError=true}
  route('history');report(lastRecord);
}
const panel=$('records');
function element(tag,text,parent=panel){const el=document.createElement(tag);el.textContent=text;parent.append(el);return el}
function action(text,fn){const b=element('button',text);b.className='secondary row';b.onclick=fn}
function description(r){return r.code+' · '+(r.mode==='demo'?'Simulação':'Câmera')+' · '+new Date(r.date).toLocaleString('pt-BR')}
function history(){panel.replaceChildren();const records=read();element('h2','Sessões concluídas');if(!records.length)element('p','As avaliações concluídas neste navegador aparecerão aqui.');for(const r of records)action(description(r),()=>report(r))}
function report(r){
  panel.replaceChildren();$('title').textContent='Resumo da avaliação';element('p',description(r));
  if(storageError&&r===lastRecord)element('p','Armazenamento indisponível. Baixe o CSV para guardar a avaliação.');
  const rows=[['data_hora','voluntario','origem','movimento','repeticao','articulacao','angulo_graus']];
  r.reps.forEach((reps,i)=>{
    element('h2',steps[i].title);
    const wrap=element('div','');wrap.className='tablewrap';const table=element('table','',wrap),head=table.insertRow();
    for(const s of ['Articulação','R1','R2','R3','Média'])element('th',s,head);
    for(const joint of new Set(reps.flatMap(Object.keys))){
      const tr=table.insertRow();element('th',joint,tr);const vals=[];
      reps.forEach((rep,j)=>{const n=rep[joint];tr.insertCell().textContent=n==null?'—':number(n)+'°';
        if(n!=null){vals.push(n);rows.push([r.date,r.code,r.mode,steps[i].title,j+1,joint,n.toFixed(1)])}
      });
      const mean=vals.reduce((a,b)=>a+b,0)/vals.length;
      tr.insertCell().textContent=number(mean)+'°';rows.push([r.date,r.code,r.mode,steps[i].title,'media',joint,mean.toFixed(1)]);
    }
  });
  action('Baixar CSV',()=>{const data=rows.map(row=>row.map(cell=>'"'+String(cell).replaceAll('"','""')+'"').join(',')).join('\r\n');
    const url=URL.createObjectURL(new Blob(['\uFEFF',data],{type:'text/csv;charset=utf-8'}));const a=document.createElement('a');a.href=url;a.download='movimento-'+r.code+'.csv';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000)});
  action('Ver histórico',()=>route('history'));
}
$('camera').onclick=()=>begin('camera');$('demo').onclick=()=>begin('demo');
$('stop').onclick=()=>route('evaluation');$('history').onclick=()=>route('history');$('evaluation').onclick=()=>route('evaluation');
window.addEventListener('pagehide',()=>{session=null;release()});
window.addEventListener('pageshow',e=>{if(e.persisted)route('evaluation')});
route('evaluation');
