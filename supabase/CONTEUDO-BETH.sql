-- Studio Beth's Designers — conteúdo inicial a partir do HTML original e das DUAS tabelas enviadas.
-- ATENÇÃO: durações são estimativas ajustáveis no painel; a fonte NÃO informa a duração.
-- A fonte também NÃO informa os dias/horários de funcionamento. Agenda desativada por padrão.
insert into public.servicos(nome,descricao,preco,duracao_minutos,imagem_url,ordem,ativo)
select x.nome,x.descricao,x.preco,x.duracao_minutos,x.imagem_url,x.ordem,true
from (values
 ('Unhas de gel', 'Modelagem e acabamento em gel.', 120.00::numeric, 120, 'assets/hero-unhas-rosas.jpg', 1),
 ('Unhas de fibra', 'Alongamento em fibra com acabamento personalizado.', 160.00::numeric, 150, 'assets/alongamento-fibra.jpg', 2),
 ('Manutenção (gel)', 'Manutenção das unhas de gel.', 80.00::numeric, 90, 'assets/aplicacao-gel.jpg', 3),
 ('Manutenção (fibra)', 'Manutenção de alongamento em fibra.', 100.00::numeric, 120, 'assets/francesinha-delicada.jpg', 4),
 ('Banho de gel', 'Camada de gel para acabamento e proteção.', 70.00::numeric, 90, 'assets/aplicacao-gel.jpg', 5),
 ('Esmaltação em gel', 'Esmaltação com acabamento em gel.', 30.00::numeric, 60, 'assets/manicure-rosada.jpg', 6),
 ('Spa dos pés', 'Cuidado e bem-estar para os pés.', 90.00::numeric, 90, 'assets/spa-esmaltes.jpg', 7),
 ('Pé e mão', 'Cuidados clássicos para unhas dos pés e das mãos.', 45.00::numeric, 90, 'assets/manicure-rosada.jpg', 8),
 ('Mão', 'Manicure tradicional.', 26.00::numeric, 60, 'assets/francesinha-delicada.jpg', 9),
 ('Pé', 'Pedicure tradicional.', 28.00::numeric, 60, 'assets/spa-esmaltes.jpg', 10),
 ('Pé e mão c/ francesinha', 'Manicure e pedicure com francesinha.', 50.00::numeric, 90, 'assets/francesinha-delicada.jpg', 11),
 ('Pé c/ francesinha', 'Pedicure com francesinha.', 33.00::numeric, 60, 'assets/spa-esmaltes.jpg', 12),
 ('Mão c/ francesinha', 'Manicure com francesinha.', 31.00::numeric, 60, 'assets/francesinha-delicada.jpg', 13),
 ('Mão c/ esmaltação em gel', 'Manicure com esmaltação em gel.', 50.00::numeric, 60, 'assets/hero-unhas-rosas.jpg', 14)
) x(nome,descricao,preco,duracao_minutos,imagem_url,ordem)
where not exists(select 1 from public.servicos s where lower(s.nome)=lower(x.nome));

insert into public.galeria(titulo,descricao,imagem_url,categoria,ordem,ativo)
select x.titulo,x.descricao,x.imagem_url,x.categoria,x.ordem,true
from (values
 ('Unhas de gel e delicadeza', 'Imagem ilustrativa de nail art', 'assets/hero-unhas-rosas.jpg', 'Gel', 1),
 ('Francesinha romântica', 'Imagem ilustrativa de manicure', 'assets/francesinha-delicada.jpg', 'Manicure', 2),
 ('Aplicação de gel', 'Imagem ilustrativa de procedimento', 'assets/aplicacao-gel.jpg', 'Gel', 3),
 ('Ambiente de beleza', 'Imagem ilustrativa de esmaltes e acessórios', 'assets/espaco-esmaltes.jpg', 'Inspiração', 4),
 ('Rosa nude', 'Imagem ilustrativa de unhas', 'assets/manicure-rosada.jpg', 'Manicure', 5),
 ('Momento de autocuidado', 'Imagem ilustrativa de produtos de manicure', 'assets/spa-esmaltes.jpg', 'Spa', 6)
) x(titulo,descricao,imagem_url,categoria,ordem)
where not exists(select 1 from public.galeria g where g.titulo=x.titulo);

update public.configuracoes set
 nome_estudio='Studio Beth''s Designers',
 descricao='Unhas de gel, fibra, manicure e pedicure com delicadeza e atenção aos detalhes no Centro de Araruama/RJ.',
 whatsapp='5522988334019', telefone='+55 22 98833-4019',
 endereco='R. Mário Vasconcelos, 60 - loja 01 - Centro, Araruama - RJ, 28979-132',
 link_maps='https://maps.google.com/?cid=12011292072847203588&g_mp=Cidnb29nbGUubWFwcy5wbGFjZXMudjEuUGxhY2VzLlNlYXJjaFRleHQQAhgEIAA'
where nome_estudio='Studio Beth''s Designers';
