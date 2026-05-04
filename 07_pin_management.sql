-- =====================================================================
-- FIX 07 · FUNCIÓN PARA CAMBIAR PINs DESDE EL CLIENTE
-- =====================================================================
-- Permite que el panel admin del cliente HTML cambie PINs del staff
-- sin necesidad de ir al SQL Editor de Supabase.
--
-- La función recibe el staff_id, el PIN actual (para verificación)
-- y el nuevo PIN. Solo cambia si el PIN actual es correcto.
--
-- Cómo usar: pegar en SQL Editor de Supabase y Run.
-- =====================================================================

-- Función que cambia el PIN de un staff verificando el PIN actual
-- (SECURITY DEFINER para que ejecute con permisos del owner, no del caller)
create or replace function fn_update_staff_pin(
  p_staff_id text,
  p_current_pin text,
  p_new_pin text
)
returns jsonb as $$
declare
  v_valid boolean;
begin
  -- Validaciones básicas
  if p_new_pin is null or length(p_new_pin) < 4 then
    return jsonb_build_object('ok', false, 'error', 'El PIN nuevo debe tener al menos 4 dígitos');
  end if;

  if p_new_pin !~ '^\d{4,8}$' then
    return jsonb_build_object('ok', false, 'error', 'El PIN debe ser solo números (4-8 dígitos)');
  end if;

  -- Verificar que el staff existe y el PIN actual es correcto
  select (s.pin_hash = crypt(p_current_pin, s.pin_hash))
    into v_valid
    from staff s
   where s.id = p_staff_id
     and s.active = true;

  if v_valid is null then
    return jsonb_build_object('ok', false, 'error', 'Staff no encontrado');
  end if;

  if not v_valid then
    return jsonb_build_object('ok', false, 'error', 'PIN actual incorrecto');
  end if;

  -- Actualizar el PIN
  update staff
     set pin_hash = crypt(p_new_pin, gen_salt('bf', 10))
   where id = p_staff_id;

  return jsonb_build_object('ok', true);
end;
$$ language plpgsql security definer;

-- También una versión "admin" que NO requiere el PIN actual
-- (para cuando el admin olvida el PIN de un empleado)
create or replace function fn_admin_reset_staff_pin(
  p_staff_id text,
  p_new_pin text
)
returns jsonb as $$
begin
  if p_new_pin is null or length(p_new_pin) < 4 then
    return jsonb_build_object('ok', false, 'error', 'El PIN nuevo debe tener al menos 4 dígitos');
  end if;

  if p_new_pin !~ '^\d{4,8}$' then
    return jsonb_build_object('ok', false, 'error', 'El PIN debe ser solo números (4-8 dígitos)');
  end if;

  -- Verificar que el staff existe
  if not exists (select 1 from staff where id = p_staff_id) then
    return jsonb_build_object('ok', false, 'error', 'Staff no encontrado');
  end if;

  update staff
     set pin_hash = crypt(p_new_pin, gen_salt('bf', 10))
   where id = p_staff_id;

  return jsonb_build_object('ok', true);
end;
$$ language plpgsql security definer;

-- Permisos para que el rol anon pueda llamar estas funciones
grant execute on function fn_update_staff_pin(text, text, text) to anon;
grant execute on function fn_admin_reset_staff_pin(text, text) to anon;

-- Permisos para que el admin del cliente pueda crear/editar staff en Supabase
grant insert on staff to anon;
grant update on staff to anon;

-- Política RLS para INSERT de staff desde anon
drop policy if exists "staff_anon_insert" on staff;
create policy "staff_anon_insert" on staff
  for insert to anon
  with check (true);

-- Política RLS para UPDATE de staff desde anon (soft delete, cambio de nombre/rol)
drop policy if exists "staff_anon_update" on staff;
create policy "staff_anon_update" on staff
  for update to anon
  using (true);

-- Verificación
select routine_name from information_schema.routines
where routine_schema = 'public'
  and routine_name in ('fn_update_staff_pin', 'fn_admin_reset_staff_pin');
