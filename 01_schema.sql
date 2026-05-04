-- =====================================================================
-- SCHEMA SUPABASE · CAPTURA DE LEADS GAMIFICADA EN FERIAS MÉDICAS
-- =====================================================================
-- Versión: 1.0
-- Fecha:   2026-04-30
-- Autor:   Sirex Médica / Eccosur
--
-- Cómo usar:
--   1. Crear un proyecto en https://app.supabase.com
--   2. Ir a SQL Editor → New query
--   3. Pegar este archivo entero y hacer "Run"
--   4. Verificar que las 6 tablas, vistas y políticas queden creadas
--   5. Después correr 02_seed.sql para cargar datos iniciales
--   6. Después correr 03_views_and_functions.sql para vistas del dashboard
--
-- Idempotencia: este script usa CREATE IF NOT EXISTS / DROP IF EXISTS
-- donde corresponde, así que se puede correr varias veces sin romper.
-- =====================================================================


-- =====================================================================
-- 1. EXTENSIONES NECESARIAS
-- =====================================================================
-- pgcrypto: para gen_random_uuid() y hashing de PINs
-- citext:   para emails case-insensitive (foo@x.com == FOO@x.com)
create extension if not exists pgcrypto;
create extension if not exists citext;


-- =====================================================================
-- 2. TABLA: companies (empresas / tenants)
-- =====================================================================
-- Cada empresa es un tenant aislado. Sirex y Eccosur son ejemplos.
-- Las URLs de los catálogos PDF y la config visual van acá para que
-- el panel admin del cliente pueda traer la config desde el servidor.
-- =====================================================================
create table if not exists companies (
  id          text primary key,                  -- 'sirex', 'eccosur', 'torregal_cl'
  name        text not null,
  color       text default '#1F4E79',            -- color institucional para branding
  countries   text[] default array['AR']::text[],-- ['AR','CL','PE']
  active      boolean default true,
  metadata    jsonb default '{}'::jsonb,         -- libre: logos, configs extra
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);

comment on table companies is 'Tenants del sistema. Cada empresa cliente del distribuidor tiene su row.';
comment on column companies.metadata is 'JSON libre: logos, configs visuales, integraciones específicas.';


-- =====================================================================
-- 3. TABLA: events (cada feria/congreso)
-- =====================================================================
-- Un evento agrupa los leads capturados durante un congreso específico.
-- Ej: "Congreso SAC 2026 · Buenos Aires · 15-17 mayo".
-- Permite reportes tipo "todos los leads del SAC 2026" sin mezclar con
-- otros congresos.
-- =====================================================================
create table if not exists events (
  id           uuid primary key default gen_random_uuid(),
  company_id   text not null references companies(id) on delete cascade,
  name         text not null,                    -- 'Congreso SAC 2026'
  location     text,                             -- 'La Rural, Buenos Aires'
  country      text,                             -- 'AR'
  starts_at    timestamptz,
  ends_at      timestamptz,
  active       boolean default true,             -- false = evento cerrado, no aceptar más leads
  metadata     jsonb default '{}'::jsonb,
  created_at   timestamptz default now(),
  updated_at   timestamptz default now()
);

create index if not exists idx_events_company        on events(company_id);
create index if not exists idx_events_starts_at      on events(starts_at desc);
create index if not exists idx_events_active         on events(active) where active = true;

comment on table events is 'Cada feria/congreso es un evento. Agrupa leads para reportes.';


-- =====================================================================
-- 4. TABLA: staff (empleados del booth)
-- =====================================================================
-- El staff identifica a cada empleado que carga leads. PIN se hashea
-- con bcrypt antes de persistir — NUNCA se guarda en texto plano.
-- En producción, el cliente envía el PIN, el backend lo verifica con
-- crypt() y emite un JWT que después usa para autenticar requests.
-- =====================================================================
create table if not exists staff (
  id          text primary key,                  -- 'sx_001', 'ec_002'
  company_id  text not null references companies(id) on delete cascade,
  name        text not null,
  email       citext,                            -- opcional, case-insensitive
  role        text,                              -- 'Asistente comercial', 'Comercial senior'
  pin_hash    text not null,                     -- bcrypt(pin), NUNCA texto plano
  active      boolean default true,
  last_login  timestamptz,
  metadata    jsonb default '{}'::jsonb,
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);

create index if not exists idx_staff_company        on staff(company_id);
create index if not exists idx_staff_active         on staff(company_id, active) where active = true;

comment on table staff is 'Empleados que cargan leads. PIN siempre hasheado con bcrypt.';
comment on column staff.pin_hash is 'bcrypt(pin). Verificar con: pin_hash = crypt(pin_input, pin_hash)';


