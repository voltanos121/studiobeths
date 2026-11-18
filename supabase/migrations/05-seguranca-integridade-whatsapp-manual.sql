-- STUDIO BETH'S DESIGNERS | MIGRAÇÃO 05 | 18/11/2026
-- Executar APENAS no banco existente, DEPOIS de backup e das migrações anteriores.
-- Preserva histórico, não cancela reservas e NÃO envia WhatsApp automático.
-- Execute INTEIRO uma vez no Supabase SQL Editor (é seguro repetir em banco compatível).
begin;

-- 1. Privacidade: nem visitantes nem funcionários podem consultar os demais perfis
-- (e seus números). O site usa get_public_staff() para exibir os nomes.
drop policy if exists "public read active staff" on public.profissionais;
drop policy if exists "staff read own profile" on public.profissionais;
drop policy if exists "profile read only owner or admin" on public.profissionais;
create policy "profile read only owner or admin" on public.profissionais
  for select to authenticated
  using (public.is_admin() or (auth.uid() is not null and auth_user_id = auth.uid()));
revoke select on public.profissionais from anon;
-- Os GRANTs de authenticated permanecem para as consultas do próprio funcionário
-- e do painel administrador, mas a policy restringe as LINHAS permitidas.

-- 2. Histórico de valores: o preço é fixado no momento de cada NOVA reserva.
-- Reservas antigas recebem NULL porque o preço original delas é desconhecido.
alter table public.agendamentos
  add column if not exists preco_cobrado numeric(10,2);
alter table public.agendamentos drop constraint if exists agendamentos_preco_cobrado_nonnegative;
alter table public.agendamentos
  add constraint agendamentos_preco_cobrado_nonnegative check(preco_cobrado is null or preco_cobrado >= 0);
create or replace function public.booking_record_price()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- Nunca sobrescreva o preço de uma reserva antiga por uma simples edição.
  if tg_op = 'INSERT' then
    select s.preco into new.preco_cobrado from public.servicos s where s.id = new.servico_id;
  elsif new.servico_id is distinct from old.servico_id then
    select s.preco into new.preco_cobrado from public.servicos s where s.id = new.servico_id;
  end if;
  return new;
end $$;
drop trigger if exists trg_booking_record_price on public.agendamentos;
create trigger trg_booking_record_price before insert or update of servico_id
  on public.agendamentos for each row execute function public.booking_record_price();

-- 3. Regras de transição também no banco, inclusive para atualizações manuais.
create or replace function public.booking_guard_status_transition()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.status is distinct from old.status then
    if not (
      (old.status = 'pendente' and new.status in ('confirmado','cancelado'))
      or (old.status = 'confirmado' and new.status in ('cancelado','concluido'))
    ) then
      raise exception 'Transição inválida de % para %. Confirme antes de concluir.', old.status, new.status
        using errcode = '23514';
    end if;
  end if;
  new.updated_at = now();
  return new;
end $$;
drop trigger if exists trg_booking_guard_status on public.agendamentos;
create trigger trg_booking_guard_status before update of status on public.agendamentos
  for each row execute function public.booking_guard_status_transition();

-- Registro de alterações de status para auditoria administrativa.
create table if not exists public.agendamento_eventos(
  id bigint generated always as identity primary key,
  agendamento_id uuid not null references public.agendamentos(id) on delete cascade,
  status_anterior text not null,
  status_novo text not null,
  alterado_por uuid,
  criado_em timestamptz not null default now()
);
alter table public.agendamento_eventos enable row level security;
drop policy if exists "admin read booking events" on public.agendamento_eventos;
create policy "admin read booking events" on public.agendamento_eventos
  for select to authenticated using(public.is_admin());
grant select on public.agendamento_eventos to authenticated;
create or replace function public.booking_log_status_event()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.status is distinct from new.status then
    insert into public.agendamento_eventos(agendamento_id,status_anterior,status_novo,alterado_por)
    values(new.id,old.status,new.status,auth.uid());
  end if;
  return new;
end $$;
drop trigger if exists trg_booking_log_status on public.agendamentos;
create trigger trg_booking_log_status after update of status on public.agendamentos
  for each row execute function public.booking_log_status_event();

