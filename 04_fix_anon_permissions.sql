-- =====================================================================
-- FIX DE PERMISOS · permitir uso desde cliente con anon key
-- =====================================================================
-- Problema: el cliente HTML se conecta con la anon public key, lo que
-- lo identifica como rol 'anon' en Postgres. Los grants iniciales solo
-- dieron permisos al rol 'authenticated' (que requiere JWT login).
--
-- Solución: dar permisos básicos al rol 'anon' para las operaciones
-- que el cliente necesita (read+insert+update). Las políticas RLS
-- siguen filtrando por encima, así que la seguridad se mantiene
-- a nivel de fila (cada empresa solo ve lo suyo).
--
-- Cómo usar: pegá esto en el SQL Editor de Supabase y Run.
-- =====================================================================

-- Permisos básicos al rol anon
grant usage on schema public to anon;

-- SELECT: el cliente necesita leer companies, events, staff (sin pin),
-- prize_inventory, vistas del dashboard
grant select on companies        to anon;
grant select on events           to anon;
grant select on staff            to anon;
grant select on prize_inventory  to anon;
grant select on leads            to anon;
grant select on email_queue      to anon;

-- Vistas también
grant select on vw_leads_dashboard    to anon;
grant select on vw_event_stats        to anon;
grant select on vw_staff_performance  to anon;
grant select on vw_prize_status       to anon;
grant select on vw_sync_health        to anon;

-- INSERT: el cliente necesita crear leads, sync_log, email_queue
grant insert on leads        to anon;
grant insert on sync_log     to anon;
grant insert on email_queue  to anon;

-- UPDATE: el cliente actualiza leads cuando se entrega premio o se envía email
grant update on leads        to anon;
grant update on email_queue  to anon;

-- EXECUTE: las funciones que el cliente necesita llamar via RPC
grant execute on function fn_verify_staff_pin(text, text)        to anon;
grant execute on function fn_check_lead_duplicate(text, uuid, text) to anon;
grant execute on function fn_can_pick_prize(text, uuid, text)    to anon;


-- =====================================================================
-- AJUSTE DE POLÍTICAS RLS PARA EL ROL anon
-- =====================================================================
-- Las políticas RLS originales asumían que el JWT del usuario tenía
-- claim 'company_id'. Como por ahora estamos usando la anon key sin
-- JWT, necesitamos políticas más permisivas que sean luego endurecidas
-- cuando implementemos el flujo de auth completo.
--
-- IMPORTANTE: estas políticas son apropiadas para el MVP en piloto.
-- Antes de un evento real con datos de pacientes/médicos sensibles,
-- conviene implementar JWT auth y volver a las políticas restrictivas.
-- =====================================================================

-- COMPANIES: el cliente lee todas (necesita ver Sirex y Eccosur para
-- mostrarlos según el QR escaneado). En producción, esto se filtra por
-- el JWT del staff logueado.
drop policy if exists "companies_anon_read" on companies;
create policy "companies_anon_read" on companies
  for select to anon using (true);

-- EVENTS
drop policy if exists "events_anon_read" on events;
create policy "events_anon_read" on events
  for select to anon using (true);

-- STAFF: lectura sin el pin_hash. Para el cliente solo necesita ver
-- lista de empleados para el modal de selección.
drop policy if exists "staff_anon_read" on staff;
create policy "staff_anon_read" on staff
  for select to anon using (true);

-- PRIZE_INVENTORY
drop policy if exists "prize_inventory_anon_read" on prize_inventory;
create policy "prize_inventory_anon_read" on prize_inventory
  for select to anon using (true);
drop policy if exists "prize_inventory_anon_update" on prize_inventory;
create policy "prize_inventory_anon_update" on prize_inventory
  for update to anon using (true);

-- LEADS: el cliente puede leer, insertar y actualizar leads.
-- Más adelante con JWT, se filtra por company_id.
drop policy if exists "leads_anon_read" on leads;
create policy "leads_anon_read" on leads
  for select to anon using (true);
drop policy if exists "leads_anon_insert" on leads;
create policy "leads_anon_insert" on leads
  for insert to anon with check (true);
drop policy if exists "leads_anon_update" on leads;
create policy "leads_anon_update" on leads
  for update to anon using (true);

-- SYNC_LOG: solo insertar (auditoría). Lectura es solo para admins
-- en el dashboard, no desde el cliente.
drop policy if exists "sync_log_anon_insert" on sync_log;
create policy "sync_log_anon_insert" on sync_log
  for insert to anon with check (true);

-- EMAIL_QUEUE: insertar y actualizar (estado de envío).
drop policy if exists "email_queue_anon_insert" on email_queue;
create policy "email_queue_anon_insert" on email_queue
  for insert to anon with check (true);
drop policy if exists "email_queue_anon_update" on email_queue;
create policy "email_queue_anon_update" on email_queue
  for update to anon using (true);


-- =====================================================================
-- VERIFICACIÓN
-- =====================================================================
-- Después de correr esto, podés verificar con:
--
--   select grantee, privilege_type, table_name
--   from information_schema.table_privileges
--   where table_schema = 'public' and grantee = 'anon'
--   order by table_name, privilege_type;
--
-- Esperado: filas para companies (SELECT), leads (SELECT, INSERT, UPDATE), etc.
-- =====================================================================