-- =====================================================================
-- 5. TABLA: leads (la tabla central)
-- =====================================================================
-- El lead es la entidad central. Cada row representa un médico que
-- pasó por un booth y dejó sus datos.
--
-- Decisiones importantes:
--   - id viene del cliente (no autogenerado): permite idempotencia
--     en sincronización offline. Si el cliente reintenta, no duplica.
--   - captured_at != synced_at: capturado puede ser hace 2 horas offline,
--     sincronizado es ahora. Útil para analizar latencia de sincronización.
--   - staff_name denormalizado: si después borrás un staff, los leads
--     históricos siguen mostrando quién los cargó (auditoría).
--   - resultado_juego en JSONB: flexible para cualquier estructura sin
--     tener que cambiar schema.
-- =====================================================================
create table if not exists leads (
  id                       text primary key,
  company_id               text not null references companies(id) on delete restrict,
  event_id                 uuid references events(id) on delete set null,

  -- Quién y cuándo (los 3 datos críticos del requerimiento)
  staff_id                 text references staff(id) on delete set null,
  staff_name               text,                 -- denormalizado para auditoría
  captured_at              timestamptz not null, -- timestamp del cliente al guardar
  synced_at                timestamptz default now(), -- timestamp del servidor
  origen_captura           text not null,        -- 'staff_manual' | 'staff_ocr_credencial' | 'staff_ocr_tarjeta' | 'qr_self'
  device_id                text,                 -- identificador del dispositivo (debugging)

  -- Datos del médico
  nombre                   text not null,
  especialidad             text,
  rol                      text default 'Médico',
  institucion              text,
  whatsapp_e164            text,                 -- '+54 9 11 5555 1234'
  email                    citext,
  pais                     text,                 -- 'AR' | 'CL' | 'PE'
  intereses                text[] default array[]::text[],
  notas                    text,

  -- Calificación del staff (Lead Score + temperatura)
  lead_score               smallint check (lead_score is null or lead_score between 0 and 5),
  temperatura              text check (temperatura is null or temperatura in ('frio','tibio','caliente')),

  -- Juego y premio físico
  juego_jugado             text check (juego_jugado is null or juego_jugado in ('ruleta','quiz','memotest')),
  resultado_juego          jsonb,                -- {premio:'Holter', score:2, total:3, tiempo_seg:14}
  premio_ganado            text,                 -- label del premio si ganó algo
  premio_entregado         boolean default false,
  premio_entregado_at      timestamptz,
  premio_entregado_by      text references staff(id) on delete set null,

  -- Email post-feria con catálogo PDF
  email_enviado            boolean default false,
  email_enviado_at         timestamptz,
  email_pdf_attached       text,                 -- título del PDF que se mandó

  -- WhatsApp post-feria (Meta HSM template)
  whatsapp_enviado         boolean default false,
  whatsapp_enviado_at      timestamptz,
  whatsapp_template_id     text,                 -- ID del template de Meta usado

  -- Verificación anti-fraude (futuro: OTP por WhatsApp)
  whatsapp_verificado      boolean default false,
  whatsapp_verificado_at   timestamptz,

  -- Compliance / consentimiento informado
  consentimiento           boolean default true,
  consentimiento_ley       text,                 -- 'Ley 25.326', 'Ley 19.628', 'Ley 29.733'

  -- Sync conflicts (cuando un lead duplicado quedó marcado en el cliente)
  sync_conflict            boolean default false,
  sync_conflict_reason     text,

  -- Metadata
  created_at               timestamptz default now(),
  updated_at               timestamptz default now()
);

-- Índices para queries comunes del dashboard
create index if not exists idx_leads_company_event       on leads(company_id, event_id);
create index if not exists idx_leads_captured_at         on leads(captured_at desc);
create index if not exists idx_leads_staff               on leads(staff_id);
create index if not exists idx_leads_temperatura         on leads(temperatura) where temperatura is not null;
create index if not exists idx_leads_lead_score          on leads(lead_score) where lead_score is not null;
create index if not exists idx_leads_premio_pendiente    on leads(company_id, premio_entregado)
  where premio_ganado is not null and premio_entregado = false;
create index if not exists idx_leads_email_pendiente     on leads(company_id, email_enviado)
  where email is not null and email_enviado = false;
create index if not exists idx_leads_whatsapp            on leads(company_id, whatsapp_e164) where whatsapp_e164 is not null;

-- Constraint anti-duplicado: un mismo WhatsApp no puede registrarse dos veces
-- en la misma empresa+evento (regla de negocio del sorteo)
create unique index if not exists uq_lead_whatsapp_event
  on leads(company_id, event_id, whatsapp_e164)
  where whatsapp_e164 is not null and event_id is not null;

