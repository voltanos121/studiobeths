-- STUDIO BETH'S DESIGNERS — esquema Supabase atualizado com equipe e agendamento por profissional
create extension if not exists pgcrypto;
create extension if not exists btree_gist;

create table if not exists public.admins(user_id uuid primary key references auth.users(id) on delete cascade,created_at timestamptz not null default now());
create table if not exists public.profissionais(
 id uuid primary key default gen_random_uuid(), nome text not null check(length(trim(nome)) between 2 and 80),
 tipo text not null default 'funcionario' check(tipo in ('admin','funcionario')),
 username text unique, auth_user_id uuid unique references auth.users(id) on delete set null,
 ativo boolean not null default true, ordem integer not null default 0, created_at timestamptz not null default now()
);
create table if not exists public.convites_funcionarios(
 id uuid primary key default gen_random_uuid(), profissional_id uuid not null references public.profissionais(id) on delete cascade,
 token_hash text not null unique, criado_por uuid not null references auth.users(id), expira_em timestamptz not null,
 usado_em timestamptz, created_at timestamptz not null default now()
);
create table if not exists public.clientes(id uuid primary key default gen_random_uuid(),nome text not null,telefone text not null,created_at timestamptz not null default now());
create table if not exists public.servicos(id uuid primary key default gen_random_uuid(),nome text not null,descricao text,preco numeric(10,2) not null default 0 check(preco>=0),duracao_minutos integer not null default 30 check(duracao_minutos>=30 and duracao_minutos%30=0),imagem_url text,ordem integer not null default 0,ativo boolean not null default true,created_at timestamptz not null default now());
create table if not exists public.agendamentos(
 id uuid primary key default gen_random_uuid(),codigo text not null unique default upper(substr(encode(gen_random_bytes(6),'hex'),1,10)),
 cliente_id uuid not null references public.clientes(id),servico_id uuid not null references public.servicos(id),
 profissional_id uuid references public.profissionais(id),data date not null,horario_inicio time not null,horario_fim time not null,
 status text not null default 'pendente' check(status in ('pendente','confirmado','cancelado','concluido')),observacoes text,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),check(horario_fim>horario_inicio)
);
-- Bloqueia sobreposição apenas na agenda do mesmo profissional.
do $$ begin
 alter table public.agendamentos add constraint agendamentos_sem_sobreposicao_por_profissional
 exclude using gist (profissional_id with =, tsrange((data+horario_inicio)::timestamp,(data+horario_fim)::timestamp,'[)') with &&)
 where (status in ('pendente','confirmado') and profissional_id is not null);
exception when duplicate_object then null; end $$;

create table if not exists public.disponibilidade_semanal(id uuid primary key default gen_random_uuid(),dia_semana integer not null unique check(dia_semana between 0 and 6),ativo boolean not null default false,horario_inicio time not null default '09:00',horario_fim time not null default '18:00',intervalo_inicio time,intervalo_fim time,check(horario_fim>horario_inicio));
create table if not exists public.bloqueios(id uuid primary key default gen_random_uuid(),data date not null,horario_inicio time,horario_fim time,dia_inteiro boolean not null default true,descricao text not null,check(dia_inteiro or (horario_inicio is not null and horario_fim is not null and horario_fim>horario_inicio)));
create table if not exists public.galeria(id uuid primary key default gen_random_uuid(),titulo text not null,descricao text,imagem_url text not null,categoria text,ordem integer not null default 0,ativo boolean not null default true,created_at timestamptz not null default now());
create table if not exists public.configuracoes(id uuid primary key default gen_random_uuid(),nome_estudio text not null default 'Studio Beth''s Designers',descricao text,telefone text default '+55 22 98833-4019',whatsapp text default '5522988334019',endereco text default 'R. Mário Vasconcelos, 60 - loja 01 - Centro, Araruama - RJ, 28979-132',link_maps text,instagram text,updated_at timestamptz not null default now());

