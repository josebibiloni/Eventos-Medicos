-- =====================================================================
-- FIX 05 · CONSTRAINT ANTI-DUPLICADO MÁS PERMISIVO
-- =====================================================================
-- Problema: el constraint original uq_lead_whatsapp_event bloqueaba
-- TODOS los leads que compartieran (company_id, event_id, whatsapp_e164),
-- incluyendo leads de prueba con whatsapp vacío o de testing.
--
-- Solución: dos cambios.
--   1) El constraint solo aplica si whatsapp_e164 tiene >= 8 dígitos
--      (NULL, vacío y "test"/"asdf" no se bloquean).
--   2) Durante la fase de prueba, podés DESHABILITAR completamente
--      el constraint con la opción al final del script.
--
-- Cómo usar: pegar en SQL Editor de Supabase y Run.
-- =====================================================================


-- 1. ELIMINAR el constraint estricto original
drop index if exists uq_lead_whatsapp_event;
drop index if exists uq_lead_whatsapp_event_strict;


-- =====================================================================
-- OPCIÓN A · CONSTRAINT MODERADO (recomendado para producción)
-- =====================================================================
-- Aplica solo a WhatsApps con formato válido. Permite múltiples leads
-- con WhatsApp NULL, vacío, o de menos de 8 dígitos.
--
-- En producción: si el médico ingresa un WhatsApp real (>= 8 dígitos)
-- y ya estaba registrado en mismo evento+empresa, se rechaza.
--
-- Para activar esta opción, dejá descomentadas estas líneas:
create unique index if not exists uq_lead_whatsapp_event_strict
  on leads(company_id, event_id, whatsapp_e164)
  where whatsapp_e164 is not null
    and length(regexp_replace(whatsapp_e164, '[^0-9]', '', 'g')) >= 8
    and event_id is not null;


-- =====================================================================
-- OPCIÓN B · SIN CONSTRAINT (recomendado para fase de prueba)
-- =====================================================================
-- Si querés probar libremente con cualquier WhatsApp incluso repetido,
-- DESCOMENTÁ las dos líneas siguientes Y comentá la opción A de arriba:
--
-- drop index if exists uq_lead_whatsapp_event_strict;
-- -- (sin constraint = todos los leads se aceptan, sin importar duplicados)
--
-- Cuando termines la fase de prueba y vayas a producción real, volvés
-- a habilitar la opción A (que crea el índice unique).
-- =====================================================================


-- 3. VERIFICACIÓN
select indexname, indexdef
from pg_indexes
where tablename = 'leads'
  and indexname like 'uq_lead%';


-- =====================================================================
-- LIMPIEZA OPCIONAL · borrar leads de prueba
-- =====================================================================
-- Si querés que la BD quede limpia para producción, descomentá y corré:
--
-- delete from leads
-- where origen_captura = 'staff_manual'
--   and (
--     whatsapp_e164 is null
--     or whatsapp_e164 = ''
--     or length(regexp_replace(whatsapp_e164, '[^0-9]', '', 'g')) < 8
--     or nombre ilike 'poiu%' or nombre ilike 'cacho%' or nombre ilike '%test%'
--     or nombre ilike '%prueba%'
--   );
-- =====================================================================


-- =====================================================================
-- NOTA SOBRE PRODUCCIÓN
-- =====================================================================
-- En el evento real, asumimos que cada médico va a poner un WhatsApp
-- válido (>= 8 dígitos) y que dos médicos distintos no van a tener el
-- mismo número. Bajo estos supuestos, el constraint moderado de la
-- opción A protege correctamente contra duplicados maliciosos sin
-- bloquear el flujo de carga normal.
-- =====================================================================

