const STORAGE_KEY = "meusPetsApp_v1";
let db = loadDB();
let currentPetId = null;
let currentEntryType = null;
let currentEntryId = null;

const $ = id => document.getElementById(id);
const today = () => new Date().toISOString().slice(0,10);

function loadDB(){
  try { return JSON.parse(localStorage.getItem(STORAGE_KEY)) || {pets:[]}; }
  catch { return {pets:[]}; }
}
function saveDB(){ localStorage.setItem(STORAGE_KEY, JSON.stringify(db)); render(); }
function uid(){ return Date.now().toString(36)+Math.random().toString(36).slice(2,8); }
function escapeHTML(value=""){
  return String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));
}
function formatDate(date){
  if(!date) return "—";
  const [y,m,d] = date.split("-");
  return `${d}/${m}/${y}`;
}
function ageFromBirth(date){
  if(!date) return "—";
  const birth = new Date(date+"T12:00:00"), now = new Date();
  if(birth > now) return "Data inválida";
  let years = now.getFullYear()-birth.getFullYear();
  let months = now.getMonth()-birth.getMonth();
  let days = now.getDate()-birth.getDate();
  if(days < 0) months--;
  if(months < 0){ years--; months += 12; }
  if(years > 0) return `${years} ano${years>1?"s":""}${months?` e ${months} mês${months>1?"es":""}`:""}`;
  if(months > 0) return `${months} mês${months>1?"es":""}${days>0?` e ${days} dia${days>1?"s":""}`:""}`;
  const daysTotal = Math.max(0, Math.floor((now-birth)/86400000));
  return `${daysTotal} dia${daysTotal===1?"":"s"}`;
}
function speciesEmoji(s){
  return ({Gato:"🐱",Cachorro:"🐶",Pássaro:"🐦",Coelho:"🐰"}[s] || "🐾");
}
function statusClass(s){
  return s==="Saudável" ? "status-saude" : s==="Em observação" ? "status-observacao" : "status-tratamento";
}
function showToast(msg){
  const t=$("toast"); t.textContent=msg; t.classList.add("show");
  setTimeout(()=>t.classList.remove("show"),2200);
}
function openModal(id){ $(id).classList.remove("hidden"); }
function closeModal(id){ $(id).classList.add("hidden"); }

function render(){
  const q=$("searchInput").value.trim().toLowerCase();
  const status=$("statusFilter").value;
  const pets=db.pets.filter(p => p.name.toLowerCase().includes(q) && (status==="todos"||p.status===status));
  $("totalPets").textContent=db.pets.length;
  $("totalRecords").textContent=db.pets.reduce((n,p)=>n+(p.health?.length||0)+(p.appointments?.length||0),0);
  const upcoming=db.pets.flatMap(p=>(p.appointments||[]).filter(a=>a.nextDate).map(a=>({date:a.nextDate}))).filter(x=>x.date>=today()).sort((a,b)=>a.date.localeCompare(b.date))[0];
  $("nextAppointment").textContent=upcoming ? formatDate(upcoming.date) : "—";
  $("attentionPets").textContent=db.pets.filter(p=>p.status!=="Saudável").length;

  $("petsGrid").innerHTML=pets.map(petCard).join("");
  $("emptyState").classList.toggle("hidden", pets.length!==0);
}
function petCard(p){
  const last=[...(p.health||[]),...(p.appointments||[])].sort((a,b)=>b.date.localeCompare(a.date))[0];
  return `<article class="pet-card">
    <div class="pet-cover">${p.photo ? `<img src="${escapeHTML(p.photo)}" alt="Foto de ${escapeHTML(p.name)}" onerror="this.style.display='none'">` : speciesEmoji(p.species)}</div>
    <div class="pet-body">
      <div class="pet-title"><div><h3>${escapeHTML(p.name)}</h3><div class="pet-meta">${escapeHTML(p.species)}${p.sex?` • ${escapeHTML(p.sex)}`:""}</div></div><span class="status ${statusClass(p.status)}">${escapeHTML(p.status)}</span></div>
      <div class="card-info">
        <div><span>Nascimento</span><strong>${formatDate(p.birth)}</strong></div>
        <div><span>Idade</span><strong>${ageFromBirth(p.birth)}</strong></div>
        <div><span>Último registro</span><strong>${last?formatDate(last.date):"Nenhum"}</strong></div>
      </div>
      <div class="card-actions">
        <button class="btn btn-primary" onclick="openRecord('${p.id}')">Prontuário</button>
        <button class="btn btn-secondary" onclick="editPet('${p.id}')">Editar</button>
      </div>
    </div>
  </article>`;
}