comment on table leads is 'Tabla central de leads capturados. id viene del cliente (idempotencia).';
comment on column leads.captured_at is 'Cuándo el médico se registró (timestamp del cliente, puede ser pasado).';
comment on column leads.synced_at is 'Cuándo llegó al servidor. synced_at - captured_at = latencia de sincronización.';
comment on column leads.resultado_juego is 'JSONB: {premio,score,total,tiempo_seg}. Estructura libre por flexibilidad.';


-- =====================================================================
-- 6. TABLA: prize_inventory (stock por evento × empresa × premio)
-- =====================================================================
-- Track del inventario de premios físicos por evento. Permite que el
-- backend valide la disponibilidad (no solo el cliente offline) y que
-- el dashboard muestre cuánto queda en cada booth.
--
-- Si un premio no aparece acá, se asume stock ilimitado (-1).
-- =====================================================================
create table if not exists prize_inventory (
  id              uuid primary key default gen_random_uuid(),
  company_id      text not null references companies(id) on delete cascade,
  event_id        uuid references events(id) on delete cascade,
  prize_label     text not null,
  prize_short     text,
  weight          smallint default 1,
  initial_stock   integer default -1,           -- -1 = ilimitado
  delivered_count integer default 0,            -- se actualiza con trigger
  created_at      timestamptz default now(),
  updated_at      timestamptz default now(),
  unique (company_id, event_id, prize_label)
);

create index if not exists idx_prize_inv_company_event on prize_inventory(company_id, event_id);

comment on table prize_inventory is 'Stock por evento × empresa × premio. -1 = ilimitado.';


-- =====================================================================
-- 7. TABLA: sync_log (auditoría de sincronizaciones)
-- =====================================================================
-- Cada vez que un cliente sincroniza, queda un registro acá. Útil para:
--   - Debugging cuando el cliente dice "sincronicé" y la BD no lo tiene
--   - Identificar dispositivos problemáticos
--   - Auditar conflictos
--   - Calcular latencia promedio de sync
-- =====================================================================
create table if not exists sync_log (
  id              uuid primary key default gen_random_uuid(),
  device_id       text,
  staff_id        text references staff(id) on delete set null,
  company_id      text references companies(id) on delete set null,
  action          text not null,               -- 'lead_create' | 'lead_update' | 'prize_delivered' | 'email_queued'
  entity_type     text,                        -- 'lead' | 'email_queue' | 'prize_inventory'
  entity_id       text,
  payload         jsonb,
  result          text not null,               -- 'success' | 'conflict' | 'error' | 'duplicate_ignored'
  error_message   text,
  client_timestamp timestamptz,                -- cuándo lo capturó el cliente
  created_at      timestamptz default now()    -- cuándo llegó al server
);

create index if not exists idx_sync_log_created       on sync_log(created_at desc);
create index if not exists idx_sync_log_staff         on sync_log(staff_id, created_at desc);
create index if not exists idx_sync_log_result_error  on sync_log(result) where result != 'success';

comment on table sync_log is 'Log de auditoría de sincronizaciones. Útil para debugging y métricas.';


-- =====================================================================
-- 8. TABLA: email_queue (cola de emails pendientes)
-- =====================================================================
-- Cuando un médico se registra, se encola un email con el catálogo PDF
-- correspondiente al interés que marcó. Un worker (o un trigger de
-- Supabase Functions) procesa la cola y envía via Resend/Brevo/SendGrid.
-- =====================================================================
create table if not exists email_queue (
  id              text primary key,            -- viene del cliente
  lead_id         text references leads(id) on delete cascade,
  company_id      text not null references companies(id),
  to_email        citext not null,
  to_name         text,
  subject         text not null,
  html_body       text not null,
  attachment_url  text,                        -- URL del PDF de catálogo
  attachment_name text,
  status          text not null default 'pending'
                  check (status in ('pending','sending','sent','failed','cancelled')),
  attempts        smallint default 0,
  last_error      text,
  scheduled_at    timestamptz default now(),
  sent_at         timestamptz,
  created_at      timestamptz default now(),
  updated_at      timestamptz default now()
);

create index if not exists idx_email_queue_pending  on email_queue(status, scheduled_at) where status = 'pending';
create index if not exists idx_email_queue_lead     on email_queue(lead_id);

comment on table email_queue is 'Cola de emails post-feria con catálogos PDF. Procesada por worker externo.';


