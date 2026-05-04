-- =====================================================================
-- VISTAS Y FUNCIONES PARA EL DASHBOARD
-- =====================================================================
-- Versión: 1.0
-- Fecha:   2026-04-30
--
-- Cómo usar:
--   1. Antes correr 01_schema.sql y 02_seed.sql
--   2. Pegar este archivo en SQL Editor → Run
--
-- Estas vistas simplifican las queries del dashboard. En vez de hacer
-- joins complejos cada vez, el dashboard consulta vw_leads_dashboard,
-- vw_event_stats, etc. y obtiene datos pre-agregados.
-- =====================================================================


-- =====================================================================
-- VISTA: vw_leads_dashboard
-- =====================================================================
-- Vista principal para listados del dashboard. Cruza leads con eventos
-- y staff para mostrar el contexto completo de cada lead. Lo que el
-- equipo comercial necesita ver de un vistazo.
-- =====================================================================
create or replace view vw_leads_dashboard as
select
  l.id,
  l.company_id,
  c.name                 as company_name,
  l.event_id,
  e.name                 as event_name,
  e.location             as event_location,
  l.captured_at,
  l.synced_at,
  extract(epoch from (l.synced_at - l.captured_at))::int as sync_latency_seconds,
  l.origen_captura,
  l.staff_id,
  l.staff_name,
  s.email                as staff_email,
  l.nombre,
  l.especialidad,
  l.rol,
  l.institucion,
  l.whatsapp_e164,
  l.email,
  l.pais,
  l.intereses,
  l.notas,
  l.lead_score,
  l.temperatura,
  -- Etiqueta combinada útil para el dashboard
  case
    when l.temperatura = 'caliente' and l.lead_score >= 4 then 'PRIORIDAD ALTA'
    when l.temperatura = 'tibio' and l.lead_score >= 3    then 'Prioridad media'
    when l.temperatura = 'frio'                            then 'Prioridad baja'
    else                                                        'Sin calificar'
  end as prioridad_comercial,
  l.juego_jugado,
  l.resultado_juego,
  l.premio_ganado,
  l.premio_entregado,
  l.premio_entregado_at,
  l.email_enviado,
  l.email_enviado_at,
  l.whatsapp_enviado,
  l.consentimiento,
  l.sync_conflict
from leads l
left join companies c on c.id = l.company_id
left join events    e on e.id = l.event_id
left join staff     s on s.id = l.staff_id;

comment on view vw_leads_dashboard is 'Vista principal del dashboard. Cruza leads con eventos y staff.';


-- =====================================================================
-- VISTA: vw_event_stats
-- =====================================================================
-- Estadísticas agregadas por evento. Ideal para el header del dashboard
-- de cada evento ("Congreso SAC 2026: 247 leads · 18 calientes · ...")
-- =====================================================================
create or replace view vw_event_stats as
select
  e.id                                          as event_id,
  e.company_id,
  e.name                                        as event_name,
  e.location,
  e.starts_at,
  e.ends_at,
  count(l.id)                                   as total_leads,
  count(l.id) filter (where l.temperatura = 'caliente') as leads_calientes,
  count(l.id) filter (where l.temperatura = 'tibio')    as leads_tibios,
  count(l.id) filter (where l.temperatura = 'frio')     as leads_frios,
  count(l.id) filter (where l.lead_score >= 4)          as leads_alto_score,
  count(l.id) filter (where l.juego_jugado is not null) as leads_jugaron,
  count(l.id) filter (where l.premio_ganado is not null) as premios_ganados,
  count(l.id) filter (where l.premio_entregado = true)   as premios_entregados,
  count(l.id) filter (where l.email_enviado = true)      as emails_enviados,
  count(l.id) filter (where l.origen_captura = 'qr_self') as autoservicio,
  count(l.id) filter (where l.origen_captura like 'staff_%') as cargados_por_staff,
  round(avg(l.lead_score) filter (where l.lead_score is not null), 2) as score_promedio,
  min(l.captured_at)                            as primer_lead,
  max(l.captured_at)                            as ultimo_lead
from events e
left join leads l on l.event_id = e.id
group by e.id, e.company_id, e.name, e.location, e.starts_at, e.ends_at;

comment on view vw_event_stats is 'Estadísticas agregadas por evento.';


