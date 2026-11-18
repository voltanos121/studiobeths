import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Método não permitido." }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const authHeader = req.headers.get("Authorization") || "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "Sessão não encontrada. Entre novamente." }, 401);

  const callerClient = createClient(url, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const adminClient = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Nunca confiar em IDs, e-mails ou papéis enviados pelo navegador.
  const { data: authData, error: authError } = await callerClient.auth.getUser(token);
  if (authError || !authData.user) return json({ error: "Sessão inválida ou expirada." }, 401);
  const callerId = authData.user.id;

  const { data: permission, error: permissionError } = await adminClient
    .from("admins").select("user_id").eq("user_id", callerId).maybeSingle();
  if (permissionError || !permission) return json({ error: "Acesso restrito a administradores." }, 403);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: "Corpo da solicitação inválido." }, 400); }
  const action = String(body.action || "");

  try {
    if (action === "list") {
      const allUsers: any[] = [];
      for (let page = 1; page <= 20; page++) {
        const { data, error } = await adminClient.auth.admin.listUsers({ page, perPage: 100 });
        if (error) throw error;
        allUsers.push(...data.users);
        if (data.users.length < 100) break;
      }
      const { data: adminRows, error } = await adminClient.from("admins").select("user_id");
      if (error) throw error;
      const ids = new Set((adminRows || []).map((r: { user_id: string }) => r.user_id));
      const users = allUsers.filter((u) => ids.has(u.id)).map((u) => ({
        id: u.id,
        email: u.email || "",
        name: String(u.user_metadata?.full_name || u.user_metadata?.name || ""),
        created_at: u.created_at,
      })).sort((a, b) => a.email.localeCompare(b.email));
      return json({ users });
    }

    // Arquiva funcionários sem excluir os agendamentos antigos, revogando o login Auth.
    // Repetir a operação conclui uma exclusão de Auth que tenha falhado anteriormente.
    if (action === "archive_staff") {
      const staffId = String(body.staff_id || "");
      if (!/^[a-f0-9-]{36}$/i.test(staffId)) return json({ error: "Profissional inválido." }, 400);
      const { data: staff, error: staffError } = await adminClient.from("profissionais")
        .select("id,nome,tipo,auth_user_id,auth_user_id_arquivado,arquivado_em")
        .eq("id", staffId).maybeSingle();
      if (staffError) throw staffError;
      if (!staff || staff.tipo !== "funcionario") return json({ error: "Funcionário não encontrado." }, 404);
      if (!staff.arquivado_em) {
        // Roda com a sessão do administrador; a função SQL trava a linha e
        // impede arquivar qualquer pessoa com reservas ainda abertas.
        const { data: result, error: archiveError } = await callerClient.rpc(
          "arquivar_profissional", { p_profissional_id: staffId });
        if (archiveError) throw archiveError;
        if (!result?.success) return json({ error: result?.message || "Não foi possível arquivar." }, 409);
      }
      const oldUserId = staff.auth_user_id || staff.auth_user_id_arquivado;
      if (oldUserId) {
        const { data: adminAccount, error: adminCheckError } = await adminClient.from("admins")
          .select("user_id").eq("user_id", oldUserId).maybeSingle();
        if (adminCheckError) throw adminCheckError;
        if (adminAccount) return json({ success: true,
          warning: "O perfil foi arquivado, mas a antiga conta também é administradora. O acesso administrativo não foi excluído por segurança." });
        const { error: deleteError } = await adminClient.auth.admin.deleteUser(oldUserId);
        if (deleteError) {
          return json({ success: true,
            warning: `O perfil foi arquivado, mas a conta Auth precisa de nova tentativa: ${deleteError.message}` });
        }
        const { error: clearError } = await adminClient.from("profissionais")
          .update({ auth_user_id_arquivado: null }).eq("id", staffId);
        if (clearError) {
          return json({ success: true,
            warning: "Login excluído; não foi possível limpar o indicador de exclusão pendente." });
        }
      }
      return json({ success: true });
    }

    const id = String(body.id || "");
    if (action === "create") {
      const name = String(body.name || "").trim();
      const email = String(body.email || "").trim().toLowerCase();
      const password = String(body.password || "");
      if (!name || name.length > 100) return json({ error: "Informe um nome válido (até 100 caracteres)." }, 400);
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ error: "Informe um e-mail válido." }, 400);
      if (password.length < 8) return json({ error: "A senha precisa ter pelo menos 8 caracteres." }, 400);
      const { data: created, error: createError } = await adminClient.auth.admin.createUser({
        email, password, email_confirm: true, user_metadata: { full_name: name },
      });
      if (createError || !created.user) throw createError || new Error("Não foi possível criar a conta.");
      const { error: insertError } = await adminClient.from("admins").insert({ user_id: created.user.id });
      if (insertError) {
        await adminClient.auth.admin.deleteUser(created.user.id);
        throw insertError;
      }
      return json({ success: true, id: created.user.id });
    }

    if (!id) return json({ error: "Identificador do administrador não informado." }, 400);
    const { data: target, error: targetError } = await adminClient.from("admins").select("user_id").eq("user_id", id).maybeSingle();
    if (targetError || !target) return json({ error: "Administrador não encontrado." }, 404);

    if (action === "update") {
      const update: Record<string, unknown> = {};
      if (body.name !== undefined) {
        const name = String(body.name).trim();
        if (!name || name.length > 100) return json({ error: "Informe um nome válido (até 100 caracteres)." }, 400);
        const { data: existing } = await adminClient.auth.admin.getUserById(id);
        update.user_metadata = { ...(existing.user?.user_metadata || {}), full_name: name };
      }
      if (body.email !== undefined) {
        const email = String(body.email).trim().toLowerCase();
        if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ error: "Informe um e-mail válido." }, 400);
        update.email = email;
        update.email_confirm = true;
      }
      if (body.password !== undefined && String(body.password).length > 0) {
        if (String(body.password).length < 8) return json({ error: "A nova senha precisa ter pelo menos 8 caracteres." }, 400);
        update.password = String(body.password);
      }
      if (Object.keys(update).length === 0) return json({ error: "Nenhuma alteração foi informada." }, 400);
      const { error } = await adminClient.auth.admin.updateUserById(id, update);
      if (error) throw error;
      return json({ success: true });
    }

    if (action === "delete") {
      if (id === callerId) return json({ error: "Por segurança, você não pode excluir a própria conta enquanto está conectado." }, 400);
      const { count, error: countError } = await adminClient.from("admins").select("user_id", { count: "exact", head: true });
      if (countError) throw countError;
      if ((count || 0) <= 1) return json({ error: "O último administrador não pode ser excluído." }, 400);
      // Um administrador também pode aparecer na agenda pública como profissional.
      // Não deixe novas reservas serem criadas para uma conta removida.
      const { data: profiles, error: profilesError } = await adminClient.from("profissionais")
        .select("id,ativo").eq("auth_user_id", id);
      if (profilesError) throw profilesError;
      const profileIds = (profiles || []).map(p => p.id);
      if (profileIds.length) {
        const { count: openCount, error: openError } = await adminClient.from("agendamentos")
          .select("id", { count: "exact", head: true })
          .in("profissional_id", profileIds).in("status", ["pendente", "confirmado"]);
        if (openError) throw openError;
        if ((openCount || 0) > 0) return json({ error:
          "Há reservas pendentes ou confirmadas nesta agenda. Resolva-as antes de excluir a conta." }, 409);
        const { error: deactivateError } = await adminClient.from("profissionais")
          .update({ ativo: false }).in("id", profileIds);
        if (deactivateError) throw deactivateError;
      }
      // Convites foram criados pela conta que sairá; invalidá-los evita FK impedir o delete.
      const { error: invitesError } = await adminClient.from("convites_funcionarios")
        .delete().eq("criado_por", id);
      if (invitesError) throw invitesError;
      const { error: removeRoleError } = await adminClient.from("admins").delete().eq("user_id", id);
      if (removeRoleError) {
        if (profileIds.length) await adminClient.from("profissionais").update({ ativo: true }).in("id", profileIds);
        throw removeRoleError;
      }
      const { error: deleteUserError } = await adminClient.auth.admin.deleteUser(id);
      if (deleteUserError) {
        await adminClient.from("admins").insert({ user_id: id });
        // O perfil permanece inativo se houver erro: evita recebimento de reservas
        // para um administrador que o sistema tentou retirar.
        throw new Error(`A conta Auth não foi excluída. Permissão administrativa restaurada; reavalie o perfil de atendimento. ${deleteUserError.message}`);
      }
      return json({ success: true });
    }

    return json({ error: "Ação não reconhecida." }, 400);
  } catch (error) {
    console.error("manage-admins:", error);
    return json({ error: error instanceof Error ? error.message : "Erro interno ao gerenciar administradores." }, 400);
  }
});
