-- =====================================================================
-- SEED DATA · DATOS INICIALES PARA EMPEZAR A USAR EL SISTEMA
-- =====================================================================
-- Versión: 1.0
-- Fecha:   2026-04-30
--
-- Cómo usar:
--   1. Antes correr 01_schema.sql
--   2. Pegar este archivo en SQL Editor → Run
--   3. Cambiar los PINs default ANTES del primer evento real
--
-- IMPORTANTE: los PINs acá vienen hasheados con bcrypt usando crypt().
-- En producción real, generá los hashes desde la app web de admin
-- usando bcrypt con cost factor >= 10.
-- =====================================================================


-- =====================================================================
-- 1. EMPRESAS (TENANTS)
-- =====================================================================
insert into companies (id, name, color, countries, metadata) values
  ('sirex',    'Sirex Médica', '#1F4E79', array['AR','CL','PE'],
   '{"logo_url":null,"website":"https://sirex.com.ar","industry":"cardiologia"}'::jsonb),
  ('eccosur',  'Eccosur',      '#0F6E56', array['AR','CL','PE'],
   '{"logo_url":null,"website":"https://eccosur.com","industry":"vascular"}'::jsonb),
  ('torregal', 'Torregal',     '#7A2E2E', array['CL'],
   '{"logo_url":null,"website":"https://torregal.cl","industry":"cardiologia"}'::jsonb)
on conflict (id) do update set
  name = excluded.name,
  color = excluded.color,
  countries = excluded.countries,
  metadata = excluded.metadata;


-- =====================================================================
-- 2. EVENTOS (FERIAS / CONGRESOS)
-- =====================================================================
-- Crear el primer evento de cada empresa para tenerlo listo cuando
-- empiezan a llegar leads. Después se crean más desde el dashboard.
-- =====================================================================
insert into events (id, company_id, name, location, country, starts_at, ends_at, metadata) values
  ('a0000001-0000-0000-0000-000000000001'::uuid, 'sirex',
   'Congreso SAC 2026', 'La Rural, Buenos Aires', 'AR',
   '2026-05-15 09:00:00-03', '2026-05-17 18:00:00-03',
   '{"booth_number":"A-42","staff_count_expected":4}'::jsonb),

  ('a0000001-0000-0000-0000-000000000002'::uuid, 'eccosur',
   'Expo Médica Andina 2026', 'Centro Costa Salguero, Buenos Aires', 'AR',
   '2026-06-10 09:00:00-03', '2026-06-12 18:00:00-03',
   '{"booth_number":"B-12","staff_count_expected":2}'::jsonb),

  ('a0000001-0000-0000-0000-000000000003'::uuid, 'torregal',
   'Congreso Cardiología Chile 2026', 'CasaPiedra, Santiago', 'CL',
   '2026-07-22 09:00:00-04', '2026-07-24 18:00:00-04',
   '{"booth_number":"C-5","staff_count_expected":2}'::jsonb)
on conflict (id) do nothing;


-- =====================================================================
-- 3. STAFF (EMPLEADOS DEL BOOTH)
-- =====================================================================
-- Los PINs están hasheados con bcrypt. PIN en texto plano abajo de cada
-- empleado para que sepas cuál es. CAMBIAR ANTES DE PRODUCCIÓN.
-- =====================================================================
insert into staff (id, company_id, name, email, role, pin_hash) values
  -- Staff Sirex
  ('sx_001', 'sirex', 'Carla Méndez',  'carla.mendez@sirex.com.ar',  'Asistente comercial',
   crypt('1234', gen_salt('bf', 10))),    -- PIN: 1234
  ('sx_002', 'sirex', 'Diego Romero',  'diego.romero@sirex.com.ar',  'Comercial senior',
   crypt('2345', gen_salt('bf', 10))),    -- PIN: 2345
  ('sx_003', 'sirex', 'Bibi (admin)',  'bibi@sirex.com.ar',          'Administrador',
   crypt('9999', gen_salt('bf', 10))),    -- PIN: 9999

  -- Staff Eccosur
  ('ec_001', 'eccosur', 'Laura Fernández', 'laura.f@eccosur.com',    'Asistente comercial',
   crypt('3456', gen_salt('bf', 10))),    -- PIN: 3456
  ('ec_002', 'eccosur', 'Martín Sosa',     'martin.s@eccosur.com',   'Comercial senior',
   crypt('4567', gen_salt('bf', 10))),    -- PIN: 4567

  -- Staff Torregal Chile
  ('tg_001', 'torregal', 'José González',  'jose.g@torregal.cl',     'Asistente comercial',
   crypt('5678', gen_salt('bf', 10)))     -- PIN: 5678
