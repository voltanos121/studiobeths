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