-- =====================================================================
-- VISTA: vw_staff_performance
-- =====================================================================
-- Performance del staff: cuántos leads cargó cada uno, qué calidad
-- promedio tienen, cuántos terminaron jugando. Útil para el ranking
-- interno del booth y para reconocer al mejor empleado del evento.
-- =====================================================================
create or replace view vw_staff_performance as
select
  s.id                                          as staff_id,
  s.company_id,
  s.name                                        as staff_name,
  s.email                                       as staff_email,
  count(l.id)                                   as leads_cargados,
  count(l.id) filter (where l.temperatura = 'caliente') as leads_calientes,
  count(l.id) filter (where l.lead_score >= 4)          as leads_alto_score,
  count(l.id) filter (where l.juego_jugado is not null) as leads_jugaron,
  round(avg(l.lead_score) filter (where l.lead_score is not null), 2) as score_promedio,
  -- Tasa de conversión: porcentaje de leads que efectivamente jugaron
  round(
    100.0 * count(l.id) filter (where l.juego_jugado is not null) / nullif(count(l.id), 0),
    1
  ) as tasa_juego_pct,
  min(l.captured_at)                            as primer_lead,
  max(l.captured_at)                            as ultimo_lead
from staff s
left join leads l on l.staff_id = s.id
group by s.id, s.company_id, s.name, s.email;

comment on view vw_staff_performance is 'Performance individual del staff: leads, calidad, tasa de juego.';


-- =====================================================================
-- VISTA: vw_prize_status
-- =====================================================================
-- Status del inventario de premios en tiempo real. Color del semáforo:
-- verde (>2 unidades), naranja (1-2), rojo (agotado).
-- =====================================================================
create or replace view vw_prize_status as
select
  pi.id,
  pi.company_id,
  pi.event_id,
  e.name                  as event_name,
  pi.prize_label,
  pi.prize_short,
  pi.weight,
  pi.initial_stock,
  pi.delivered_count,
  case
    when pi.initial_stock = -1 then null
    else pi.initial_stock - pi.delivered_count
  end                     as remaining_stock,
  case
    when pi.initial_stock = -1                                       then 'unlimited'
    when pi.initial_stock - pi.delivered_count <= 0                  then 'depleted'
    when pi.initial_stock - pi.delivered_count <= 2                  then 'low'
    else                                                                   'ok'
  end                     as stock_status,
  pi.updated_at
from prize_inventory pi
left join events e on e.id = pi.event_id;

comment on view vw_prize_status is 'Estado del inventario de premios con semáforo (ok/low/depleted/unlimited).';


-- =====================================================================
-- VISTA: vw_sync_health
-- =====================================================================
-- Health check de la sincronización en tiempo real. Permite identificar
-- problemas: dispositivos con muchos errores, latencia alta, conflictos
-- por duplicados, etc.
-- =====================================================================
create or replace view vw_sync_health as
select
  date_trunc('hour', created_at)                as hour_bucket,
  company_id,
  count(*)                                      as total_events,
  count(*) filter (where result = 'success')    as success,
  count(*) filter (where result = 'conflict')   as conflicts,
  count(*) filter (where result = 'error')      as errors,
  count(distinct device_id)                     as unique_devices,
  count(distinct staff_id)                      as unique_staff,
  round(
    100.0 * count(*) filter (where result = 'success') / nullif(count(*), 0),
    1
  ) as success_rate_pct
from sync_log
where created_at > now() - interval '7 days'
group by date_trunc('hour', created_at), company_id
order by hour_bucket desc, company_id;

comment on view vw_sync_health is 'Métricas de salud de sincronización en las últimas 7 días, por hora.';


-- =====================================================================
-- FUNCIÓN: fn_verify_staff_pin
-- =====================================================================
-- Verifica un PIN contra el hash bcrypt y devuelve los datos del staff
-- si el match es correcto. La usa la app cuando el empleado ingresa el
-- PIN en el modal. NO devuelve el hash, solo los datos seguros.
--
-- Uso desde el cliente (RPC):
--   const { data } = await supabase.rpc('fn_verify_staff_pin', {
--     p_staff_id: 'sx_001',
--     p_pin: '1234'
--   });
-- =====================================================================
create or replace function fn_verify_staff_pin(
  p_staff_id text,
  p_pin      text
)
returns table (
  id          text,
  company_id  text,
  name        text,
  email       text,
  role        text,
  active      boolean
) as $$
begin
  -- Validación de input
  if p_pin is null or length(p_pin) < 4 then
    return;
  end if;

  return query
    select s.id, s.company_id, s.name, s.email::text, s.role, s.active
    from staff s
    where s.id = p_staff_id
      and s.active = true
      and s.pin_hash = crypt(p_pin, s.pin_hash);

  -- Si encontró match, actualizar last_login (efecto secundario informativo)
  -- Calificamos con alias 'st.' para evitar ambigüedad con los OUT params
  -- de la función (que también se llaman id, company_id, etc.)
  update staff st
     set last_login = now()
   where st.id = p_staff_id
     and st.pin_hash = crypt(p_pin, st.pin_hash);
