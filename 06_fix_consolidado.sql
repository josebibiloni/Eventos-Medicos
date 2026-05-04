-- =====================================================================
-- FIX 06 · CONSOLIDADO · drop forzado + permisos sync_log
-- =====================================================================
-- Resuelve dos errores que se ven en el cliente:
--   1) HTTP 409 Conflict al insertar leads (constraint viejo todavía vivo)
--   2) HTTP 401 Unauthorized al insertar sync_log (faltan permisos para anon)
--
-- Cómo usar: pegar TODO en SQL Editor de Supabase y Run.
-- Es idempotente: se puede correr varias veces.
-- =====================================================================


-- =====================================================================
-- PARTE 1 · ELIMINAR TODOS los constraints unique de whatsapp
-- =====================================================================
-- Forzamos el drop de cualquier constraint que existiera de fixes anteriores
drop index if exists uq_lead_whatsapp_event;
drop index if exists uq_lead_whatsapp_event_strict;

-- Verificación: la siguiente query debe devolver 0 filas
-- select count(*) from pg_indexes
-- where tablename = 'leads'
--   and indexname like 'uq_lead_whatsapp%';


-- =====================================================================
-- PARTE 2 · CREAR el constraint moderado
-- =====================================================================
-- Solo aplica a WhatsApps con formato razonable (>= 8 dígitos numéricos)
create unique index if not exists uq_lead_whatsapp_event_strict
  on leads(company_id, event_id, whatsapp_e164)
  where whatsapp_e164 is not null
    and length(regexp_replace(whatsapp_e164, '[^0-9]', '', 'g')) >= 8
    and event_id is not null;


-- =====================================================================
-- PARTE 3 · PERMISOS sync_log para rol anon (faltaba en fix 04)
-- =====================================================================
-- Grants explícitos
grant insert on sync_log to anon;
grant select on sync_log to anon;

-- Política RLS: permitir INSERT desde anon sin filtro
-- (sync_log es de solo escritura desde el cliente, lectura solo del dashboard)
drop policy if exists "sync_log_anon_insert" on sync_log;
create policy "sync_log_anon_insert" on sync_log
  for insert to anon
  with check (true);

drop policy if exists "sync_log_anon_select" on sync_log;
create policy "sync_log_anon_select" on sync_log
  for select to anon
  using (true);


-- =====================================================================
-- VERIFICACIÓN FINAL
-- =====================================================================
-- 1) Índices unique en leads (esperado: solo uq_lead_whatsapp_event_strict)
select indexname, indexdef
from pg_indexes
where tablename = 'leads' and indexname like 'uq_%';

-- 2) Permisos de anon sobre sync_log (esperado: INSERT, SELECT)
select privilege_type
from information_schema.table_privileges
where table_schema = 'public'
  and grantee = 'anon'
  and table_name = 'sync_log';

-- 3) Políticas RLS sobre sync_log (esperado: 2 políticas para anon)
select policyname, cmd, roles
from pg_policies
where tablename = 'sync_log';