on conflict (id) do nothing;


-- =====================================================================
-- 4. INVENTARIO DE PREMIOS (POR EVENTO × EMPRESA)
-- =====================================================================
-- Stock físico inicial de premios para cada evento.
-- -1 = ilimitado (cupones digitales, descuentos, etc.)
-- =====================================================================

-- Sirex en Congreso SAC 2026
insert into prize_inventory (company_id, event_id, prize_label, prize_short, weight, initial_stock) values
  ('sirex', 'a0000001-0000-0000-0000-000000000001'::uuid, 'Holter de cortesía 🎉',     'Holter',   1,  1),
  ('sirex', 'a0000001-0000-0000-0000-000000000001'::uuid, 'Termo de regalo',             'Termo',    1,  5),
  ('sirex', 'a0000001-0000-0000-0000-000000000001'::uuid, '10% off en próxima compra',   '10% off',  1, -1),
  ('sirex', 'a0000001-0000-0000-0000-000000000001'::uuid, 'Mate de regalo',              'Mate',     1,  5),
  ('sirex', 'a0000001-0000-0000-0000-000000000001'::uuid, 'Cena para 2',                 'Cena',     1,  2),
  ('sirex', 'a0000001-0000-0000-0000-000000000001'::uuid, 'Libro de cardiología',        'Libro',    1,  3),
  ('sirex', 'a0000001-0000-0000-0000-000000000001'::uuid, '5% off en próxima compra',    '5% off',   1, -1),
  ('sirex', 'a0000001-0000-0000-0000-000000000001'::uuid, 'Otra suerte la próxima',      'Próxima',  1, -1)
on conflict (company_id, event_id, prize_label) do nothing;

-- Eccosur en Expo Médica Andina 2026
insert into prize_inventory (company_id, event_id, prize_label, prize_short, weight, initial_stock) values
  ('eccosur', 'a0000001-0000-0000-0000-000000000002'::uuid, 'Estudio vascular gratis 🎉',  'Vascular', 1,  2),
  ('eccosur', 'a0000001-0000-0000-0000-000000000002'::uuid, 'Voucher USD 200',              'USD 200',  1,  1),
  ('eccosur', 'a0000001-0000-0000-0000-000000000002'::uuid, 'Termo Eccosur',                'Termo',    1,  5),
  ('eccosur', 'a0000001-0000-0000-0000-000000000002'::uuid, '15% off',                      '15% off',  1, -1),
  ('eccosur', 'a0000001-0000-0000-0000-000000000002'::uuid, 'Mate Eccosur',                 'Mate',     1,  5),
  ('eccosur', 'a0000001-0000-0000-0000-000000000002'::uuid, 'Otra suerte',                  'Próxima',  1, -1)
on conflict (company_id, event_id, prize_label) do nothing;


-- =====================================================================
-- VERIFICACIÓN
-- =====================================================================
-- Para verificar que todo cargó bien:
--   select count(*) as empresas from companies;       -- esperado: 3
--   select count(*) as eventos from events;           -- esperado: 3
--   select count(*) as staff_total from staff;        -- esperado: 6
--   select count(*) as inventario from prize_inventory; -- esperado: 14
--
-- Para verificar el hash de PINs (debería devolver true):
--   select pin_hash = crypt('1234', pin_hash) as pin_ok
--     from staff where id = 'sx_001';
-- =====================================================================