-- =====================================================================
-- 9. TRIGGERS · updated_at automático
-- =====================================================================
-- Mantiene actualizado el campo updated_at en cada modificación.
-- Aplica a todas las tablas con campo updated_at.
-- =====================================================================
create or replace function fn_set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_companies_updated_at on companies;
create trigger trg_companies_updated_at before update on companies
  for each row execute function fn_set_updated_at();

drop trigger if exists trg_events_updated_at on events;
create trigger trg_events_updated_at before update on events
  for each row execute function fn_set_updated_at();

drop trigger if exists trg_staff_updated_at on staff;
create trigger trg_staff_updated_at before update on staff
  for each row execute function fn_set_updated_at();

drop trigger if exists trg_leads_updated_at on leads;
create trigger trg_leads_updated_at before update on leads
  for each row execute function fn_set_updated_at();

drop trigger if exists trg_prize_inventory_updated_at on prize_inventory;
create trigger trg_prize_inventory_updated_at before update on prize_inventory
  for each row execute function fn_set_updated_at();

drop trigger if exists trg_email_queue_updated_at on email_queue;
create trigger trg_email_queue_updated_at before update on email_queue
  for each row execute function fn_set_updated_at();


-- =====================================================================
-- 10. TRIGGER · actualizar prize_inventory.delivered_count
-- =====================================================================
-- Cuando un lead se marca como premio_entregado=true, incrementa el
-- contador del inventario. Si se deshace (premio_entregado=false),
-- decrementa. Mantiene consistencia entre leads y prize_inventory.
-- =====================================================================
create or replace function fn_update_prize_delivered_count()
returns trigger as $$
begin
  -- Caso 1: se marca como entregado (insert con true, o update false→true)
  if (tg_op = 'INSERT' and new.premio_entregado = true and new.premio_ganado is not null) or
     (tg_op = 'UPDATE' and new.premio_entregado = true and (old.premio_entregado is distinct from true) and new.premio_ganado is not null) then
    update prize_inventory
       set delivered_count = delivered_count + 1
     where company_id = new.company_id
       and event_id is not distinct from new.event_id
       and prize_label = new.premio_ganado;
  end if;

  -- Caso 2: se deshace la entrega (true → false)
  if tg_op = 'UPDATE' and old.premio_entregado = true and new.premio_entregado = false and new.premio_ganado is not null then
    update prize_inventory
       set delivered_count = greatest(0, delivered_count - 1)
     where company_id = new.company_id
       and event_id is not distinct from new.event_id
       and prize_label = new.premio_ganado;
  end if;

  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_leads_prize_count on leads;
create trigger trg_leads_prize_count
  after insert or update of premio_entregado on leads
  for each row execute function fn_update_prize_delivered_count();


-- =====================================================================
-- 11. ROW LEVEL SECURITY (multi-tenant aislado)
-- =====================================================================
-- CRÍTICO: cada empresa solo ve los datos de sus propios tenants.
-- Sirex jamás puede leer datos de Eccosur ni viceversa.
--
-- El cliente se autentica con Supabase Auth y el JWT contiene un claim
-- 'company_id' que identifica a qué empresa pertenece el staff logueado.
-- Las políticas filtran por ese claim.
--
-- IMPORTANTE: estas políticas asumen que vas a usar Supabase Auth con
-- custom claims. Si por ahora preferís usar la anon key sin auth, podés
-- comentar las políticas hasta que tengas auth corriendo.
-- =====================================================================
alter table companies          enable row level security;
alter table events             enable row level security;
alter table staff              enable row level security;
alter table leads              enable row level security;
alter table prize_inventory    enable row level security;
alter table sync_log           enable row level security;
alter table email_queue        enable row level security;

-- Función helper: extrae el company_id del JWT
create or replace function fn_jwt_company_id()
returns text as $$
  select coalesce(
    nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', ''),
    nullif(current_setting('request.jwt.claim.company_id', true), '')
  );
$$ language sql stable;

-- Función helper: el usuario actual es service_role? (panel admin global)
create or replace function fn_is_service_role()
returns boolean as $$
  select coalesce(current_setting('request.jwt.claims', true)::jsonb ->> 'role', '') = 'service_role';
$$ language sql stable;

-- =====================================================================
-- POLÍTICAS · companies
-- Cada empresa solo ve su propia row (o todas si es service_role)
-- =====================================================================
drop policy if exists "companies_select_own" on companies;
create policy "companies_select_own" on companies
  for select using (
    fn_is_service_role() or id = fn_jwt_company_id()
  );

-- =====================================================================
-- POLÍTICAS · events
-- =====================================================================
drop policy if exists "events_select_own" on events;
create policy "events_select_own" on events
  for select using (
    fn_is_service_role() or company_id = fn_jwt_company_id()
  );