insert into public.disponibilidade_semanal(dia_semana,ativo,horario_inicio,horario_fim) values (0,false,'09:00','18:00'),(1,false,'09:00','18:00'),(2,false,'09:00','18:00'),(3,false,'09:00','18:00'),(4,false,'09:00','18:00'),(5,false,'09:00','18:00'),(6,false,'09:00','18:00') on conflict(dia_semana) do nothing;
insert into public.configuracoes(nome_estudio,telefone,whatsapp,endereco) select 'Studio Beth''s Designers','+55 22 98833-4019','5522988334019','R. Mário Vasconcelos, 60 - loja 01 - Centro, Araruama - RJ, 28979-132' where not exists(select 1 from public.configuracoes);

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from public.admins where user_id=auth.uid()) $$;
-- Cria perfil de atendimento automaticamente para a conta administradora incluída em public.admins.
create or replace function public.create_admin_professional() returns trigger language plpgsql security definer set search_path=public as $$ begin
 insert into public.profissionais(nome,tipo,auth_user_id,ativo,ordem) values('Administradora','admin',new.user_id,true,0)
 on conflict(auth_user_id) do update set tipo='admin',ativo=true;
 return new; end $$;
drop trigger if exists trg_admin_professional on public.admins;
create trigger trg_admin_professional after insert on public.admins for each row execute function public.create_admin_professional();
insert into public.profissionais(nome,tipo,auth_user_id,ativo,ordem) select 'Administradora','admin',a.user_id,true,0 from public.admins a where not exists(select 1 from public.profissionais p where p.auth_user_id=a.user_id);

-- Disponibilidade é calculada separadamente para cada profissional.
create or replace function public.get_available_slots(p_date date,p_service_id uuid,p_staff_id uuid)
returns table(start_time time,end_time time) language plpgsql stable security definer set search_path=public as $$
declare v_day public.disponibilidade_semanal%rowtype; v_duration integer; v_start time; v_finish time;
begin
 if p_date<current_date then return; end if;
 if not exists(select 1 from public.profissionais where id=p_staff_id and ativo=true) then return; end if;
 select * into v_day from public.disponibilidade_semanal where dia_semana=extract(dow from p_date)::integer and ativo=true; if not found then return; end if;
 select duracao_minutos into v_duration from public.servicos where id=p_service_id and ativo=true; if not found then return; end if;
 v_start:=v_day.horario_inicio;
 while v_start+make_interval(mins=>v_duration)<=v_day.horario_fim loop
  v_finish:=v_start+make_interval(mins=>v_duration);
  if (v_day.intervalo_inicio is null or v_day.intervalo_fim is null or v_finish<=v_day.intervalo_inicio or v_start>=v_day.intervalo_fim)
   and not exists(select 1 from public.bloqueios b where b.data=p_date and (b.dia_inteiro or (v_start<b.horario_fim and v_finish>b.horario_inicio)))
   and not exists(select 1 from public.agendamentos a where a.data=p_date and a.profissional_id=p_staff_id and a.status in ('pendente','confirmado') and v_start<a.horario_fim and v_finish>a.horario_inicio)
   and (p_date>current_date or v_start>localtime)
  then start_time:=v_start;end_time:=v_finish;return next;end if;
  v_start:=v_start+interval '30 minutes';
 end loop;
end $$;