end;
$$ language plpgsql security definer;

comment on function fn_verify_staff_pin is 'Verifica PIN del staff. Devuelve datos sin el hash. SECURITY DEFINER para ejecutar con permisos de la función, no del caller.';


-- =====================================================================
-- FUNCIÓN: fn_check_lead_duplicate
-- =====================================================================
-- Verifica si un WhatsApp ya está registrado en otra empresa para el
-- mismo evento. Útil para que el cliente confirme antes de intentar
-- guardar y reciba un mensaje claro.
--
-- Uso desde el cliente:
--   const { data } = await supabase.rpc('fn_check_lead_duplicate', {
--     p_whatsapp: '+54 9 11 5555 1234',
--     p_event_id: 'a0000001-...',
--     p_current_company: 'sirex'
--   });
-- =====================================================================
create or replace function fn_check_lead_duplicate(
  p_whatsapp        text,
  p_event_id        uuid,
  p_current_company text
)
returns table (
  is_duplicate     boolean,
  existing_company text,
  existing_lead_id text,
  captured_at      timestamptz
) as $$
begin
  return query
    select
      true                       as is_duplicate,
      l.company_id               as existing_company,
      l.id                       as existing_lead_id,
      l.captured_at              as captured_at
    from leads l
    where l.whatsapp_e164 = p_whatsapp
      and l.event_id = p_event_id
      and l.company_id != p_current_company
    limit 1;
end;
$$ language plpgsql stable;

comment on function fn_check_lead_duplicate is 'Verifica si un WhatsApp ya está en otra empresa del mismo evento.';


-- =====================================================================
-- FUNCIÓN: fn_can_pick_prize
-- =====================================================================
-- Verifica si un premio tiene stock disponible antes de asignarlo.
-- Útil cuando el cliente hace girar la ruleta y antes de confirmar
-- el premio quiere validar contra el server (no solo contra IndexedDB).
-- =====================================================================
create or replace function fn_can_pick_prize(
  p_company_id  text,
  p_event_id    uuid,
  p_prize_label text
)
returns boolean as $$
declare
  v_initial integer;
  v_delivered integer;
begin
  select initial_stock, delivered_count
    into v_initial, v_delivered
    from prize_inventory
   where company_id = p_company_id
     and event_id is not distinct from p_event_id
     and prize_label = p_prize_label;

  -- Si no está en inventario, asumimos ilimitado
  if not found then
    return true;
  end if;

  -- -1 = ilimitado
  if v_initial = -1 then
    return true;
  end if;

  return (v_initial - v_delivered) > 0;
end;
$$ language plpgsql stable;

comment on function fn_can_pick_prize is 'Verifica si queda stock de un premio en un evento.';


-- =====================================================================
-- FUNCIÓN: fn_lead_summary_by_period
-- =====================================================================
-- Reporte agregado por período: cuántos leads totales, calientes, etc.
-- en un rango de fechas. Útil para reportes mensuales/trimestrales.
-- =====================================================================
create or replace function fn_lead_summary_by_period(
  p_company_id text,
  p_from       timestamptz,
  p_to         timestamptz
)
returns table (
  total_leads        bigint,
  leads_calientes    bigint,
  leads_tibios       bigint,
  leads_frios        bigint,
  score_promedio     numeric,
  emails_enviados    bigint,
  premios_entregados bigint,
  eventos_distintos  bigint
) as $$
  select
    count(*),
    count(*) filter (where temperatura = 'caliente'),
    count(*) filter (where temperatura = 'tibio'),
    count(*) filter (where temperatura = 'frio'),
    round(avg(lead_score) filter (where lead_score is not null), 2),
    count(*) filter (where email_enviado = true),
    count(*) filter (where premio_entregado = true),
    count(distinct event_id)
  from leads
  where company_id = p_company_id
    and captured_at between p_from and p_to;
$$ language sql stable;


-- =====================================================================
-- VERIFICACIÓN
-- =====================================================================
-- Para verificar que las vistas y funciones quedaron creadas:
--
--   select table_name from information_schema.views where table_schema='public';
--   select routine_name from information_schema.routines where routine_schema='public';
--
-- Para probar la vista principal:
--   select * from vw_leads_dashboard limit 5;
--
-- Para probar el verificador de PIN (debería devolver datos del staff):
--   select * from fn_verify_staff_pin('sx_001', '1234');
--
-- Y NO debería devolver nada si el PIN es incorrecto:
--   select * from fn_verify_staff_pin('sx_001', '0000');
-- =====================================================================
