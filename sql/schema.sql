-- Triagem inteligente de e-mails suspeitos (phishing) - esquema do banco (Supabase / PostgreSQL)
-- Execute no SQL Editor do Supabase, na ordem em que aparece.
-- Dados do projeto são fictícios. Não grave o corpo dos e-mails nem dados pessoais.

-- 1) Log de execuções: uma linha por etapa (virustotal, gemini, fluxo, validacao, roteamento, erro_workflow)
create table public.execucoes_log (
  id bigint generated always as identity not null,
  criado_em timestamp with time zone null default now(),
  execucao_id text null,
  etapa text null,
  status text null,
  duracao_ms integer null,
  erro text null,          -- apenas um código curto, nunca o texto completo do erro
  modelo text null,
  tokens integer null,
  constraint execucoes_log_pkey primary key (id),
  constraint execucoes_log_status_check check (
    status = any (array['sucesso'::text, 'erro'::text, 'fallback'::text])
  )
) tablespace pg_default;

-- 2) Incidentes: uma linha por e-mail reportado (sem o corpo do e-mail)
create table public.incidentes (
  id uuid not null default gen_random_uuid(),
  criado_em timestamp with time zone null default now(),
  execucao_id text null,
  dominio_remetente text null,
  assunto text null,       -- já mascarado (CPF, CNPJ, cartão, e-mail, telefone)
  urls jsonb null default '[]'::jsonb,   -- sem a parte depois de "?"
  reputacao jsonb null,
  classificacao text null,
  risco text null,         -- risco final, depois das regras
  indicadores jsonb null default '[]'::jsonb,
  justificativa text null,
  confianca numeric null,  -- número informado pelo próprio modelo, não é probabilidade calibrada
  acao_recomendada text null,
  status text null default 'novo'::text,
  decisao_humana text null,
  constraint incidentes_pkey primary key (id),
  constraint incidentes_classificacao_check check (
    classificacao = any (array[
      'phishing'::text, 'suspeito'::text, 'legitimo'::text,
      'indeterminado'::text, 'dados_incompletos'::text
    ])
  ),
  constraint incidentes_risco_check check (
    risco = any (array['alto'::text, 'medio'::text, 'baixo'::text])
  ),
  constraint incidentes_status_check check (
    status = any (array[
      'novo'::text, 'aguardando_validacao'::text, 'revisao'::text,
      'confirmado'::text, 'falso_positivo'::text
    ])
  )
) tablespace pg_default;

-- 3) Colunas adicionais (histórico de por que o risco mudou e proteção contra duplicidade)
alter table public.incidentes
  add column if not exists submission_id text,
  add column if not exists risco_ia text,
  add column if not exists regras_aplicadas jsonb default '[]'::jsonb,
  add column if not exists divergencia_ia_reputacao boolean default false;

create unique index if not exists incidentes_submission_id_key
  on public.incidentes (submission_id);

-- 4) Row Level Security ligada. O n8n usa a chave secreta do Supabase, que ignora a RLS.
alter table public.incidentes enable row level security;
alter table public.execucoes_log enable row level security;