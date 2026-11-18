-- MIGRAÇÃO HISTÓRICA (01–04). SE JÁ CONFIGURADO, EXECUTE SOMENTE migrations/05-...sql.
-- ========================================================
-- STUDIO BETH'S DESIGNERS — ATUALIZAÇÕES CONSOLIDADAS
-- Não apaga agendamentos ou históricos. Para banco existente.
-- Execute no projeto correto, com backup realizado.
-- ========================================================

-- 1. Roteamento do WhatsApp individual
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


-- 2. Ações permitidas no painel dos funcionários
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


-- 3. Arquivamento de profissionais com histórico preservado
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


-- 4. Indicadores de rendimentos (recria a mesma RPC, se já existente)
-- STUDIO BETH'S DESIGNERS | Correção opcional da função de rendimentos
-- Execute SOMENTE se a função get_staff_performance não existir no Supabase
-- do seu site ou se você ainda não tiver publicado essa parte do schema.sql.
-- Este script não apaga atendimentos, serviços, funcionários ou avaliações.
-- Requer as tabelas já existentes e a função public.is_admin() do projeto.

create or replace function public.get_staff_performance() returns table(profissional_id uuid,nome text,tipo text,atendimentos_concluidos bigint,rendimento_bruto numeric,media_avaliacoes numeric,total_avaliacoes bigint) language plpgsql stable security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'Acesso restrito à administradora.'; end if;
 return query select p.id,p.nome,p.tipo,count(a.id) filter(where a.status='concluido'),coalesce(sum(s.preco) filter(where a.status='concluido'),0)::numeric(12,2),coalesce((select round(avg(r.nota)::numeric,1) from public.avaliacoes_funcionarios r where r.profissional_id=p.id),0),(select count(*) from public.avaliacoes_funcionarios r where r.profissional_id=p.id) from public.profissionais p left join public.agendamentos a on a.profissional_id=p.id left join public.servicos s on s.id=a.servico_id where p.tipo in ('admin','funcionario') group by p.id,p.nome,p.tipo,p.ordem order by count(a.id) filter(where a.status='concluido') desc,coalesce(sum(s.preco) filter(where a.status='concluido'),0) desc,p.nome;
end $$;
revoke all on function public.get_staff_performance() from public,anon;
grant execute on function public.get_staff_performance() to authenticated;


notify pgrst, 'reload schema';
