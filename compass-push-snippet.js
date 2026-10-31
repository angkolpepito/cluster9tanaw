<script id="cluster-push">
/* PROJECT TANAW bridge — pushes this school's GSA/MPS to the Cluster 9 dashboard.
   Fill the 4 values below (the PSDS gives you the School ID and token). */
(function(){
  var CL={ URL:"https://sukmtblkbnjnvgajgccy.supabase.co", ANON:"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN1a210YmxrYm5qbnZnYWpnY2N5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI1NzYyNDMsImV4cCI6MjEwODE1MjI0M30.diNBw9cyWP_xZ3U3W_12jLM4fWn_Qfp_7mIp5HBIhs0",
           CODE:"YOUR-SCHOOL-ID", TOKEN:"YOUR-PUSH-TOKEN", SY:"2026-2027" };
  if(CL.TOKEN.indexOf("YOUR")===0) return;
  var timer=null, btn=document.createElement("button");
  btn.style.cssText="position:fixed;right:14px;bottom:14px;z-index:9999;background:#1f5a3f;color:#fff;border:0;border-radius:8px;padding:9px 14px;font:600 13px system-ui;display:none;box-shadow:0 2px 8px #0003;cursor:pointer";
  btn.textContent="Send data to Cluster 9"; document.body.appendChild(btn);
  function flat(){
    var g=[],m=[];
    Object.keys(DB.gsa||{}).forEach(function(s){Object.keys(DB.gsa[s]).forEach(function(gr){Object.keys(DB.gsa[s][gr]).forEach(function(t){
      var v=DB.gsa[s][gr][t]; if(v!==""&&v!==null) g.push({subject:s,grade:String(gr),term:t,value:+v}); });});});
    Object.keys(DB.mps||{}).forEach(function(s){Object.keys(DB.mps[s]).forEach(function(gr){Object.keys(DB.mps[s][gr]).forEach(function(t){
      var r=DB.mps[s][gr][t]; if(r.st1===""&&r.st2===""&&r.exam==="") return;
      m.push({subject:s,grade:String(gr),term:t,st1:r.st1===""?null:+r.st1,st2:r.st2===""?null:+r.st2,exam:r.exam===""?null:+r.exam}); });});});
    return {g:g,m:m};
  }
  async function push(manual){
    try{
      var d=flat();
      var r=await fetch(CL.URL+"/rest/v1/rpc/push_compass",{method:"POST",
        headers:{"Content-Type":"application/json",apikey:CL.ANON,Authorization:"Bearer "+CL.ANON},
        body:JSON.stringify({p_code:CL.CODE,p_token:CL.TOKEN,p_sy:CL.SY,p_gsa:d.g,p_mps:d.m})});
      if(!r.ok) throw new Error((await r.json()).message||r.status);
      btn.textContent="Sent to Cluster 9 ✓ "+new Date().toLocaleTimeString();
    }catch(e){ btn.textContent="Cluster 9 send failed"; console.error("TANAW push:",e); if(manual) alert("Could not send: "+e.message); }
  }
  btn.onclick=function(){push(true)};
  setInterval(function(){ btn.style.display=(typeof CURRENT_USER!=="undefined"&&CURRENT_USER&&CURRENT_USER.role==="admin")?"block":"none"; },1500);
  // Auto-send 20 s after COMPASS reloads data (live sync triggers this when teachers save)
  var orig=window.dbLoad; window.dbLoad=async function(){ var x=await orig.apply(this,arguments);
    if(typeof CURRENT_USER!=="undefined"&&CURRENT_USER&&CURRENT_USER.role==="admin"){clearTimeout(timer);timer=setTimeout(function(){push(false)},20000);} return x; };
})();
</script>
