var fs=require('fs');
var html=fs.readFileSync('dashboard.html','utf8');

// 1. Timeline bar HTML after </header>
var tl='<div id="tlBar" style="position:sticky;top:68px;z-index:49;display:flex;align-items:center;gap:10px;padding:7px 28px;background:color-mix(in srgb,var(--bg-1) 90%,transparent);backdrop-filter:blur(16px);border-bottom:1px solid var(--border)">';
tl+='<button id="tlPlay" onclick="tlToggle()" style="width:30px;height:30px;display:grid;place-items:center;border:1px solid var(--border);border-radius:50%;background:transparent;color:var(--t1);cursor:pointer;font-size:.65rem">▶</button>';
tl+='<button onclick="tlStep(-1)" style="width:24px;height:24px;display:grid;place-items:center;border:1px solid var(--border);border-radius:5px;background:transparent;color:var(--t2);cursor:pointer;font-size:.55rem">◀</button>';
tl+='<span id="tlTime" style="font-family:JetBrains Mono,monospace;font-size:.68rem;color:var(--t2);min-width:40px;text-align:center">0.0h</span>';
tl+='<button onclick="tlStep(1)" style="width:24px;height:24px;display:grid;place-items:center;border:1px solid var(--border);border-radius:5px;background:transparent;color:var(--t2);cursor:pointer;font-size:.55rem">▶</button>';
tl+='<input type="range" id="tlSlider" min="0" max="239" value="0" oninput="tlSeek(this.value)" style="flex:1;height:4px;accent-color:var(--bl);cursor:pointer">';
tl+='<span style="font-family:JetBrains Mono,monospace;font-size:.58rem;color:var(--t3)">24h</span>';
tl+='<span id="tlSpBtns" style="display:flex;gap:1px;padding:1px;border:1px solid var(--border);border-radius:6px;background:rgba(148,163,184,.04)"></span></div>';
tl+='<div id="scrollBar" style="position:fixed;top:0;left:0;height:2px;background:var(--bl);z-index:100;box-shadow:0 0 8px var(--bl);width:0%"></div>';
html=html.replace('</header>\n\n<main class="page-shell"',tl+'\n<main class="page-shell"');