function resetPetForm(){
  $("petForm").reset(); $("petId").value=""; $("petModalTitle").textContent="Novo pet"; $("petStatus").value="Saudável";
}
function editPet(id){
  const p=db.pets.find(x=>x.id===id); if(!p) return;
  $("petId").value=p.id;$("petName").value=p.name;$("petSpecies").value=p.species;$("petSex").value=p.sex||"";
  $("petBirth").value=p.birth;$("petStatus").value=p.status||"Saudável";$("petPhoto").value=p.photo||"";$("petNotes").value=p.notes||"";
  $("petModalTitle").textContent="Editar pet";openModal("petModal");
}
$("petForm").addEventListener("submit",e=>{
  e.preventDefault();
  const id=$("petId").value;
  const data={name:$("petName").value.trim(),species:$("petSpecies").value,sex:$("petSex").value,birth:$("petBirth").value,status:$("petStatus").value,photo:$("petPhoto").value.trim(),notes:$("petNotes").value.trim()};
  if(id){Object.assign(db.pets.find(p=>p.id===id),data);showToast("Pet atualizado!");}
  else{db.pets.push({id:uid(),...data,health:[],appointments:[]});showToast("Pet cadastrado!");}
  saveDB();closeModal("petModal");
});

function openRecord(id){
  currentPetId=id; renderRecord(); openModal("recordModal");
}
function renderRecord(){
  const p=db.pets.find(x=>x.id===currentPetId); if(!p) return;
  $("recordPetName").textContent=`${speciesEmoji(p.species)} ${p.name}`;
  $("recordPetMeta").textContent=`${p.species}${p.sex?" • "+p.sex:""} • Nascimento: ${formatDate(p.birth)} • ${ageFromBirth(p.birth)}`;
  $("petOverview").innerHTML=`<div class="overview-grid">
    <div class="overview-item"><small>Status</small><strong>${escapeHTML(p.status)}</strong></div>
    <div class="overview-item"><small>Nascimento</small><strong>${formatDate(p.birth)}</strong></div>
    <div class="overview-item"><small>Idade</small><strong>${ageFromBirth(p.birth)}</strong></div>
    <div class="overview-item"><small>Observações</small><strong>${p.notes?escapeHTML(p.notes):"Nenhuma"}</strong></div>
  </div>`;
  const health=[...(p.health||[])].sort((a,b)=>b.date.localeCompare(a.date));
  $("healthList").innerHTML=health.length?health.map(x=>entryHTML(x,"health")).join(""):`<div class="empty-state"><div>🩺</div><h2>Sem ocorrências</h2><p>Registre problemas de saúde, sintomas ou tratamentos.</p></div>`;
  const apps=[...(p.appointments||[])].sort((a,b)=>b.date.localeCompare(a.date));
  $("appointmentsList").innerHTML=apps.length?apps.map(x=>entryHTML(x,"appointment")).join(""):`<div class="empty-state"><div>📅</div><h2>Sem consultas</h2><p>Registre uma consulta realizada ou agendada.</p></div>`;
}
function entryHTML(x,type){
  return `<div class="timeline-item">
    <div class="timeline-top"><span class="timeline-type">${type==="health"?"Saúde":"Consulta"}</span><span class="timeline-date">${formatDate(x.date)}</span></div>
    <h4>${escapeHTML(x.problem||"Consulta veterinária")}</h4>
    ${x.place?`<p><strong>Local/veterinário:</strong> ${escapeHTML(x.place)}</p>`:""}
    ${x.treatment?`<p><strong>Tratamento/conduta:</strong> ${escapeHTML(x.treatment)}</p>`:""}
    ${x.notes?`<p><strong>Observações:</strong> ${escapeHTML(x.notes)}</p>`:""}
    ${x.nextDate?`<span class="next-badge">Próxima data: ${formatDate(x.nextDate)}</span>`:""}
    <div class="timeline-actions"><button class="mini-btn" onclick="editEntry('${type}','${x.id}')">Editar</button><button class="mini-btn" onclick="deleteEntry('${type}','${x.id}')">Excluir</button></div>
  </div>`;
}