create or replace function public.create_booking(p_name text,p_phone text,p_service_id uuid,p_staff_id uuid,p_date date,p_start_time time,p_notes text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_client uuid;v_service public.servicos%rowtype;v_code text;v_end time;
begin
 if length(trim(coalesce(p_name,'')))<2 or length(trim(coalesce(p_phone,'')))<8 then return jsonb_build_object('success',false,'message','Informe nome e telefone válidos.');end if;
 if p_date<current_date then return jsonb_build_object('success',false,'message','Não é possível reservar uma data passada.');end if;
 if not exists(select 1 from public.profissionais where id=p_staff_id and ativo=true) then return jsonb_build_object('success',false,'message','Profissional indisponível.');end if;
 perform pg_advisory_xact_lock(hashtext(p_date::text||p_staff_id::text));
 select * into v_service from public.servicos where id=p_service_id and ativo=true;if not found then return jsonb_build_object('success',false,'message','Serviço indisponível.');end if;
 v_end:=p_start_time+make_interval(mins=>v_service.duracao_minutos);
 if not exists(select 1 from public.get_available_slots(p_date,p_service_id,p_staff_id) s where s.start_time=p_start_time) then return jsonb_build_object('success',false,'message','Este horário não está mais disponível. Atualize a agenda.');end if;
 insert into public.clientes(nome,telefone) values(trim(p_name),trim(p_phone)) returning id into v_client;
 insert into public.agendamentos(cliente_id,servico_id,profissional_id,data,horario_inicio,horario_fim,observacoes) values(v_client,p_service_id,p_staff_id,p_date,p_start_time,v_end,nullif(trim(coalesce(p_notes,'')),'')) returning codigo into v_code;
 return jsonb_build_object('success',true,'code',v_code,'start_time',p_start_time,'end_time',v_end);
exception when exclusion_violation then return jsonb_build_object('success',false,'message','Este horário acabou de ser reservado. Escolha outro.');end $$;

-- Convites: somente administradores podem criar e consultar convites; tokens são armazenados apenas como hash.
create or replace function public.create_staff_invite(p_staff_id uuid,p_token_hash text)
returns void language plpgsql security definer set search_path=public as $$ begin
 if not public.is_admin() then raise exception 'Apenas a administradora pode convidar funcionários.';end if;
 if not exists(select 1 from public.profissionais where id=p_staff_id and tipo='funcionario' and ativo=true) then raise exception 'Funcionário inválido ou inativo.';end if;
 insert into public.convites_funcionarios(profissional_id,token_hash,criado_por,expira_em) values(p_staff_id,p_token_hash,auth.uid(),now()+interval '30 minutes');
end $$;

-- RLS
alter table public.admins enable row level security;alter table public.profissionais enable row level security;alter table public.convites_funcionarios enable row level security;alter table public.clientes enable row level security;alter table public.servicos enable row level security;alter table public.agendamentos enable row level security;alter table public.disponibilidade_semanal enable row level security;alter table public.bloqueios enable row level security;alter table public.galeria enable row level security;alter table public.configuracoes enable row level security;
create policy "admins read admins" on public.admins for select to authenticated using(user_id=auth.uid() or public.is_admin());
create policy "public read active staff" on public.profissionais for select to anon,authenticated using(ativo=true or public.is_admin());
create policy "admins manage staff" on public.profissionais for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "admins manage invitations" on public.convites_funcionarios for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "public read active services" on public.servicos for select to anon,authenticated using(ativo or public.is_admin());
create policy "admins manage services" on public.servicos for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "public read active gallery" on public.galeria for select to anon,authenticated using(ativo or public.is_admin());
create policy "admins manage gallery" on public.galeria for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "public read settings" on public.configuracoes for select to anon,authenticated using(true);
create policy "admins manage settings" on public.configuracoes for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "public read weekly availability" on public.disponibilidade_semanal for select to anon,authenticated using(true);
create policy "admins manage weekly availability" on public.disponibilidade_semanal for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "admins manage blocks" on public.bloqueios for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "admins read clients" on public.clientes for select to authenticated using(public.is_admin());
create policy "admins manage clients" on public.clientes for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "staff read own clients" on public.clientes for select to authenticated using(exists(select 1 from public.agendamentos a join public.profissionais p on p.id=a.profissional_id where a.cliente_id=clientes.id and p.auth_user_id=auth.uid()));
create policy "admins manage bookings" on public.agendamentos for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "staff read own appointments" on public.agendamentos for select to authenticated using(exists(select 1 from public.profissionais p where p.id=profissional_id and p.auth_user_id=auth.uid()));
create policy "staff read own profile" on public.profissionais for select to authenticated using(auth_user_id=auth.uid() or public.is_admin());

grant select on public.profissionais,public.servicos,public.galeria,public.configuracoes,public.disponibilidade_semanal to anon,authenticated;
grant all on public.profissionais,public.servicos,public.galeria,public.configuracoes,public.disponibilidade_semanal,public.bloqueios to authenticated;
grant select,insert,update,delete on public.agendamentos,public.clientes to authenticated;
grant select,insert,update,delete on public.convites_funcionarios to authenticated;
grant execute on function public.get_available_slots(date,uuid,uuid) to anon,authenticated;
grant execute on function public.create_booking(text,text,uuid,uuid,date,time,text) to anon,authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.create_staff_invite(uuid,text) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('studio-beth-gallery','studio-beth-gallery',true,8388608,array['image/jpeg','image/png','image/webp']) on conflict(id) do update set public=true,file_size_limit=8388608,allowed_mime_types=array['image/jpeg','image/png','image/webp'];
create policy "public can view studio gallery files" on storage.objects for select to anon,authenticated using(bucket_id='studio-beth-gallery');
create policy "admins upload studio gallery files" on storage.objects for insert to authenticated with check(bucket_id='studio-beth-gallery' and public.is_admin());
create policy "admins update studio gallery files" on storage.objects for update to authenticated using(bucket_id='studio-beth-gallery' and public.is_admin()) with check(bucket_id='studio-beth-gallery' and public.is_admin());
create policy "admins delete studio gallery files" on storage.objects for delete to authenticated using(bucket_id='studio-beth-gallery' and public.is_admin());

-- ==========================================================
-- EXTENSÃO: WhatsApp da equipe, avaliações e desempenho
-- Execute este bloco também como migração se o schema já existe.
-- ==========================================================
alter table public.profissionais add column if not exists whatsapp text, add column if not exists whatsapp_opt_in boolean not null default false;
alter table public.profissionais drop constraint if exists profissionais_whatsapp_digits_check;
alter table public.profissionais add constraint profissionais_whatsapp_digits_check check (whatsapp is null or whatsapp ~ '^[0-9]{10,15}$');
create table if not exists public.avaliacoes_funcionarios(id uuid primary key default gen_random_uuid(),agendamento_id uuid not null unique references public.agendamentos(id) on delete cascade,profissional_id uuid not null references public.profissionais(id) on delete cascade,nota integer not null check(nota between 1 and 5),comentario text check(comentario is null or length(comentario)<=500),created_at timestamptz not null default now());
alter table public.avaliacoes_funcionarios enable row level security;
drop policy if exists "admins read staff reviews" on public.avaliacoes_funcionarios;
create policy "admins read staff reviews" on public.avaliacoes_funcionarios for select to authenticated using(public.is_admin());
grant select on public.avaliacoes_funcionarios to authenticated;
create or replace function public.get_public_staff() returns table(id uuid,nome text,tipo text,media_avaliacoes numeric,total_avaliacoes bigint) language sql stable security definer set search_path=public as $$ select p.id,p.nome,p.tipo,coalesce(round(avg(r.nota)::numeric,1),0),count(r.id) from public.profissionais p left join public.avaliacoes_funcionarios r on r.profissional_id=p.id where p.ativo=true group by p.id,p.nome,p.tipo,p.ordem order by p.ordem,p.nome $$;
revoke all on function public.get_public_staff() from public;
grant execute on function public.get_public_staff() to anon,authenticated;
create or replace function public.submit_staff_review(p_code text,p_phone text,p_rating integer,p_comment text default null) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_booking public.agendamentos%rowtype; v_staff_name text; v_phone text;
begin
 if p_rating is null or p_rating<1 or p_rating>5 then return jsonb_build_object('success',false,'message','A nota precisa ser de 1 a 5.'); end if;
 v_phone:=regexp_replace(coalesce(p_phone,''),'[^0-9]','','g');
 select a.* into v_booking from public.agendamentos a join public.clientes c on c.id=a.cliente_id where upper(a.codigo)=upper(trim(coalesce(p_code,''))) and regexp_replace(c.telefone,'[^0-9]','','g')=v_phone;
 if not found then return jsonb_build_object('success',false,'message','Não encontramos uma reserva com esse código e WhatsApp.'); end if;
 if v_booking.status<>'concluido' then return jsonb_build_object('success',false,'message','A avaliação ficará disponível depois que o atendimento for marcado como concluído.'); end if;
 select nome into v_staff_name from public.profissionais where id=v_booking.profissional_id;
 insert into public.avaliacoes_funcionarios(agendamento_id,profissional_id,nota,comentario) values(v_booking.id,v_booking.profissional_id,p_rating,nullif(trim(coalesce(p_comment,'')),''));
 return jsonb_build_object('success',true,'profissional',v_staff_name);
exception when unique_violation then return jsonb_build_object('success',false,'message','Esta reserva já recebeu uma avaliação.'); end $$;
revoke all on function public.submit_staff_review(text,text,integer,text) from public;
grant execute on function public.submit_staff_review(text,text,integer,text) to anon,authenticated;
create or replace function public.get_staff_performance() returns table(profissional_id uuid,nome text,tipo text,atendimentos_concluidos bigint,rendimento_bruto numeric,media_avaliacoes numeric,total_avaliacoes bigint) language plpgsql stable security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'Acesso restrito à administradora.'; end if;
 return query select p.id,p.nome,p.tipo,count(a.id) filter(where a.status='concluido'),coalesce(sum(s.preco) filter(where a.status='concluido'),0)::numeric(12,2),coalesce((select round(avg(r.nota)::numeric,1) from public.avaliacoes_funcionarios r where r.profissional_id=p.id),0),(select count(*) from public.avaliacoes_funcionarios r where r.profissional_id=p.id) from public.profissionais p left join public.agendamentos a on a.profissional_id=p.id left join public.servicos s on s.id=a.servico_id where p.tipo in ('admin','funcionario') group by p.id,p.nome,p.tipo,p.ordem order by count(a.id) filter(where a.status='concluido') desc,coalesce(sum(s.preco) filter(where a.status='concluido'),0) desc,p.nome;
end $$;
revoke all on function public.get_staff_performance() from public,anon;
grant execute on function public.get_staff_performance() to authenticated;
revoke select on public.profissionais from anon;
grant select(id,nome,tipo,ativo,ordem,created_at) on public.profissionais to anon;
grant select on public.profissionais to authenticated;
drop policy if exists "staff read booked services" on public.servicos;
create policy "staff read booked services" on public.servicos for select to authenticated using(exists(select 1 from public.agendamentos a join public.profissionais p on p.id=a.profissional_id where a.servico_id=servicos.id and p.auth_user_id=auth.uid()));



-- ========================================================
-- STUDIO BETH'S DESIGNERS — ATUALIZAÇÕES CONSOLIDADAS
-- Não apaga agendamentos ou históricos. Para banco existente.
-- Execute no projeto correto, com backup realizado.
-- ========================================================

-- WhatsApp individual
-- Studio Beth's Designers | Correção do roteamento do WhatsApp por profissional
-- Execute SOMENTE este arquivo no SQL Editor do projeto Supabase já configurado.
-- Não recrie as tabelas nem execute o schema.sql completo.

-- Mantém a migração compatível caso as colunas ainda não estejam presentes.
alter table public.profissionais
  add column if not exists whatsapp text,
  add column if not exists whatsapp_opt_in boolean not null default false;

-- O público NÃO precisa ter acesso a todos os números das funcionárias.
-- Esta função retorna o contato apenas para uma reserva existente e validada,
-- vinculada à profissional escolhida e ao telefone informado pela cliente.
create or replace function public.get_booking_whatsapp(p_code text, p_phone text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_number text;
  v_opt_in boolean;
  v_type text;
  v_client_phone text;
begin
  if nullif(trim(coalesce(p_code, '')), '') is null
     or nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), '') is null then
    return jsonb_build_object('success', false, 'message', 'Informe o código e o telefone da reserva.');
  end if;

  select p.whatsapp, p.whatsapp_opt_in, p.tipo, c.telefone
    into v_number, v_opt_in, v_type, v_client_phone
  from public.agendamentos a
  join public.clientes c on c.id = a.cliente_id
  join public.profissionais p on p.id = a.profissional_id
  where upper(a.codigo) = upper(trim(p_code))
  limit 1;

  if not found or
     regexp_replace(coalesce(v_client_phone, ''), '[^0-9]', '', 'g') <>
     regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g') then
    return jsonb_build_object('success', false, 'message', 'Reserva não encontrada ou telefone não confere.');
  end if;

  if v_type = 'admin' then
    -- Somente quando A ADMINISTRADORA foi a profissional escolhida,
    -- seu contato pode usar o WhatsApp público geral do estúdio.
    if nullif(regexp_replace(coalesce(v_number, ''), '[^0-9]', '', 'g'), '') is null then
      select whatsapp into v_number from public.configuracoes
      order by updated_at desc limit 1;
    end if;
  elsif v_opt_in is not true then
    return jsonb_build_object('success', false, 'message', 'A profissional ainda não autorizou contatos por WhatsApp.');
  end if;

  v_number := regexp_replace(coalesce(v_number, ''), '[^0-9]', '', 'g');
  if v_number !~ '^[0-9]{10,15}$' then
    return jsonb_build_object('success', false, 'message', 'A profissional está sem um WhatsApp válido cadastrado.');
  end if;

  return jsonb_build_object('success', true, 'whatsapp', v_number);