// 2. Speed buttons + timeline JS + cursor + glow + keyboard
var js='\n/* === TIMELINE + CURSOR + GLOW === */\n';
js+='var _tlI=0,_tlD=null,_tlCs=[],_tlP=false,_tlSp=1,_tlTm=null;\n';
js+='Chart.register({id:"tlCur",afterDraw:function(c){if(!_tlD)return;var x=c.scales.x.getPixelForValue(_tlI);if(x<c.chartArea.left||x>c.chartArea.right)return;var ctx=c.ctx,top=c.chartArea.top,bot=c.chartArea.bottom;ctx.save();ctx.strokeStyle="rgba(255,255,255,.35)";ctx.lineWidth=1;ctx.setLineDash([3,5]);ctx.beginPath();ctx.moveTo(x,top);ctx.lineTo(x,bot);ctx.stroke();ctx.setLineDash([]);ctx.fillStyle="rgba(255,255,255,.8)";ctx.beginPath();ctx.arc(x,top,3,0,2*Math.PI);ctx.fill();ctx.restore()}});\n';
js+='function tlToggle(){_tlP=!_tlP;document.getElementById("tlPlay").textContent=_tlP?"⏸":"▶";if(_tlP)tlRun()}\n';
js+='function tlRun(){if(!_tlP)return;_tlI++;if(_tlI>=(_tlD?_tlD.length-1:239))_tlI=0;tlUpd();_tlTm=setTimeout(tlRun,1000/_tlSp)}\n';
js+='function tlSeek(v){_tlI=parseInt(v);tlUpd()}\n';
js+='function tlStep(d){_tlI=Math.max(0,Math.min(_tlD?_tlD.length-1:239,_tlI+d));tlUpd()}\n';
js+='function tlSpeed(v){_tlSp=v;document.querySelectorAll("#tlSpBtns button").forEach(function(b){var m=parseFloat(b.dataset.s)===v;b.style.background=m?"var(--panel-strong)":"transparent";b.style.color=m?"var(--bl)":"var(--t3)"});if(_tlP){clearTimeout(_tlTm);tlRun()}}\n';
js+='function tlUpd(){document.getElementById("tlSlider").value=_tlI;document.getElementById("tlTime").textContent=(_tlI*0.1).toFixed(1)+"h";if(!_tlD)return;var r=_tlD[_tlI];var f=((r["VPP1_Freq_Hz"]||50)+(r["VPP2_Freq_Hz"]||50)+(r["VPP3_Freq_Hz"]||50))/3;document.getElementById("overviewFreq").textContent=f.toFixed(3)+" Hz";document.getElementById("overviewRenewable").textContent=Math.round((r["VPP1_PV_kW"]||0)+(r["VPP1_Wind_kW"]||0)+(r["VPP2_PV_kW"]||0)+(r["VPP2_Wind_kW"]||0)+(r["VPP3_PV_kW"]||0)+(r["VPP3_Wind_kW"]||0))+" kW";document.getElementById("overviewLoad").textContent=Math.round((r["VPP1_Load_kW"]||0)+(r["VPP2_Load_kW"]||0)+(r["VPP3_Load_kW"]||0))+" kW";for(var v=0;v<3;v++)document.getElementById("nodeFreq"+(v+1)).textContent=(r["VPP"+(v+1)+"_Freq_Hz"]||50).toFixed(3)+" Hz";_tlCs.forEach(function(c){c.draw()})}\n';
js+='addEventListener("keydown",function(e){if(e.target.tagName==="INPUT")return;if(e.code==="Space"){e.preventDefault();tlToggle()}if(e.code==="ArrowRight")tlStep(1);if(e.code==="ArrowLeft")tlStep(-1)});\n';
js+='addEventListener("scroll",function(){var h=document.documentElement.scrollHeight-innerHeight;document.getElementById("scrollBar").style.width=h>0?(scrollY/h*100)+"%":"0%"},{passive:true});\n';
js+='addEventListener("DOMContentLoaded",function(){[0.5,1,2,4].forEach(function(v){var b=document.createElement("button");b.textContent=v+"×";b.dataset.s=v;b.onclick=function(){tlSpeed(v)};b.style.cssText="padding:3px 7px;border-radius:4px;border:none;background:"+(v===1?"var(--panel-strong)":"transparent")+";color:"+(v===1?"var(--bl)":"var(--t3)")+";font-size:.57rem;font-family:JetBrains Mono,monospace;cursor:pointer";document.getElementById("tlSpBtns").appendChild(b)});\n';
js+='document.querySelectorAll(".panel").forEach(function(p){var s=document.createElement("div");s.style.cssText="position:absolute;border-radius:50%;pointer-events:none;opacity:0;transition:opacity .4s;background:radial-gradient(circle,rgba(79,140,255,.1),transparent 70%);width:280px;height:280px;transform:translate(-50%,-50%);z-index:1";p.appendChild(s);p.addEventListener("mousemove",function(e){var r=p.getBoundingClientRect();s.style.left=(e.clientX-r.left)+"px";s.style.top=(e.clientY-r.top)+"px"});p.addEventListener("mouseenter",function(){s.style.opacity="1"});p.addEventListener("mouseleave",function(){s.style.opacity="0"})})});\n';
html=html.replace('async function init(){',js+'async function init(){');

// 3. Store data ref + chart refs
html=html.replace('const labels=D.map(r=>(r[TIME]*1).toFixed(1)),fAvg=D.map(r=>C.freq.reduce((s,c)=>s+(r[c]||50),0)/3);','const labels=D.map(r=>(r[TIME]*1).toFixed(1)),fAvg=D.map(r=>C.freq.reduce((s,c)=>s+(r[c]||50),0)/3);_tlD=D;document.getElementById("tlSlider").max=D.length-1;');
html=html.replace('new Chart(fCtx,{type:','var _c0=new Chart(fCtx,{type:');
html=html.replace("ctx.restore()}}]});\n\n    new Chart(document.getElementById('chartCost'),{","ctx.restore()}}]});_tlCs.push(_c0);\n\n    var _c1=new Chart(document.getElementById('chartCost'),{");
html=html.replace("ctx.restore()}}]});\n\n    const skip=Math.max","ctx.restore()}}]});_tlCs.push(_c1);\n\n    const skip=Math.max");
html=html.replace("new Chart(document.getElementById('chartPower'),{","var _c2=new Chart(document.getElementById('chartPower'),{");
html=html.replace("title:{display:true,text:'kW',color:t3}}});\n\n    const socC","title:{display:true,text:'kW',color:t3}}});_tlCs.push(_c2);\n\n    const socC");
html=html.replace("new Chart(document.getElementById('chartSOC'),{","var _c3=new Chart(document.getElementById('chartSOC'),{");
html=html.replace("grid:{color:gridC}}});\n\n    const vppK","grid:{color:gridC}}});_tlCs.push(_c3);\n\n    const vppK");
html=html.replace("new Chart(document.getElementById('chartVPP'),{","var _c4=new Chart(document.getElementById('chartVPP'),{");
html=html.replace("grid:{color:gridC}}});\n\n    const alog","grid:{color:gridC}}});_tlCs.push(_c4);\n\n    const alog");

fs.writeFileSync('dashboard.html',html);
console.log('Patched OK');