-- Administradora altera qualquer agendamento, respeitando a mesma sequência da equipe.
create or replace function public.admin_update_booking_status(p_booking_id uuid,p_new_status text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_booking public.agendamentos%rowtype;
begin
  if auth.uid() is null or not public.is_admin() then
    return jsonb_build_object('success',false,'message','Acesso administrativo necessário.');
  end if;
  if p_new_status is null or p_new_status not in ('confirmado','cancelado','concluido') then
    return jsonb_build_object('success',false,'message','Status não permitido.');
  end if;
  select * into v_booking from public.agendamentos a where a.id=p_booking_id for update;
  if not found then return jsonb_build_object('success',false,'message','Reserva não encontrada.'); end if;
  if not (
    (v_booking.status='pendente' and p_new_status in ('confirmado','cancelado'))
    or (v_booking.status='confirmado' and p_new_status in ('cancelado','concluido'))
  ) then
    return jsonb_build_object('success',false,'message','Ação incompatível com o status atual. Atualize a agenda.');
  end if;
  update public.agendamentos set status=p_new_status where id=p_booking_id;
  return jsonb_build_object('success',true,'status',p_new_status);
end $$;
revoke all on function public.admin_update_booking_status(uuid,text) from public,anon,authenticated;
grant execute on function public.admin_update_booking_status(uuid,text) to authenticated;

-- 4. Regras de datas na timezone do estúdio (Araruama/RJ).
create or replace function public.get_available_slots(p_date date,p_service_id uuid,p_staff_id uuid)
returns table(start_time time,end_time time) language plpgsql stable security definer set search_path=public as $$
declare
  v_day public.disponibilidade_semanal%rowtype;
  v_duration integer; v_start time; v_finish time;
  v_today date := (now() at time zone 'America/Sao_Paulo')::date;
  v_current_time time := (now() at time zone 'America/Sao_Paulo')::time;
begin
  if p_date is null or p_date < v_today then return; end if;
  if not exists(select 1 from public.profissionais where id=p_staff_id and ativo=true) then return; end if;
  select * into v_day from public.disponibilidade_semanal
    where dia_semana=extract(dow from p_date)::integer and ativo=true;
  if not found then return; end if;
  select duracao_minutos into v_duration from public.servicos where id=p_service_id and ativo=true;
  if not found then return; end if;
  v_start:=v_day.horario_inicio;
  while v_start + make_interval(mins=>v_duration) <= v_day.horario_fim loop
    v_finish:=v_start + make_interval(mins=>v_duration);
    if (v_day.intervalo_inicio is null or v_day.intervalo_fim is null
          or v_finish<=v_day.intervalo_inicio or v_start>=v_day.intervalo_fim)
      and not exists(select 1 from public.bloqueios b where b.data=p_date
        and (b.dia_inteiro or (v_start<b.horario_fim and v_finish>b.horario_inicio)))
      and not exists(select 1 from public.agendamentos a where a.data=p_date
        and a.profissional_id=p_staff_id and a.status in ('pendente','confirmado')
        and v_start<a.horario_fim and v_finish>a.horario_inicio)
      and (p_date>v_today or v_start>v_current_time)
    then start_time:=v_start;end_time:=v_finish;return next;end if;
    v_start:=v_start+interval '30 minutes';
  end loop;
end $$;
revoke all on function public.get_available_slots(date,uuid,uuid) from public,anon,authenticated;
grant execute on function public.get_available_slots(date,uuid,uuid) to anon,authenticated;

-- Validação de entrada e proteção leve contra reservas repetidas pelo mesmo telefone.
create or replace function public.create_booking(
  p_name text,p_phone text,p_service_id uuid,p_staff_id uuid,p_date date,p_start_time time,p_notes text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_client uuid; v_service public.servicos%rowtype; v_code text; v_end time;
  v_phone text := regexp_replace(coalesce(p_phone,''),'[^0-9]','','g');
  v_today date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if length(trim(coalesce(p_name,''))) not between 2 and 100 or length(v_phone) not between 10 and 15 then
    return jsonb_build_object('success',false,'message','Informe nome e WhatsApp válidos.');
  end if;
  if length(coalesce(p_notes,''))>600 then
    return jsonb_build_object('success',false,'message','Observações muito longas (máximo de 600 caracteres).');
  end if;
  if p_date is null or p_start_time is null or p_date < v_today then
    return jsonb_build_object('success',false,'message','Escolha uma data e horário válidos.');
  end if;
  if not exists(select 1 from public.profissionais where id=p_staff_id and ativo=true) then
    return jsonb_build_object('success',false,'message','Profissional indisponível.');
  end if;
  -- Serializa reservas para esta profissional e data, inclusive dupla submissão.
  perform pg_advisory_xact_lock(hashtext(p_date::text||p_staff_id::text));
  select * into v_service from public.servicos where id=p_service_id and ativo=true;
  if not found then return jsonb_build_object('success',false,'message','Serviço indisponível.');end if;
  v_end:=p_start_time+make_interval(mins=>v_service.duracao_minutos);
  if not exists(select 1 from public.get_available_slots(p_date,p_service_id,p_staff_id) s where s.start_time=p_start_time) then
    return jsonb_build_object('success',false,'message','Este horário não está mais disponível. Atualize a agenda.');
  end if;
  -- Limita reservas em aberto para o MESMO telefone e DIA.
  if (select count(*) from public.agendamentos a join public.clientes c on c.id=a.cliente_id
      where a.data=p_date and a.status in ('pendente','confirmado')
        and regexp_replace(c.telefone,'[^0-9]','','g')=v_phone) >= 5 then
    return jsonb_build_object('success',false,'message','Limite de agendamentos deste telefone nesta data atingido. Entre em contato com o estúdio.');
  end if;
  insert into public.clientes(nome,telefone) values(trim(p_name),trim(p_phone)) returning id into v_client;
  insert into public.agendamentos(cliente_id,servico_id,profissional_id,data,horario_inicio,horario_fim,observacoes)
  values(v_client,p_service_id,p_staff_id,p_date,p_start_time,v_end,nullif(trim(coalesce(p_notes,'')),''))
  returning codigo into v_code;
  return jsonb_build_object('success',true,'code',v_code,'start_time',p_start_time,'end_time',v_end);
exception when exclusion_violation then
  return jsonb_build_object('success',false,'message','Este horário acabou de ser reservado. Escolha outro.');
end $$;
revoke all on function public.create_booking(text,text,uuid,uuid,date,time,text) from public,anon,authenticated;
grant execute on function public.create_booking(text,text,uuid,uuid,date,time,text) to anon,authenticated;

-- Relatório: reservas novas congelam preço; antigas SEM snapshot ainda são estimadas pelo preço atual.
create or replace function public.get_staff_performance()
returns table(profissional_id uuid,nome text,tipo text,atendimentos_concluidos bigint,rendimento_bruto numeric,media_avaliacoes numeric,total_avaliacoes bigint)
language plpgsql stable security definer set search_path=public as $$
begin
  if not public.is_admin() then raise exception 'Acesso restrito à administradora.'; end if;
  return query
    select p.id,p.nome,p.tipo,
      count(a.id) filter(where a.status='concluido'),
      coalesce(sum(coalesce(a.preco_cobrado,s.preco)) filter(where a.status='concluido'),0)::numeric(12,2),
      coalesce((select round(avg(r.nota)::numeric,1) from public.avaliacoes_funcionarios r where r.profissional_id=p.id),0),
      (select count(*) from public.avaliacoes_funcionarios r where r.profissional_id=p.id)
    from public.profissionais p
    left join public.agendamentos a on a.profissional_id=p.id
    left join public.servicos s on s.id=a.servico_id
    where p.tipo in ('admin','funcionario')
    group by p.id,p.nome,p.tipo,p.ordem
    order by count(a.id) filter(where a.status='concluido') desc,
      coalesce(sum(coalesce(a.preco_cobrado,s.preco)) filter(where a.status='concluido'),0) desc,p.nome;
end $$;
revoke all on function public.get_staff_performance() from public,anon,authenticated;
grant execute on function public.get_staff_performance() to authenticated;

-- 5. Convites somente para funcionários sem conta vinculada.
create or replace function public.create_staff_invite(p_staff_id uuid,p_token_hash text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_admin() then raise exception 'Apenas a administradora pode convidar funcionários.'; end if;
  if not exists(select 1 from public.profissionais p where p.id=p_staff_id
      and p.tipo='funcionario' and p.ativo=true and p.auth_user_id is null) then
    raise exception 'Funcionário inválido, inativo ou já possui acesso.';
  end if;
  insert into public.convites_funcionarios(profissional_id,token_hash,criado_por,expira_em)
  values(p_staff_id,p_token_hash,auth.uid(),now()+interval '30 minutes');
end $$;

-- 6. Arquivamento com rastreio da conta Auth anterior para remoção segura.
alter table public.profissionais add column if not exists auth_user_id_arquivado uuid;
create or replace function public.arquivar_profissional(p_profissional_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_profissional public.profissionais%rowtype;
  v_abertos bigint;
begin
  if auth.uid() is null or not public.is_admin() then
    return jsonb_build_object('success',false,'message','Apenas administradores podem remover funcionários.');
  end if;
  select * into v_profissional from public.profissionais p where p.id=p_profissional_id for update;
  if not found then return jsonb_build_object('success',false,'message','Profissional não encontrado.');end if;
  if v_profissional.tipo<>'funcionario' then
    return jsonb_build_object('success',false,'message','Não é permitido remover administradores por esta função.');
  end if;
  if v_profissional.arquivado_em is not null then
    return jsonb_build_object('success',true,'message','Profissional já arquivado.');
  end if;
  select count(*) into v_abertos from public.agendamentos a
    where a.profissional_id=p_profissional_id and a.status in ('pendente','confirmado');
  if v_abertos>0 then
    return jsonb_build_object('success',false,'message',format(
      'Há %s agendamento(s) em aberto. Confirme/conclua ou cancele antes de remover.',v_abertos));
  end if;
  update public.profissionais
    set ativo=false,arquivado_em=now(),auth_user_id_arquivado=auth_user_id,
        auth_user_id=null,username=null,whatsapp=null,whatsapp_opt_in=false
    where id=p_profissional_id;
  delete from public.convites_funcionarios c where c.profissional_id=p_profissional_id;
  return jsonb_build_object('success',true,'message','Profissional arquivado e histórico preservado.');
end $$;
revoke all on function public.arquivar_profissional(uuid) from public,anon,authenticated;
grant execute on function public.arquivar_profissional(uuid) to authenticated;

notify pgrst, 'reload schema';
commit;