end;
$$;

revoke all on function public.get_booking_whatsapp(text,text) from public, anon, authenticated;
grant execute on function public.get_booking_whatsapp(text,text) to anon, authenticated;

-- Conferência administrativa (opcional):
-- select id, nome, tipo, whatsapp, whatsapp_opt_in from public.profissionais order by nome;


-- Confirmação/cancelamento/conclusão pela equipe
-- Studio Beth's Designers: confirmar, cancelar e concluir apenas os próprios atendimentos.
-- Migração incremental: executar APENAS este arquivo no SQL Editor do Supabase.
-- NÃO execute novamente schema.sql e NÃO conceda UPDATE direto à equipe.

create or replace function public.staff_update_booking_status(
  p_booking_id uuid,
  p_new_status text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_staff_id uuid;
  v_booking public.agendamentos%rowtype;
begin
  -- O Supabase identifica a conta a partir da sessão, não de um ID enviado pelo navegador.
  if auth.uid() is null then
    return jsonb_build_object('success', false, 'message', 'Faça login novamente.');
  end if;

  -- Somente profissionais ATIVOS do tipo funcionário podem usar esta função.
  select p.id into v_staff_id
  from public.profissionais p
  where p.auth_user_id = auth.uid()
    and p.tipo = 'funcionario'
    and p.ativo is true
  limit 1;

  if v_staff_id is null then
    return jsonb_build_object('success', false, 'message', 'Seu perfil de funcionário está inativo ou não foi encontrado.');
  end if;

  if p_new_status is null or p_new_status not in ('confirmado', 'cancelado', 'concluido') then
    return jsonb_build_object('success', false, 'message', 'Status não permitido.');
  end if;

  -- Trava a reserva durante a atualização para impedir ações simultâneas conflitantes.
  -- A associação com v_staff_id impede modificar a agenda de outro profissional.
  select a.* into v_booking
  from public.agendamentos a
  where a.id = p_booking_id and a.profissional_id = v_staff_id
  for update;

  if not found then
    return jsonb_build_object('success', false, 'message', 'Agendamento não encontrado na sua agenda.');
  end if;

  -- O atendimento precisa ser confirmado antes de ser concluído.
  -- Agendamentos cancelados ou concluídos não podem ser reabertos pela equipe.
  if not (
    (v_booking.status = 'pendente' and p_new_status in ('confirmado', 'cancelado'))
    or (v_booking.status = 'confirmado' and p_new_status in ('cancelado', 'concluido'))
  ) then
    return jsonb_build_object('success', false, 'message',
      'Esta alteração não é permitida para o status atual. Atualize sua agenda.');
  end if;

  update public.agendamentos
  set status = p_new_status,
      updated_at = now()
  where id = v_booking.id;

  return jsonb_build_object('success', true, 'status', p_new_status);
end;
$$;

-- Funções PostgreSQL têm EXECUTE para PUBLIC por padrão: revoga e libera somente
-- usuários autenticados. A função exige uma conta de funcionário ativo.
revoke all on function public.staff_update_booking_status(uuid, text) from public, anon, authenticated;
grant execute on function public.staff_update_booking_status(uuid, text) to authenticated;

-- O RLS do esquema existente continua protegendo as consultas:
-- staff read own appointments = SELECT apenas dos próprios agendamentos.
-- admins manage bookings = administradora continua com todas as ações.
-- Não criar policy de UPDATE para funcionários: isso poderia permitir editar outros campos.

-- Solicita atualização do cache de funções da API Supabase/PostgREST.
notify pgrst, 'reload schema';


-- Arquivamento de profissionais
-- STUDIO BETH'S DESIGNERS — Remoção segura de profissionais com histórico
-- Compatível com o projeto existente. Execute apenas este SQL, não o schema.sql inteiro.
-- A conta administrativa pode arquivar um(a) funcionário(a), mesmo que tenha
-- agendamentos concluídos/cancelados. O histórico financeiro é preservado.

alter table public.profissionais
  add column if not exists arquivado_em timestamptz;

-- Bloqueia, inclusive para atualizações manuais, a reativação acidental
-- de profissionais já removidos.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'profissionais_arquivado_inativo_check'
      and conrelid = 'public.profissionais'::regclass
  ) then
    alter table public.profissionais
      add constraint profissionais_arquivado_inativo_check
      check (arquivado_em is null or ativo is false);
  end if;