function openEntry(type,id=null){
  currentEntryType=type;currentEntryId=id;
  const p=db.pets.find(x=>x.id===currentPetId); let x=id ? (p[type==="health"?"health":"appointments"]||[]).find(e=>e.id===id):null;
  $("entryForm").reset();$("entryType").value=type;$("entryId").value=id||"";$("entryDate").value=x?.date||today();$("entryPlace").value=x?.place||"";
  $("entryProblem").value=x?.problem||"";$("entryTreatment").value=x?.treatment||"";$("entryNotes").value=x?.notes||"";$("entryNextDate").value=x?.nextDate||"";
  $("entryTitle").textContent=id?"Editar registro":(type==="health"?"Nova ocorrência":"Nova consulta");
  $("entryEyebrow").textContent=type==="health"?"SAÚDE":"CONSULTA";
  $("problemLabel").style.display=type==="health"?"grid":"grid";
  $("entryProblem").placeholder=type==="health"?"Ex.: secreção nos olhos":"Ex.: Consulta de rotina";
  openModal("entryModal");
}
$("entryForm").addEventListener("submit",e=>{
  e.preventDefault();
  const p=db.pets.find(x=>x.id===currentPetId); const key=currentEntryType==="health"?"health":"appointments";
  if(!p[key])p[key]=[];
  const data={id:currentEntryId||uid(),date:$("entryDate").value,place:$("entryPlace").value.trim(),problem:$("entryProblem").value.trim(),treatment:$("entryTreatment").value.trim(),notes:$("entryNotes").value.trim(),nextDate:$("entryNextDate").value};
  const i=p[key].findIndex(x=>x.id===data.id); if(i>=0)p[key][i]=data;else p[key].push(data);
  saveDB();renderRecord();closeModal("entryModal");showToast("Registro salvo!");
});
function editEntry(type,id){openEntry(type,id)}
function deleteEntry(type,id){
  if(!confirm("Excluir este registro?"))return;
  const p=db.pets.find(x=>x.id===currentPetId),key=type==="health"?"health":"appointments";
  p[key]=p[key].filter(x=>x.id!==id);saveDB();renderRecord();showToast("Registro excluído.");
}
$("deletePetBtn").addEventListener("click",()=>{
  const p=db.pets.find(x=>x.id===currentPetId);if(!p)return;
  if(confirm(`Excluir o pet "${p.name}" e todo o histórico dele?`)){db.pets=db.pets.filter(x=>x.id!==currentPetId);saveDB();closeModal("recordModal");showToast("Pet excluído.");}
});

document.querySelectorAll("[data-close]").forEach(b=>b.addEventListener("click",()=>closeModal(b.dataset.close)));
document.querySelectorAll(".modal-backdrop").forEach(m=>m.addEventListener("click",e=>{if(e.target===m)closeModal(m.id)}));
document.addEventListener("keydown",e=>{if(e.key==="Escape")document.querySelectorAll(".modal-backdrop:not(.hidden)").forEach(m=>closeModal(m.id))});
$("newPetBtn").onclick=()=>{resetPetForm();openModal("petModal")};
$("emptyNewPet").onclick=()=>{resetPetForm();openModal("petModal")};
$("addHealthBtn").onclick=()=>openEntry("health");
$("addAppointmentBtn").onclick=()=>openEntry("appointment");
$("searchInput").addEventListener("input",render);$("statusFilter").addEventListener("change",render);
document.querySelectorAll(".tab").forEach(tab=>tab.addEventListener("click",()=>{
  document.querySelectorAll(".tab").forEach(x=>x.classList.remove("active"));tab.classList.add("active");
  $("healthTab").classList.toggle("hidden",tab.dataset.tab!=="health");$("appointmentsTab").classList.toggle("hidden",tab.dataset.tab!=="appointments");
}));

$("exportBtn").onclick=()=>{
  const blob=new Blob([JSON.stringify(db,null,2)],{type:"application/json"});
  const a=document.createElement("a");a.href=URL.createObjectURL(blob);a.download=`meus-pets-backup-${today()}.json`;a.click();URL.revokeObjectURL(a.href);showToast("Backup exportado!");
};
$("importInput").addEventListener("change",e=>{
  const file=e.target.files[0];if(!file)return;
  const reader=new FileReader();reader.onload=()=>{
    try{
      const imported=JSON.parse(reader.result);
      if(!imported||!Array.isArray(imported.pets))throw new Error();
      if(confirm("Importar este backup substituirá os dados atuais. Continuar?")){db=imported;saveDB();showToast("Backup importado!");}
    }catch{alert("Arquivo inválido. Selecione um backup JSON gerado por este site.")}
    e.target.value="";
  };reader.readAsText(file);
});

render();