drop policy if exists "events_insert_own" on events;
create policy "events_insert_own" on events
  for insert with check (
    fn_is_service_role() or company_id = fn_jwt_company_id()
  );

-- =====================================================================
-- POLÍTICAS · staff
-- =====================================================================
drop policy if exists "staff_select_own_company" on staff;
create policy "staff_select_own_company" on staff
  for select using (
    fn_is_service_role() or company_id = fn_jwt_company_id()
  );

-- =====================================================================
-- POLÍTICAS · leads
-- =====================================================================
drop policy if exists "leads_select_own_company" on leads;
create policy "leads_select_own_company" on leads
  for select using (
    fn_is_service_role() or company_id = fn_jwt_company_id()
  );

drop policy if exists "leads_insert_own_company" on leads;
create policy "leads_insert_own_company" on leads
  for insert with check (
    fn_is_service_role() or company_id = fn_jwt_company_id()
  );

drop policy if exists "leads_update_own_company" on leads;
create policy "leads_update_own_company" on leads
  for update using (
    fn_is_service_role() or company_id = fn_jwt_company_id()
  );

-- =====================================================================
-- POLÍTICAS · prize_inventory
-- =====================================================================
drop policy if exists "prize_inventory_all_own_company" on prize_inventory;
create policy "prize_inventory_all_own_company" on prize_inventory
  for all using (
    fn_is_service_role() or company_id = fn_jwt_company_id()
  );

-- =====================================================================
-- POLÍTICAS · sync_log
-- Solo escritura desde el cliente, lectura solo service_role
-- =====================================================================
drop policy if exists "sync_log_insert_own_company" on sync_log;
create policy "sync_log_insert_own_company" on sync_log
  for insert with check (
    fn_is_service_role() or company_id is null or company_id = fn_jwt_company_id()
  );

drop policy if exists "sync_log_select_own_company" on sync_log;
create policy "sync_log_select_own_company" on sync_log
  for select using (
    fn_is_service_role() or company_id = fn_jwt_company_id()
  );

-- =====================================================================
-- POLÍTICAS · email_queue
-- =====================================================================
drop policy if exists "email_queue_all_own_company" on email_queue;
create policy "email_queue_all_own_company" on email_queue
  for all using (
    fn_is_service_role() or company_id = fn_jwt_company_id()
  );


-- =====================================================================
-- 12. PERMISOS DE GRANT
-- =====================================================================
-- Supabase usa los roles 'anon' (sin auth) y 'authenticated' (con JWT).
-- Otorgamos permisos básicos. Las políticas RLS filtran por encima.
--
-- IMPORTANTE: Si estos roles no existen (porque corrés esto en una
-- instalación local de Postgres y no en Supabase), los GRANTS van
-- a fallar pero las tablas y RLS ya quedaron creadas. En Supabase los
-- roles existen por default así que va a funcionar bien.
-- =====================================================================

do $$
begin
  -- 'authenticated' puede hacer todo lo que las RLS le permitan
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant usage on schema public to authenticated;
    grant select, insert, update, delete on all tables in schema public to authenticated;
    grant usage, select on all sequences in schema public to authenticated;
    grant execute on all functions in schema public to authenticated;
  else
    raise notice 'Role "authenticated" no existe — saltando grants. Esto es esperado fuera de Supabase.';
  end if;

  -- 'anon' (sin login) NO puede acceder por default. Si querés permitir
  -- self-service de visitantes sin login, sumá grants acá específicos
  -- (más seguro usar Edge Functions para esos requests).
  if exists (select 1 from pg_roles where rolname = 'anon') then
    grant usage on schema public to anon;
    -- Por seguridad, no se otorga acceso a tablas. Si lo necesitás,
    -- descomentá la siguiente línea y ajustá:
    -- grant select, insert on leads to anon;
  else
    raise notice 'Role "anon" no existe — saltando grants. Esto es esperado fuera de Supabase.';
  end if;
end $$;


-- =====================================================================
-- VERIFICACIÓN
-- =====================================================================
-- Después de correr este script, deberías ver:
--   7 tablas: companies, events, staff, leads, prize_inventory, sync_log, email_queue
--   ~20 índices
--   2 funciones helper (fn_jwt_company_id, fn_is_service_role)
--   2 funciones de trigger (fn_set_updated_at, fn_update_prize_delivered_count)
--   ~13 políticas RLS
--
-- Para verificar, correr:
--   select tablename from pg_tables where schemaname = 'public';
--   select policyname, tablename from pg_policies where schemaname = 'public';
-- =====================================================================
