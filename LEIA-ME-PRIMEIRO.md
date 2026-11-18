# Studio Beth's Designers — site e sistema de agendamento completo

**Projeto independente, não conectado ao Studio Manu Lima nem à Daysileny.** Nova identidade **Rosa Borboleta**, baseada nas imagens de referência recebidas. Imagens fotográficas são ILUSTRATIVAS (não mostram atendimentos reais do estabelecimento). Este é um pacote de código, que exige implantação e integração com Supabase.

## Dados preservados do arquivo original

- Nome: **Studio Beth's Designers**
- WhatsApp: **+55 22 98833-4019** — https://wa.me/5522988334019
- Endereço: **R. Mário Vasconcelos, 60 - loja 01 - Centro, Araruama - RJ, 28979-132**
- Link original do Google Maps: **https://maps.google.com/?cid=12011292072847203588&g_mp=Cidnb29nbGUubWFwcy5wbGFjZXMudjEuUGxhY2VzLlNlYXJjaFRleHQQAhgEIAA**
- Avaliação exibida no site anterior: **4,9/5, em 32 avaliações**, preservada como texto informado no arquivo recebido, não verificada em tempo real.
- Depoimento tal como apresentado: **“Atendimento excelente e resultado acima do esperado.”**, atribuído genericamente a **Cliente satisfeito · Google**. Não inventar outros testemunhos.
- As imagens de tabela de preços fornecidas estão em `referencias-cardapio/` para conferência.
- As formas de pagamento das imagens são **PIX, dinheiro e cartões de crédito/débito**, com **taxa da máquina** para cartão.

## Lista integral de serviços e preços dos anexos

| Serviço | Preço |
|---|---:|
| Unhas de gel | R$ 120,00 |
| Unhas de fibra | R$ 160,00 |
| Manutenção (gel) | R$ 80,00 |
| Manutenção (fibra) | R$ 100,00 |
| Banho de gel | R$ 70,00 |
| Esmaltação em gel | R$ 30,00 |
| Spa dos pés | R$ 90,00 |
| Pé e mão | R$ 45,00 |
| Mão | R$ 26,00 |
| Pé | R$ 28,00 |
| Pé e mão c/ francesinha | R$ 50,00 |
| Pé c/ francesinha | R$ 33,00 |
| Mão c/ francesinha | R$ 31,00 |
| Mão c/ esmaltação em gel | R$ 50,00 |

**ATENÇÃO:** o arquivo original não informava dias ou horário de atendimento nem duração de cada serviço. Por isso, a agenda vem **inteiramente desativada** e não são publicados horários como fatos. A tabela `servicos` recebe durações **estimadas**, que a administração deve revisar antes de ativar a agenda. Não foram inventados nomes de funcionários nem Instagram.

## Implantação em Supabase EXCLUSIVO

1. Crie **um novo projeto Supabase** da Studio Beth's Designers. Não use o banco de outra loja.
2. Em **SQL Editor**, execute **somente `supabase/INSTALACAO-NOVA.sql`** num projeto novo. Ele inclui schema, RLS, migrações e `CONTEUDO-BETH.sql` (NÃO execute este separadamente no primeiro setup). `schema.sql`, `ATUALIZAR-PROJETO-EXISTENTE.sql` e `migrations/` são referências para manutenção, não passos adicionais da instalação nova.
3. Em **Authentication → Users**, crie a conta da administradora (email real, senha forte, email confirmado). Copie o ID UUID dessa conta.
4. No SQL Editor execute, alterando o UUID para o UID REAL da administradora:
   ```sql
   insert into public.admins(user_id) values ('UUID-DA-ADMINISTRADORA')
   on conflict(user_id) do nothing;
   ```
   O trigger cria o perfil de profissional admin. No painel, preencha o nome e WhatsApp correto dessa profissional.
5. Preencha `config.js` com a **Project URL** e a **publishable key/anon key** do novo Supabase. Nunca exponha `service_role`, secrets, senha nem tokens de acesso no `config.js`.
6. Publique três **Edge Functions**: `create-staff-invite`, `complete-staff-invite` e `manage-admins` (arquivos em `supabase/functions/`). Configure variáveis seguras `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`, `SUPABASE_ANON_KEY` conforme disponibilidade do projeto; use `SITE_URL` com o endereço HTTPS publicado do novo site. Na função `complete-staff-invite`, desative a verificação JWT de gateway conforme o projeto Supabase e mantenha a validação interna de token de convite, sem alterar os privilégios da função. As funções de administração fazem verificação de permissão em servidor.
7. Configure **Authentication → URL Configuration → Site URL** com a URL HTTPS do novo site. Faça deploy dos arquivos (`index.html`, `config.js`, `app.js`, CSS, `assets/`, HTMLs dos painéis) como arquivos estáticos, mantendo os caminhos relativos.
8. Acesse `admin.html`: cadastre e revise profissionais e WhatsApps, **confirme as durações** dos 14 serviços e **ative os dias e horários reais** em Disponibilidade. Confira endereço, contato e galeria. Convide funcionários por QR Code (uso único, expira após 30 minutos), cada um acessa `funcionario.html`. O banco deve ter ao menos um profissional ativo e com contato para receber pedidos.
9. Antes de publicar oficialmente, teste em Supabase real: agendar, bloquear sobreposição, confirmar, cancelar, concluir, avaliar, gerir profissionais, arquivar contas, emitir QR Code e conferir permissões RLS, estoque de horários, resultados e mapa. Os testes locais de código NÃO substituem os testes reais.

## Mensagens WhatsApp — EXCLUSIVAMENTE manuais

O sistema **não contém `notify-staff-booking`**, não envia WhatsApp automático nem chama API externa de mensageria. Ao registrar a reserva com sucesso no Supabase, a cliente vê um modal com dados e código. A aplicação consulta `get_booking_whatsapp(código, telefone)` para o telefone da profissional da reserva e cria um link `wa.me`. **A cliente precisa tocar no botão e depois enviar a mensagem no WhatsApp.** Caso o WhatsApp individual não esteja disponível, ela recebe orientação para contatar a loja; não há redirecionamento silencioso para a administradora.

## Organização dos arquivos

- `index.html`, `styles.css`, `app.js`, `config.js` — vitrine, serviços, horário, reservas, WhatsApp manual e avaliações.
- `admin.html`, `admin.js`, `admin.css`, `admin-users.css`, `brand-admin.css` — administração de equipe, serviços, galeria, agenda, ganhos estimados, avaliações, configurações e contas.
- `funcionario.html`, `funcionario.js` — acesso individual às próprias reservas, status e mural.
- `cadastro-funcionario.html`, `cadastro-funcionario.js` — cadastro por QR Code e convite.
- `assets/` — identidade (SVG) e fotos ilustrativas produzidas para este site, sem dependência de URL de imagem externa.
- `referencias-cardapio/` — duas imagens de tabelas de valores recebidas.
- `supabase/INSTALACAO-NOVA.sql` — implantação integral em banco novo.
- `supabase/CONTEUDO-BETH.sql` — seed separado, já incorporado ao SQL integral.
- `supabase/functions/` — três funções Edge; não há função de envio automático.

## Limitações conhecidas

É necessário configurar Supabase, login admin, equipe, permissões, site HTTPS e horários reais. Antes dessa configuração, o site oferece vitrine visual e não simula gravação de reservas. O mapa incorporado depende da política do Google, mas há botão externo para rotas. Valores financeiros do painel são estimativas, e não processamento de pagamentos. O tratamento dos dados deve observar a LGPD; configure backups e controles de acesso.
