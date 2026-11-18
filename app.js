(() => {
  const cfg = window.STUDIO_CONFIG || {};
  const configured = cfg.SUPABASE_URL && cfg.SUPABASE_ANON_KEY &&
    !cfg.SUPABASE_URL.includes("COLE_AQUI") && !cfg.SUPABASE_ANON_KEY.includes("COLE_AQUI");
  const db = configured && window.supabase ? window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY) : null;
  const $ = s => document.querySelector(s);
  const money = v => Number(v || 0).toLocaleString("pt-BR",{style:"currency",currency:"BRL"});
  const phoneDigits = v => String(v || "").replace(/\D/g,"");
  let services = [], staffMembers = [], selectedSlot = null, settings = {};
  // A vitrine ilustrativa permanece acessível antes da configuração do novo Supabase.
  // Apenas o agendamento real depende do banco e não é simulado.
  const previewServices = [
    {"id": "preview-1", "nome": "Unhas de gel", "descricao": "Modelagem e acabamento em gel.", "preco": 120, "duracao_minutos": 120, "imagem_url": "assets/hero-unhas-rosas.jpg", "categoria": "alongamento"},
    {"id": "preview-2", "nome": "Unhas de fibra", "descricao": "Alongamento em fibra com acabamento personalizado.", "preco": 160, "duracao_minutos": 150, "imagem_url": "assets/alongamento-fibra.jpg", "categoria": "alongamento"},
    {"id": "preview-3", "nome": "Manutenção (gel)", "descricao": "Manutenção das unhas de gel.", "preco": 80, "duracao_minutos": 90, "imagem_url": "assets/aplicacao-gel.jpg", "categoria": "alongamento"},
    {"id": "preview-4", "nome": "Manutenção (fibra)", "descricao": "Manutenção de alongamento em fibra.", "preco": 100, "duracao_minutos": 120, "imagem_url": "assets/francesinha-delicada.jpg", "categoria": "alongamento"},
    {"id": "preview-5", "nome": "Banho de gel", "descricao": "Camada de gel para acabamento e proteção.", "preco": 70, "duracao_minutos": 90, "imagem_url": "assets/aplicacao-gel.jpg", "categoria": "alongamento"},
    {"id": "preview-6", "nome": "Esmaltação em gel", "descricao": "Esmaltação com acabamento em gel.", "preco": 30, "duracao_minutos": 60, "imagem_url": "assets/manicure-rosada.jpg", "categoria": "manicure"},
    {"id": "preview-7", "nome": "Spa dos pés", "descricao": "Cuidado e bem-estar para os pés.", "preco": 90, "duracao_minutos": 90, "imagem_url": "assets/spa-esmaltes.jpg", "categoria": "spa"},
    {"id": "preview-8", "nome": "Pé e mão", "descricao": "Cuidados clássicos para unhas dos pés e das mãos.", "preco": 45, "duracao_minutos": 90, "imagem_url": "assets/manicure-rosada.jpg", "categoria": "manicure"},
    {"id": "preview-9", "nome": "Mão", "descricao": "Manicure tradicional.", "preco": 26, "duracao_minutos": 60, "imagem_url": "assets/francesinha-delicada.jpg", "categoria": "manicure"},
    {"id": "preview-10", "nome": "Pé", "descricao": "Pedicure tradicional.", "preco": 28, "duracao_minutos": 60, "imagem_url": "assets/spa-esmaltes.jpg", "categoria": "manicure"},
    {"id": "preview-11", "nome": "Pé e mão c/ francesinha", "descricao": "Manicure e pedicure com francesinha.", "preco": 50, "duracao_minutos": 90, "imagem_url": "assets/francesinha-delicada.jpg", "categoria": "manicure"},
    {"id": "preview-12", "nome": "Pé c/ francesinha", "descricao": "Pedicure com francesinha.", "preco": 33, "duracao_minutos": 60, "imagem_url": "assets/spa-esmaltes.jpg", "categoria": "manicure"},
    {"id": "preview-13", "nome": "Mão c/ francesinha", "descricao": "Manicure com francesinha.", "preco": 31, "duracao_minutos": 60, "imagem_url": "assets/francesinha-delicada.jpg", "categoria": "manicure"},
    {"id": "preview-14", "nome": "Mão c/ esmaltação em gel", "descricao": "Manicure com esmaltação em gel.", "preco": 50, "duracao_minutos": 60, "imagem_url": "assets/hero-unhas-rosas.jpg", "categoria": "manicure"}
  ];
  const previewGallery = [
    {"titulo": "Unhas delicadas", "categoria": "Unhas em gel", "imagem_url": "assets/hero-unhas-rosas.jpg"},
    {"titulo": "Francesinha e elegância", "categoria": "Manicure", "imagem_url": "assets/francesinha-delicada.jpg"},
    {"titulo": "Aplicação de gel", "categoria": "Unhas em gel", "imagem_url": "assets/aplicacao-gel.jpg"},
    {"titulo": "Ritual de beleza", "categoria": "Inspiração", "imagem_url": "assets/espaco-esmaltes.jpg"},
    {"titulo": "Nude e rose gold", "categoria": "Manicure", "imagem_url": "assets/manicure-rosada.jpg"},
    {"titulo": "Cuidado para os pés", "categoria": "Spa", "imagem_url": "assets/spa-esmaltes.jpg"}
  ];
  let latestSlotsRequest = 0;
  let bookingInProgress = false;
  let previousModalFocus = null;
  function closeSuccessModal(){
    const modal = $("#successModal");
    modal.classList.remove("open");
    modal.setAttribute("aria-hidden", "true");
    previousModalFocus?.focus?.();
  }
  function openSuccessModal(){
    const modal = $("#successModal");
    previousModalFocus = document.activeElement;
    modal.classList.add("open");
    modal.setAttribute("aria-hidden", "false");
    $("#successWhatsApp").style.display === "none" ? $("#modalClose").focus() : $("#successWhatsApp").focus();
  }

  $("#year").textContent = new Date().getFullYear();
  $("#menuToggle").addEventListener("click", () => {
    const nav = $("#mainNav"); const open = nav.classList.toggle("open");
    $("#menuToggle").setAttribute("aria-expanded", String(open));
  });
  $("#mainNav").querySelectorAll("a").forEach(a => a.addEventListener("click",()=>$("#mainNav").classList.remove("open")));
  $("#modalClose").addEventListener("click",closeSuccessModal);
  $("#successModal").addEventListener("click",e=>{if(e.target.id==="successModal")closeSuccessModal();});
  document.addEventListener("keydown",e=>{
    const modal=$("#successModal");
    if(!modal.classList.contains("open"))return;
    if(e.key==="Escape"){closeSuccessModal();return;}
    if(e.key==="Tab"){
      const controls=[...modal.querySelectorAll('a[href],button:not([disabled])')].filter(x=>x.offsetParent!==null);
      if(!controls.length)return;
      const first=controls[0], last=controls.at(-1);
      if(e.shiftKey&&document.activeElement===first){e.preventDefault();last.focus();}
      else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first.focus();}
    }
  });

  function setWhatsApp(number) {
    const n = phoneDigits(number || cfg.WHATSAPP || "5522988334019");
    const url = `https://wa.me/${n}`;
    $("#whatsappFloat").href = url;
    document.querySelectorAll("[data-contact-whatsapp]").forEach(link => { link.href = url; });
    return n;
  }
  function mapsUrl(address) {
    return `https://www.google.com/maps/dir/?api=1&destination=${encodeURIComponent(address || "R. Mário Vasconcelos, 60 - loja 01 - Centro, Araruama - RJ, 28979-132, Brasil")}`;
  }
  function applySettings(s) {
    settings = s || {};
    const wa = setWhatsApp(settings.whatsapp || cfg.WHATSAPP);
    const tel = settings.telefone || "+55 22 98833-4019";
    const address = settings.endereco || "R. Mário Vasconcelos, 60 - loja 01 - Centro, Araruama - RJ, 28979-132";
    $("#contactPhone").textContent = tel; $("#contactPhone").href = `tel:${phoneDigits(tel)}`;
    document.querySelectorAll("[data-display-phone]").forEach(link => link.textContent=tel);
    $("#contactAddress").textContent = address; $("#mapAddress").textContent = address;
    const sourceAddress = "R. Mário Vasconcelos, 60 - loja 01 - Centro, Araruama - RJ, 28979-132";
    const m = settings.link_maps || (address===sourceAddress
      ? "https://maps.google.com/?cid=12011292072847203588&g_mp=Cidnb29nbGUubWFwcy5wbGFjZXMudjEuUGxhY2VzLlNlYXJjaFRleHQQAhgEIAA"
      : mapsUrl(address));
    $("#mapsButton").href = m; $("#mapOpen").href = m;
    $("#mapFrame").src = `https://maps.google.com/maps?q=${encodeURIComponent(address)}&output=embed`;
    if(settings.descricao) $("#aboutText").textContent = settings.descricao;
    $("#contactHours").textContent = "Horários sob consulta. Confirme pelo WhatsApp ou consulte a agenda online.";
    if(settings.nome_estudio) document.title = `${settings.nome_estudio} | Nail Designer`;
    return wa;
  }
  async function loadSettings() {
    if(!db) return applySettings({});
    const {data,error}=await db.from("configuracoes").select("*").limit(1).maybeSingle();
    if(error) console.warn(error); return applySettings(data || {});
  }
  async function loadHours() {
    if(!db) return; // A fonte não informa horários de abertura; mostre aviso até configurá-los.
    let data,error;
    try { ({data,error}=await db.from("disponibilidade_semanal").select("dia_semana,ativo,horario_inicio,horario_fim").order("dia_semana")); }
    catch(err){error=err;}
    if(error||!data?.length) return;
    if(!data.some(day=>day.ativo)) {
      $("#hoursList").innerHTML = '<div><span>Horários de atendimento</span><b>Consulte pelo WhatsApp</b></div><small>Os dias e horários serão publicados após confirmação da loja.</small>';
      $("#contactHours").textContent = "Horários sob consulta. Confirme pelo WhatsApp ou consulte a agenda online.";
      return;
    }
    const labels=["Domingo","Segunda-feira","Terça-feira","Quarta-feira","Quinta-feira","Sexta-feira","Sábado"];
    const rows = data.map(day=>{
      const dayLabel=labels[day.dia_semana] || "Dia";
      const hourLabel=day.ativo ? `${String(day.horario_inicio).slice(0,5)} – ${String(day.horario_fim).slice(0,5)}` : "Não disponível";
      return {dayLabel,hourLabel};
    });
    $("#hoursList").innerHTML=rows.map(r=>`<div><span>${escapeHtml(r.dayLabel)}</span><b>${escapeHtml(r.hourLabel)}</b></div>`).join("") +
      '<small>Horários gerais configurados pelo estabelecimento; a disponibilidade individual é consultada ao agendar.</small>';
    $("#contactHours").textContent=rows.map(r=>`${r.dayLabel}: ${r.hourLabel}`).join(" · ");
  }
  function classifyService(name) {
    const n = String(name||"").toLowerCase();
    return /spa dos pés/.test(n) ? "spa" : /unhas de |manutenção|banho de gel/.test(n) ? "alongamento" : "manicure";
  }
  function activateServiceFilters(){
    const bar = $("#serviceFilters"); if(!bar)return;
    bar.querySelectorAll("button").forEach(btn=>btn.addEventListener("click",()=>{
      bar.querySelectorAll("button").forEach(el=>el.classList.toggle("active",el===btn));
      document.querySelectorAll("#servicesGrid .service-card").forEach(card=>{card.hidden=btn.dataset.category!=="todos" && card.dataset.serviceGroup!==btn.dataset.category;});
    }));
  }
  function serviceCard(s) {
    const image = s.imagem_url || "assets/manicure-rosada.jpg";
    const group = classifyService(s.nome);
    return `<article class="service-card" data-service-group="${group}"><div class="service-image" style="background-image:url('${escapeAttr(image)}')"></div><h3>${escapeHtml(s.nome)}</h3><p>${escapeHtml(s.descricao || "Um cuidado especial pensado para você.")}</p><div class="service-meta"><span class="service-price">${money(s.preco)}</span><span class="service-duration">${Number(s.duracao_minutos || 30)} min <small>(estim.)</small></span></div><button class="button button-dark" data-book-service="${s.id}">Agendar este serviço ↗</button></article>`;
  }
  function escapeHtml(v){return String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));}
  function escapeAttr(v){return escapeHtml(v).replace(/`/g,"&#96;");}
  async function loadServices() {
    if(!db){ services=previewServices;
      $("#servicesGrid").innerHTML=services.map(serviceCard).join("");
      $("#serviceSelect").innerHTML='<option value="">Configure o banco para agendar</option>'+services.map(s=>`<option value="${s.id}">${escapeHtml(s.nome)} · ${money(s.preco)}</option>`).join("");
      document.querySelectorAll("[data-book-service]").forEach(b=>b.addEventListener("click",()=>{$("#serviceSelect").value=b.dataset.bookService;$("#agenda").scrollIntoView({behavior:"smooth"});loadSlots();}));
      return;
    }
    const {data,error}=await db.from("servicos").select("*").eq("ativo",true).order("ordem").order("nome");
    if(error){$("#servicesGrid").innerHTML='<div class="loading-card">Não foi possível carregar os serviços. Verifique a configuração do banco de dados.</div>';return;}
    services=data||[];
    $("#servicesGrid").innerHTML=services.length?services.map(serviceCard).join(""):'<div class="loading-card">Nenhum serviço disponível no momento.</div>';
    $("#serviceSelect").innerHTML='<option value="">Selecione um procedimento</option>'+services.map(s=>`<option value="${s.id}">${escapeHtml(s.nome)} · ${money(s.preco)} · ${s.duracao_minutos} min</option>`).join("");
    document.querySelectorAll("[data-book-service]").forEach(b=>b.addEventListener("click",()=>{ $("#serviceSelect").value=b.dataset.bookService; $("#agenda").scrollIntoView({behavior:"smooth"}); loadSlots();}));
  }
  async function loadStaff() {
    const select = $("#staffSelect");
    if (!db) { select.innerHTML='<option value="">Configure o banco de dados</option>'; return; }
    const {data,error}=await db.rpc("get_public_staff");
    if(error){console.warn(error);select.innerHTML='<option value="">Não foi possível carregar</option>';return;}
    staffMembers=data||[];
    select.innerHTML='<option value="">Selecione quem fará seu atendimento</option>'+staffMembers.map(x=>{
      const score=Number(x.media_avaliacoes||0), count=Number(x.total_avaliacoes||0);
      const rating=count?` · ★ ${score.toFixed(1).replace(".",",")} (${count})`:"";
      return `<option value="${x.id}">${escapeHtml(x.nome)}${x.tipo==="admin"?" · Administradora":""}${rating}</option>`;
    }).join("");
  }
  async function loadGallery() {
    let rows;
    if(!db) rows=previewGallery;
    else {
      const {data,error}=await db.from("galeria").select("*").eq("ativo",true).order("ordem");
      if(error){$("#galleryGrid").innerHTML='<div class="loading-card">Não foi possível carregar a galeria.</div>';return;}
      rows=data||[];
    }
    const categories=[...new Set(rows.map(x=>x.categoria).filter(Boolean))];
    $("#galleryFilters").innerHTML='<button class="filter active" data-filter="all">Todas</button>'+categories.map(c=>`<button class="filter" data-filter="${escapeAttr(c)}">${escapeHtml(c)}</button>`).join("");
    $("#galleryGrid").innerHTML=rows.length?rows.map(x=>`<figure class="gallery-item" data-category="${escapeAttr(x.categoria||"")}"><img loading="lazy" src="${escapeAttr(x.imagem_url)}" alt="${escapeAttr(x.titulo||"Inspiração do Studio Beth's Designers")}"><figcaption class="gallery-caption">${escapeHtml(x.titulo||x.categoria||"Studio Beth's Designers")}</figcaption></figure>`).join(""):'<div class="loading-card">As novidades da galeria aparecerão aqui em breve.</div>';
    $("#galleryFilters").querySelectorAll("button").forEach(b=>b.addEventListener("click",()=>{ $("#galleryFilters").querySelectorAll("button").forEach(x=>x.classList.remove("active"));b.classList.add("active");$("#galleryGrid").querySelectorAll(".gallery-item").forEach(item=>item.hidden=b.dataset.filter!=="all"&&item.dataset.category!==b.dataset.filter);}));
  }
  function todayLocal(){const d=new Date();return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,"0")}-${String(d.getDate()).padStart(2,"0")}`;}
  $("#bookingDate").min=todayLocal();
  $("#bookingDate").addEventListener("change",loadSlots);
  $("#serviceSelect").addEventListener("change",loadSlots);
  $("#staffSelect").addEventListener("change",loadSlots);
  async function loadSlots(){
    const requestId = ++latestSlotsRequest;
    selectedSlot=null;$("#selectedTime").value="";
    const date=$("#bookingDate").value, service=$("#serviceSelect").value, staff=$("#staffSelect").value, holder=$("#slots");
    if(!date||!service||!staff){holder.innerHTML='<p class="muted">Selecione um serviço e uma data para consultar os horários.</p>';return;}
    if(date<todayLocal()){holder.innerHTML='<p class="muted">Escolha uma data futura.</p>';return;}
    if(!db){holder.innerHTML='<p class="muted">Configure o banco de dados para consultar a disponibilidade real.</p>';return;}
    holder.innerHTML='<p class="muted">Consultando disponibilidade...</p>';
    let data, error;
    try { ({data,error}=await db.rpc("get_available_slots",{p_date:date,p_service_id:service,p_staff_id:staff})); }
    catch(err){ error=err; }
    if(requestId!==latestSlotsRequest)return;
    if(error){console.error(error);holder.innerHTML='<p class="muted">Não foi possível consultar os horários. Tente novamente.</p>';return;}
    if(!data?.length){holder.innerHTML='<p class="muted">Não há horários disponíveis nesta data. Escolha outro dia.</p>';return;}
    holder.innerHTML=data.map(x=>`<button type="button" class="slot" data-time="${x.start_time}">${String(x.start_time).slice(0,5)}–${String(x.end_time).slice(0,5)}</button>`).join("");
    holder.querySelectorAll(".slot").forEach(b=>b.addEventListener("click",()=>{holder.querySelectorAll(".slot").forEach(x=>x.classList.remove("selected"));b.classList.add("selected");selectedSlot=b.dataset.time;$("#selectedTime").value=selectedSlot;}));
  }
  $("#bookingForm").addEventListener("submit",async e=>{
    e.preventDefault();const bookingForm=e.currentTarget,feedback=$("#bookingFeedback"),btn=$("#bookingSubmit");
    if(bookingInProgress)return;
    feedback.className="form-feedback";feedback.textContent="";
    if(!db){feedback.classList.add("error");feedback.textContent="O agendamento online ainda não está conectado ao banco de dados. Entre em contato pelo WhatsApp.";return;}
    if(!fStaffSelected()){feedback.classList.add("error");feedback.textContent="Selecione a profissional que fará seu atendimento.";return;}
    if(!selectedSlot){feedback.classList.add("error");feedback.textContent="Selecione um horário disponível.";return;}
    const f=new FormData(bookingForm), service=services.find(s=>s.id===f.get("service")), professional=staffMembers.find(x=>x.id===f.get("staff"));
    if(!service){feedback.classList.add("error");feedback.textContent="Selecione um serviço válido.";return;}
    if(!professional){feedback.classList.add("error");feedback.textContent="Selecione uma profissional válida.";return;}
    bookingInProgress=true;
    btn.disabled=true;btn.textContent="Registrando solicitação...";
    const payload={p_name:String(f.get("name")).trim(),p_phone:String(f.get("phone")).trim(),p_service_id:f.get("service"),p_staff_id:f.get("staff"),p_date:f.get("date"),p_start_time:selectedSlot,p_notes:String(f.get("notes")||"").trim()};
    let data, error;
    try { ({data,error}=await db.rpc("create_booking",payload)); }
    catch(err){ error=err; }
    finally { bookingInProgress=false;btn.disabled=false;btn.innerHTML='Solicitar agendamento <span>↗</span>'; }
    if(error||!data?.success){feedback.classList.add("error");feedback.textContent=data?.message||"Este horário acabou de ficar indisponível. Atualizamos a agenda; escolha outro horário.";await loadSlots();return;}
    // Nenhuma mensagem é enviada automaticamente. A cliente decide enviar pelo botão do modal.
    const start=String(data.start_time).slice(0,5),end=String(data.end_time).slice(0,5);
    const dateLabel=new Date(`${payload.p_date}T12:00:00`).toLocaleDateString("pt-BR");
    const message=`Olá! Acabei de solicitar um agendamento pelo site do Studio Beth's Designers.\n\nNome: ${payload.p_name}\nProfissional: ${professional.nome}\nServiço: ${service.nome}\nData: ${dateLabel}\nHorário: ${start} às ${end}\nCódigo: ${data.code}\n\nGostaria de confirmar meu atendimento.`;
    $("#successDetails").textContent=`${service.nome} com ${professional.nome} · ${dateLabel} · ${start} às ${end}. Código: ${data.code}.`;
    // Consulte o telefone pela reserva criada, nunca pelo contato geral do estúdio.
    // O servidor confere o código + telefone da cliente e usa o profissional_id salvo na reserva.
    const waLink=$("#successWhatsApp"),waNote=$("#successModal .modal-small");
    waLink.removeAttribute("href");
    waLink.style.display="none";
    if(waNote)waNote.textContent="Sua reserva está salva. Consultando o WhatsApp da profissional selecionada...";
    openSuccessModal();
    try {
      const {data:contact,error:contactError}=await db.rpc("get_booking_whatsapp",{
        p_code:data.code,
        p_phone:payload.p_phone
      });
      if(contactError)throw contactError;
      const targetPhone=phoneDigits(contact?.whatsapp);
      if(contact?.success && /^[0-9]{10,15}$/.test(targetPhone)){
        waLink.href=`https://wa.me/${targetPhone}?text=${encodeURIComponent(message)}`;
        waLink.style.display="";
        if(waNote)waNote.textContent=`Sua reserva foi registrada! Toque no botão para abrir o WhatsApp de ${professional.nome} e depois pressione Enviar no aplicativo. Nenhuma mensagem é enviada automaticamente.`;
      } else {
        console.warn("WhatsApp da profissional indisponível:",contact?.message||"Número não cadastrado");
        if(waNote)waNote.textContent="Sua reserva foi salva, mas o WhatsApp da profissional não está disponível. Entre em contato com o estúdio pelo botão de WhatsApp geral da página.";
      }
    }catch(contactError){
      console.error("Não foi possível consultar o WhatsApp da profissional:",contactError);
      if(waNote)waNote.textContent="Sua reserva foi salva. Não foi possível consultar o WhatsApp da profissional neste momento; entre em contato pelo botão de WhatsApp geral da página.";
    }
    bookingForm.reset();$("#bookingDate").min=todayLocal();$("#slots").innerHTML='<p class="muted">Selecione um serviço e uma data para consultar os horários.</p>';selectedSlot=null;latestSlotsRequest++;
  });
  function fStaffSelected(){return Boolean($("#staffSelect").value);}
  $("#reviewForm")?.addEventListener("submit",async e=>{
    e.preventDefault();
    const form=e.currentTarget, feedback=$("#reviewFeedback"), button=$("#reviewSubmit");
    feedback.className="form-feedback";feedback.textContent="";
    if(!db){feedback.classList.add("error");feedback.textContent="O sistema de avaliações estará disponível após configurar o banco de dados.";return;}
    const f=new FormData(form);
    const payload={p_code:String(f.get("code")||"").trim().toUpperCase(),p_phone:String(f.get("phone")||"").trim(),p_rating:Number(f.get("rating")),p_comment:String(f.get("comment")||"").trim()};
    if(!payload.p_code||!payload.p_phone||payload.p_rating<1||payload.p_rating>5){feedback.classList.add("error");feedback.textContent="Preencha o código, WhatsApp e uma nota de 1 a 5.";return;}
    button.disabled=true;button.textContent="Enviando avaliação...";
    let data, error;
    try {({data,error}=await db.rpc("submit_staff_review",payload));}
    catch(err){error=err;}
    finally{button.disabled=false;button.textContent="Enviar avaliação ↗";}
    if(error||!data?.success){feedback.classList.add("error");feedback.textContent=data?.message||"Não foi possível registrar. Confira o código, o WhatsApp e se o atendimento já foi concluído.";return;}
    feedback.classList.add("success");feedback.textContent=`Obrigada! Sua avaliação de ${data.profissional} foi registrada.`;
    form.reset();await loadStaff();
  });
  async function init(){activateServiceFilters();await loadSettings();await Promise.all([loadServices(),loadStaff(),loadGallery(),loadHours()]);}
  init();
})();