end;
$$;

create or replace function public.arquivar_profissional(p_profissional_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profissional public.profissionais%rowtype;
  v_abertos bigint;
begin
  if auth.uid() is null or not public.is_admin() then
    return jsonb_build_object('success',false,'message','Apenas a conta administradora pode remover funcionários.');
  end if;

  -- Impede conflitos com outra remoção/edição simultânea.
  select * into v_profissional
    from public.profissionais p
   where p.id = p_profissional_id
   for update;

  if not found then
    return jsonb_build_object('success',false,'message','Profissional não encontrado.');
  end if;
  if v_profissional.tipo <> 'funcionario' then
    return jsonb_build_object('success',false,'message','A administradora não pode ser removida por esta função.');
  end if;
  if v_profissional.arquivado_em is not null then
    return jsonb_build_object('success',true,'message','O profissional já foi removido.');
  end if;

  -- Não interrompe nem cancela agendamentos de clientes silenciosamente.
  -- O admin deve confirmar/concluir ou cancelar os que ainda estejam abertos.
  select count(*) into v_abertos
    from public.agendamentos a
   where a.profissional_id = p_profissional_id
     and a.status in ('pendente','confirmado');

  if v_abertos > 0 then
    return jsonb_build_object(
      'success', false,
      'message', format('Há %s agendamento(s) pendente(s) ou confirmado(s) para este profissional. Conclua ou cancele essas reservas no painel antes de remover a conta.',v_abertos)
    );
  end if;

  -- Desvincular auth_user_id bloqueia inclusive a leitura dos dados antigos
  -- por quem ainda tenha uma sessão aberta no Supabase Auth.
  update public.profissionais
     set ativo = false,
         arquivado_em = now(),
         auth_user_id = null,
         username = null,
         whatsapp = null,
         whatsapp_opt_in = false
   where id = p_profissional_id;

  -- QR Codes/convites não usados deixam de funcionar.
  delete from public.convites_funcionarios c
   where c.profissional_id = p_profissional_id;

  -- NÃO apaga agendamentos, avaliações, clientes ou receitas.
  return jsonb_build_object('success',true,'message','Profissional removido com histórico preservado.');
end;
$$;

revoke all on function public.arquivar_profissional(uuid) from public, anon, authenticated;
grant execute on function public.arquivar_profissional(uuid) to authenticated;

notify pgrst, 'reload schema';


notify pgrst, 'reload schema';
