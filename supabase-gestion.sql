-- =====================================================================
--  SISTEMA DE GESTIÓN (/gestion) · Admin y Operador
--  Pegar TODO esto en Supabase → SQL Editor → Run. Se puede correr más de una vez.
--  Todas las tablas empiezan con g_ y no tocan el chat ni la landing.
-- =====================================================================
create extension if not exists pgcrypto with schema extensions;

-- ---------- 1) Roles ----------
create table if not exists public.g_roles(
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('admin','operador')),
  created_at timestamptz not null default now()
);
alter table public.g_roles enable row level security;

create or replace function public.g_role() returns text
language sql stable security definer set search_path=public as
$$ select role from public.g_roles where user_id=auth.uid() $$;
create or replace function public.g_is_admin() returns boolean
language sql stable security definer set search_path=public as
$$ select coalesce((select role='admin' from public.g_roles where user_id=auth.uid()),false) $$;
create or replace function public.g_is_staff() returns boolean
language sql stable security definer set search_path=public as
$$ select exists(select 1 from public.g_roles where user_id=auth.uid()) $$;

drop policy if exists g_roles_sel on public.g_roles;
create policy g_roles_sel on public.g_roles for select to authenticated
  using (user_id=auth.uid() or public.g_is_admin());

-- ---------- 2) Ajustes (solo el admin los cambia) ----------
create table if not exists public.g_settings(key text primary key, value jsonb not null);
insert into public.g_settings(key,value) values ('op_can_edit','false'),('op_history_days','2') on conflict do nothing;
alter table public.g_settings enable row level security;
drop policy if exists g_settings_sel on public.g_settings;
create policy g_settings_sel on public.g_settings for select to authenticated using (public.g_is_staff());
drop policy if exists g_settings_adm on public.g_settings;
create policy g_settings_adm on public.g_settings for all to authenticated using (public.g_is_admin()) with check (public.g_is_admin());

create or replace function public.g_setting_int(k text, def int) returns int
language sql stable security definer set search_path=public as
$$ select coalesce((select (value#>>'{}')::int from public.g_settings where key=k),def) $$;
create or replace function public.g_setting_bool(k text) returns boolean
language sql stable security definer set search_path=public as
$$ select coalesce((select (value#>>'{}')::boolean from public.g_settings where key=k),false) $$;

-- Ventana de historial: el admin ve todo; el operador solo los últimos N días (1 = solo hoy, hora Argentina)
create or replace function public.g_in_window(t timestamptz) returns boolean
language sql stable security definer set search_path=public as $$
  select public.g_is_admin() or (public.g_is_staff() and t >=
    ((date_trunc('day', now() at time zone 'America/Argentina/Buenos_Aires')
      - make_interval(days => greatest(public.g_setting_int('op_history_days',2),1)-1))
      at time zone 'America/Argentina/Buenos_Aires'))
$$;

-- ---------- 3) Billeteras y fichas (con libro de movimientos) ----------
create table if not exists public.g_wallets(
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner text not null default '',
  color text not null default '#00e676',
  balance numeric(14,2) not null default 0,
  archived boolean not null default false,
  created_at timestamptz not null default now()
);
create unique index if not exists g_wallets_name on public.g_wallets(lower(name));

create table if not exists public.g_chips(
  id uuid primary key default gen_random_uuid(),
  name text not null,
  balance numeric(14,2) not null default 0,
  archived boolean not null default false,
  created_at timestamptz not null default now()
);
create unique index if not exists g_chips_name on public.g_chips(lower(name));

create table if not exists public.g_wallet_tx(
  id uuid primary key default gen_random_uuid(),
  wallet_id uuid not null references public.g_wallets(id),
  ts timestamptz not null default now(),
  kind text not null check (kind in ('inicial','carga','retiro','ajuste+','ajuste-','gasto','sueldo','transf_in','transf_out')),
  amount numeric(14,2) not null,
  descr text not null default '',
  movement_id uuid,
  expense_id uuid,
  cajero text not null default '',
  adm_only boolean not null default false,
  created_by uuid default auth.uid()
);
create index if not exists g_wtx_w on public.g_wallet_tx(wallet_id, ts desc);
create index if not exists g_wtx_ts on public.g_wallet_tx(ts desc);
create index if not exists g_wtx_mov on public.g_wallet_tx(movement_id);
create index if not exists g_wtx_exp on public.g_wallet_tx(expense_id);

create table if not exists public.g_chip_tx(
  id uuid primary key default gen_random_uuid(),
  chip_id uuid not null references public.g_chips(id),
  ts timestamptz not null default now(),
  kind text not null check (kind in ('inicial','carga','retiro','ajuste+','ajuste-','compra')),
  amount numeric(14,2) not null,
  descr text not null default '',
  movement_id uuid,
  cajero text not null default '',
  created_by uuid default auth.uid()
);
create index if not exists g_ctx_c on public.g_chip_tx(chip_id, ts desc);
create index if not exists g_ctx_ts on public.g_chip_tx(ts desc);
create index if not exists g_ctx_mov on public.g_chip_tx(movement_id);

create or replace function public.g_wtx_bal() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if tg_op='INSERT' then update public.g_wallets set balance=balance+new.amount where id=new.wallet_id;
  elsif tg_op='DELETE' then update public.g_wallets set balance=balance-old.amount where id=old.wallet_id;
  else
    update public.g_wallets set balance=balance-old.amount where id=old.wallet_id;
    update public.g_wallets set balance=balance+new.amount where id=new.wallet_id;
  end if;
  return null;
end $$;
drop trigger if exists g_wtx_bal_t on public.g_wallet_tx;
create trigger g_wtx_bal_t after insert or update or delete on public.g_wallet_tx for each row execute function public.g_wtx_bal();

create or replace function public.g_ctx_bal() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if tg_op='INSERT' then update public.g_chips set balance=balance+new.amount where id=new.chip_id;
  elsif tg_op='DELETE' then update public.g_chips set balance=balance-old.amount where id=old.chip_id;
  else
    update public.g_chips set balance=balance-old.amount where id=old.chip_id;
    update public.g_chips set balance=balance+new.amount where id=new.chip_id;
  end if;
  return null;
end $$;
drop trigger if exists g_ctx_bal_t on public.g_chip_tx;
create trigger g_ctx_bal_t after insert or update or delete on public.g_chip_tx for each row execute function public.g_ctx_bal();

-- ---------- 4) Cajeros, claves, turnos y sueldos ----------
create table if not exists public.g_cajeros(
  id uuid primary key default gen_random_uuid(),
  name text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid()
);
create unique index if not exists g_cajeros_name on public.g_cajeros(lower(name));

create table if not exists public.g_cajero_pin(
  cajero_id uuid primary key references public.g_cajeros(id) on delete cascade,
  pin_hash text not null,
  fails int not null default 0,
  locked_until timestamptz
);
alter table public.g_cajero_pin enable row level security;   -- sin políticas: solo las funciones internas la tocan

create table if not exists public.g_shifts(
  id uuid primary key default gen_random_uuid(),
  cajero_id uuid not null references public.g_cajeros(id) on delete cascade,
  cajero_name text not null,
  user_id uuid not null default auth.uid(),
  started_at timestamptz not null default now(),
  ended_at timestamptz
);
create index if not exists g_shifts_c on public.g_shifts(cajero_id, started_at desc);

create table if not exists public.g_salaries(
  cajero_id uuid primary key references public.g_cajeros(id) on delete cascade,
  monthly numeric(14,2) not null default 0
);

-- ---------- 5) Publicidad ----------
create table if not exists public.g_ads(
  id uuid primary key default gen_random_uuid(),
  name text not null,
  invest numeric(14,2) not null default 0,
  start_date date not null default current_date,
  end_date date,
  status text not null default 'activa' check (status in ('activa','pausada','finalizada','archivada')),
  init_msgs int not null default 0,
  init_loads int not null default 0,
  init_income numeric(14,2) not null default 0,
  created_at timestamptz not null default now()
);
create table if not exists public.g_ad_msgs(
  id uuid primary key default gen_random_uuid(),
  ad_id uuid not null references public.g_ads(id) on delete cascade,
  ts timestamptz not null default now(),
  qty int not null check (qty between 1 and 1000),
  cajero text not null default '',
  created_by uuid default auth.uid()
);
create index if not exists g_adm_ad on public.g_ad_msgs(ad_id, ts);
create table if not exists public.g_ad_costs(
  id uuid primary key default gen_random_uuid(),
  ad_id uuid not null references public.g_ads(id) on delete cascade,
  ts timestamptz not null default now(),
  amount numeric(14,2) not null check (amount>0),
  note text not null default ''
);
create table if not exists public.g_ad_adjust(
  id uuid primary key default gen_random_uuid(),
  ad_id uuid not null references public.g_ads(id) on delete cascade,
  ts timestamptz not null default now(),
  field text not null check (field in ('msgs','loads','income')),
  delta numeric(14,2) not null,
  note text not null default ''
);

-- ---------- 6) Movimientos (cargas y retiros) ----------
create table if not exists public.g_movements(
  id uuid primary key default gen_random_uuid(),
  ts timestamptz not null default now(),
  kind text not null check (kind in ('carga','retiro')),
  user_name text not null,
  amount numeric(14,2) not null check (amount>0),
  bonus numeric(14,2) not null default 0,
  bonus_type text not null default '%',
  bonus_value numeric(10,2) not null default 0,
  chips numeric(14,2) not null,
  chip_id uuid references public.g_chips(id),
  wallet_id uuid references public.g_wallets(id),
  ad_id uuid references public.g_ads(id) on delete set null,
  cajero_id uuid,
  cajero_name text not null default '',
  shift_id uuid,
  edited boolean not null default false,
  created_by uuid default auth.uid()
);
create index if not exists g_mov_ts on public.g_movements(ts desc);
create index if not exists g_mov_user on public.g_movements(lower(user_name));
create index if not exists g_mov_ad on public.g_movements(ad_id);

-- ---------- 7) Gastos de oficina ----------
create table if not exists public.g_expense_cats(
  id uuid primary key default gen_random_uuid(),
  name text not null,
  active boolean not null default true,
  is_salary boolean not null default false
);
create unique index if not exists g_ecat_name on public.g_expense_cats(lower(name));
insert into public.g_expense_cats(name,is_salary) values
  ('sueldos',true),('alquiler',false),('expensas (gas, luz, etc)',false),('agua',false),('fichas',false),('recarga de celu',false),('otros',false)
  on conflict do nothing;

create table if not exists public.g_expenses(
  id uuid primary key default gen_random_uuid(),
  ts timestamptz not null default now(),
  cat_id uuid references public.g_expense_cats(id),
  cat_name text not null,
  amount numeric(14,2) not null check (amount>0),
  wallet_id uuid references public.g_wallets(id),
  descr text not null default '',
  responsible text not null default '',
  doc_path text,
  adm_only boolean not null default false,
  cajero text not null default '',
  created_by uuid default auth.uid()
);
create index if not exists g_exp_ts on public.g_expenses(ts desc);

create table if not exists public.g_salary_payments(
  id uuid primary key default gen_random_uuid(),
  cajero_id uuid not null references public.g_cajeros(id) on delete cascade,
  ts timestamptz not null default now(),
  period text not null check (period ~ '^[0-9]{4}-[0-9]{2}$'),
  amount numeric(14,2) not null check (amount>0),
  wallet_id uuid references public.g_wallets(id),
  expense_id uuid,
  note text not null default ''
);
create index if not exists g_salpay_c on public.g_salary_payments(cajero_id, period);

-- ---------- 8) Auditoría ----------
create table if not exists public.g_audit(
  id bigint generated always as identity primary key,
  ts timestamptz not null default now(),
  user_id uuid default auth.uid(),
  actor text not null default '',
  action text not null,
  detail jsonb not null default '{}'::jsonb
);
create index if not exists g_audit_ts on public.g_audit(ts desc);

create or replace function public.g_log(p_action text, p_detail jsonb, p_actor text default null) returns void
language plpgsql security definer set search_path=public as $$
begin
  insert into public.g_audit(actor,action,detail)
  values (coalesce(p_actor, coalesce(public.g_role(),'?')), p_action, coalesce(p_detail,'{}'::jsonb));
end $$;

-- ---------- 9) Seguridad por filas (RLS) ----------
do $$ declare t text; begin
  foreach t in array array['g_wallets','g_chips','g_wallet_tx','g_chip_tx','g_cajeros','g_shifts','g_salaries','g_ads','g_ad_msgs','g_ad_costs','g_ad_adjust','g_movements','g_expense_cats','g_expenses','g_salary_payments','g_audit']
  loop execute format('alter table public.%I enable row level security',t); end loop;
end $$;

-- Billeteras y fichas: todo el personal las ve; solo el admin edita nombre/color/archivo (el saldo nunca se edita a mano)
drop policy if exists g_w_sel on public.g_wallets;  create policy g_w_sel on public.g_wallets for select to authenticated using (public.g_is_staff());
drop policy if exists g_w_upd on public.g_wallets;  create policy g_w_upd on public.g_wallets for update to authenticated using (public.g_is_admin()) with check (public.g_is_admin());
drop policy if exists g_c_sel on public.g_chips;    create policy g_c_sel on public.g_chips for select to authenticated using (public.g_is_staff());
drop policy if exists g_c_upd on public.g_chips;    create policy g_c_upd on public.g_chips for update to authenticated using (public.g_is_admin()) with check (public.g_is_admin());
-- Libros de movimientos: admin todo; operador solo la ventana de días y nunca lo marcado "solo admin" (sueldos)
drop policy if exists g_wtx_sel on public.g_wallet_tx;
create policy g_wtx_sel on public.g_wallet_tx for select to authenticated using (public.g_is_admin() or (public.g_is_staff() and not adm_only and public.g_in_window(ts)));
drop policy if exists g_ctx_sel on public.g_chip_tx;
create policy g_ctx_sel on public.g_chip_tx for select to authenticated using (public.g_in_window(ts));
-- Cajeros: el personal ve la lista; solo el admin cambia estado/nombre o borra. Sueldos: SOLO admin.
drop policy if exists g_cj_sel on public.g_cajeros; create policy g_cj_sel on public.g_cajeros for select to authenticated using (public.g_is_staff());
drop policy if exists g_cj_upd on public.g_cajeros; create policy g_cj_upd on public.g_cajeros for update to authenticated using (public.g_is_admin()) with check (public.g_is_admin());
drop policy if exists g_cj_del on public.g_cajeros; create policy g_cj_del on public.g_cajeros for delete to authenticated using (public.g_is_admin());
drop policy if exists g_sh_sel on public.g_shifts;  create policy g_sh_sel on public.g_shifts for select to authenticated using (public.g_is_admin());
drop policy if exists g_sal_all on public.g_salaries; create policy g_sal_all on public.g_salaries for all to authenticated using (public.g_is_admin()) with check (public.g_is_admin());
drop policy if exists g_sp_sel on public.g_salary_payments; create policy g_sp_sel on public.g_salary_payments for select to authenticated using (public.g_is_admin());
-- Publicidad: solo admin ve cifras (el operador usa las funciones g_ads_active / g_ad_add_msg)
drop policy if exists g_ads_all on public.g_ads; create policy g_ads_all on public.g_ads for all to authenticated using (public.g_is_admin()) with check (public.g_is_admin());
drop policy if exists g_adm_sel on public.g_ad_msgs; create policy g_adm_sel on public.g_ad_msgs for select to authenticated using (public.g_is_admin());
drop policy if exists g_adc_all on public.g_ad_costs; create policy g_adc_all on public.g_ad_costs for all to authenticated using (public.g_is_admin()) with check (public.g_is_admin());
drop policy if exists g_ada_all on public.g_ad_adjust; create policy g_ada_all on public.g_ad_adjust for all to authenticated using (public.g_is_admin()) with check (public.g_is_admin());
-- Movimientos y gastos
drop policy if exists g_mov_sel on public.g_movements; create policy g_mov_sel on public.g_movements for select to authenticated using (public.g_in_window(ts));
drop policy if exists g_ec_sel on public.g_expense_cats; create policy g_ec_sel on public.g_expense_cats for select to authenticated using (public.g_is_admin() or (public.g_is_staff() and not is_salary));
drop policy if exists g_ec_ins on public.g_expense_cats; create policy g_ec_ins on public.g_expense_cats for insert to authenticated with check (public.g_is_admin() and not is_salary);
drop policy if exists g_ec_upd on public.g_expense_cats; create policy g_ec_upd on public.g_expense_cats for update to authenticated using (public.g_is_admin() and not is_salary) with check (public.g_is_admin() and not is_salary);
drop policy if exists g_exp_sel on public.g_expenses;
create policy g_exp_sel on public.g_expenses for select to authenticated using (public.g_is_admin() or (public.g_is_staff() and not adm_only and public.g_in_window(ts)));
drop policy if exists g_aud_sel on public.g_audit; create policy g_aud_sel on public.g_audit for select to authenticated using (public.g_is_admin());

-- ---------- 10) Permisos de tablas ----------
do $$ declare t text; begin
  foreach t in array array['g_roles','g_settings','g_wallets','g_chips','g_wallet_tx','g_chip_tx','g_cajeros','g_cajero_pin','g_shifts','g_salaries','g_ads','g_ad_msgs','g_ad_costs','g_ad_adjust','g_movements','g_expense_cats','g_expenses','g_salary_payments','g_audit']
  loop execute format('revoke all on public.%I from anon, authenticated',t); end loop;
end $$;
grant select on public.g_roles, public.g_settings, public.g_wallets, public.g_chips, public.g_wallet_tx, public.g_chip_tx, public.g_cajeros,
  public.g_shifts, public.g_salaries, public.g_ads, public.g_ad_msgs, public.g_ad_costs, public.g_ad_adjust, public.g_movements,
  public.g_expense_cats, public.g_expenses, public.g_salary_payments, public.g_audit to authenticated;
grant insert, update, delete on public.g_settings to authenticated;
grant update (name, owner, color, archived) on public.g_wallets to authenticated;
grant update (name, archived) on public.g_chips to authenticated;
grant update (active, name), delete on public.g_cajeros to authenticated;
grant insert, update, delete on public.g_salaries to authenticated;
grant insert, update, delete on public.g_ads to authenticated;
grant insert, update, delete on public.g_ad_costs to authenticated;
grant insert, update, delete on public.g_ad_adjust to authenticated;
grant insert, update on public.g_expense_cats to authenticated;
grant usage on schema public to anon, authenticated;

-- ---------- 11) Funciones (todo lo que mueve plata pasa por acá, en una sola operación) ----------
create or replace function public.g_whoami() returns jsonb
language sql stable security definer set search_path=public as $$
  select jsonb_build_object('role', public.g_role(),
    'op_can_edit', public.g_setting_bool('op_can_edit'),
    'op_history_days', public.g_setting_int('op_history_days',2))
$$;

-- Turno: devuelve (cid, cname) del cajero que opera. El admin puede operar sin turno ("Admin").
create or replace function public.g_shift_info(p_shift uuid, out cid uuid, out cname text)
language plpgsql security definer set search_path=public as $$
begin
  if not public.g_is_staff() then raise exception 'Sin permisos'; end if;
  if p_shift is not null then
    select s.cajero_id, s.cajero_name into cid, cname
      from public.g_shifts s join public.g_cajeros c on c.id=s.cajero_id
     where s.id=p_shift and s.user_id=auth.uid() and s.ended_at is null and c.active;
    if cname is null then raise exception 'Tu turno no está activo. Volvé a iniciar turno.'; end if;
  elsif public.g_is_admin() then cid:=null; cname:='Admin';
  else raise exception 'Primero iniciá tu turno.'; end if;
end $$;

create or replace function public.g_cajero_choices() returns table(id uuid, name text)
language sql stable security definer set search_path=public as $$
  select c.id, c.name from public.g_cajeros c where public.g_is_staff() and c.active order by lower(c.name)
$$;

create or replace function public.g_cajeros_list() returns table(id uuid, name text, active boolean, created_at timestamptz, cargas bigint)
language sql stable security definer set search_path=public as $$
  select c.id, c.name, c.active, c.created_at,
         (select count(*) from public.g_movements m where m.cajero_id=c.id and m.kind='carga')
    from public.g_cajeros c where public.g_is_staff() order by lower(c.name)
$$;

create or replace function public.g_register_cajero(p_name text, p_pin text) returns uuid
language plpgsql security definer set search_path=public, extensions as $$
declare v_name text := btrim(coalesce(p_name,'')); v_id uuid;
begin
  if not public.g_is_staff() then raise exception 'Sin permisos'; end if;
  if char_length(v_name)<2 or char_length(v_name)>30 then raise exception 'El nombre o apodo debe tener entre 2 y 30 letras.'; end if;
  if lower(v_name)='admin' then raise exception 'Ese nombre no está disponible.'; end if;
  if char_length(coalesce(p_pin,''))<4 or char_length(p_pin)>40 then raise exception 'La contraseña debe tener al menos 4 caracteres.'; end if;
  if exists(select 1 from public.g_cajeros where lower(name)=lower(v_name)) then raise exception 'Ya existe un cajero con ese nombre o apodo.'; end if;
  insert into public.g_cajeros(name) values (v_name) returning id into v_id;
  insert into public.g_cajero_pin(cajero_id,pin_hash) values (v_id, crypt(p_pin, gen_salt('bf')));
  perform public.g_log('cajero_crear', jsonb_build_object('id',v_id,'name',v_name));
  return v_id;
end $$;

-- Iniciar turno: devuelve {ok, shift_id, name} o {ok:false, error}. 5 errores seguidos bloquean 5 minutos.
create or replace function public.g_start_shift(p_cajero uuid, p_pin text) returns jsonb
language plpgsql security definer set search_path=public, extensions as $$
declare c public.g_cajeros; p public.g_cajero_pin; v_shift uuid;
begin
  if not public.g_is_staff() then raise exception 'Sin permisos'; end if;
  select * into c from public.g_cajeros where id=p_cajero;
  if not found or not c.active then return jsonb_build_object('ok',false,'error','Ese cajero no está disponible.'); end if;
  select * into p from public.g_cajero_pin where cajero_id=p_cajero for update;
  if not found then return jsonb_build_object('ok',false,'error','Ese cajero no tiene contraseña. Pedile al admin que la restablezca.'); end if;
  if p.locked_until is not null and p.locked_until>now() then
    return jsonb_build_object('ok',false,'error','Demasiados intentos. Probá de nuevo en unos minutos.');
  end if;
  if p.pin_hash <> crypt(coalesce(p_pin,''), p.pin_hash) then
    update public.g_cajero_pin set
      fails = case when fails+1>=5 then 0 else fails+1 end,
      locked_until = case when fails+1>=5 then now()+interval '5 minutes' else null end
    where cajero_id=p_cajero;
    return jsonb_build_object('ok',false,'error','Contraseña incorrecta.');
  end if;
  update public.g_cajero_pin set fails=0, locked_until=null where cajero_id=p_cajero;
  insert into public.g_shifts(cajero_id,cajero_name) values (c.id,c.name) returning id into v_shift;
  return jsonb_build_object('ok',true,'shift_id',v_shift,'name',c.name);
end $$;

create or replace function public.g_end_shift(p_shift uuid) returns void
language sql security definer set search_path=public as $$
  update public.g_shifts set ended_at=now() where id=p_shift and user_id=auth.uid() and ended_at is null
$$;

create or replace function public.g_reset_pin(p_cajero uuid, p_pin text) returns void
language plpgsql security definer set search_path=public, extensions as $$
begin
  if not public.g_is_admin() then raise exception 'Solo el admin puede cambiar contraseñas.'; end if;
  if char_length(coalesce(p_pin,''))<4 or char_length(p_pin)>40 then raise exception 'La contraseña debe tener al menos 4 caracteres.'; end if;
  insert into public.g_cajero_pin(cajero_id,pin_hash) values (p_cajero, crypt(p_pin, gen_salt('bf')))
  on conflict (cajero_id) do update set pin_hash=excluded.pin_hash, fails=0, locked_until=null;
  perform public.g_log('cajero_clave', jsonb_build_object('id',p_cajero));
end $$;

-- Núcleo: registra o recalcula un movimiento (carga/retiro) con su efecto en billetera y fichas.
create or replace function public.g_post_movement(
  p_id uuid, p_insert boolean, p_ts timestamptz, p_kind text, p_user text, p_amount numeric,
  p_bonus_type text, p_bonus_value numeric, p_chip uuid, p_wallet uuid, p_ad uuid,
  p_cid uuid, p_cname text, p_shift uuid) returns void
language plpgsql security definer set search_path=public as $$
declare v_user text := btrim(coalesce(p_user,'')); v_bonus numeric(14,2) := 0; v_chips numeric(14,2);
        w public.g_wallets; ch public.g_chips; ad public.g_ads; v_ad uuid := p_ad; v_bt text := coalesce(p_bonus_type,'%'); v_bv numeric := coalesce(p_bonus_value,0);
begin
  if p_kind not in ('carga','retiro') then raise exception 'Tipo de movimiento inválido.'; end if;
  if char_length(v_user)<1 or char_length(v_user)>40 then raise exception 'Escribí el usuario del jugador (hasta 40 caracteres).'; end if;
  if p_amount is null or p_amount<=0 or p_amount>100000000 then raise exception 'El monto tiene que ser mayor a 0.'; end if;
  select * into w from public.g_wallets where id=p_wallet for update;
  if not found or w.archived then raise exception 'Elegí una billetera válida.'; end if;
  select * into ch from public.g_chips where id=p_chip for update;
  if not found or ch.archived then raise exception 'Elegí una ficha válida.'; end if;
  if p_kind='carga' then
    if v_bv<0 then raise exception 'El bono no puede ser negativo.'; end if;
    if v_bv>0 then
      if v_bt='%' then
        if v_bv>1000 then raise exception 'El bono en porcentaje es demasiado grande.'; end if;
        v_bonus := round(p_amount*v_bv/100,2);
      elsif v_bt='$' then v_bonus := round(v_bv,2);
      else raise exception 'Tipo de bono inválido.'; end if;
    end if;
    v_chips := p_amount + v_bonus;
    if ch.balance < v_chips then raise exception 'No alcanza el stock de fichas (hay %).', ch.balance; end if;
    if v_ad is not null then
      select * into ad from public.g_ads where id=v_ad;
      if not found then raise exception 'Esa publicidad no existe.'; end if;
      if p_insert and ad.status<>'activa' then raise exception 'Esa publicidad no está activa.'; end if;
    end if;
  else
    v_bv := 0; v_bt := '%'; v_ad := null;
    v_chips := p_amount;
    if w.balance < p_amount then raise exception 'La billetera no tiene saldo suficiente (hay %).', w.balance; end if;
  end if;

  if p_insert then
    insert into public.g_movements(id,ts,kind,user_name,amount,bonus,bonus_type,bonus_value,chips,chip_id,wallet_id,ad_id,cajero_id,cajero_name,shift_id)
    values (p_id,p_ts,p_kind,v_user,round(p_amount,2),v_bonus,v_bt,round(v_bv,2),v_chips,p_chip,p_wallet,v_ad,p_cid,p_cname,p_shift);
  else
    update public.g_movements set user_name=v_user, amount=round(p_amount,2), bonus=v_bonus, bonus_type=v_bt, bonus_value=round(v_bv,2),
      chips=v_chips, chip_id=p_chip, wallet_id=p_wallet, ad_id=v_ad, edited=true where id=p_id;
  end if;
  insert into public.g_wallet_tx(wallet_id,ts,kind,amount,descr,movement_id,cajero)
  values (p_wallet,p_ts,p_kind,case when p_kind='carga' then round(p_amount,2) else -round(p_amount,2) end, initcap(p_kind)||' - Usuario: '||v_user, p_id, p_cname);
  insert into public.g_chip_tx(chip_id,ts,kind,amount,descr,movement_id,cajero)
  values (p_chip,p_ts,p_kind,case when p_kind='carga' then -v_chips else v_chips end, initcap(p_kind)||' - Usuario: '||v_user, p_id, p_cname);
end $$;

create or replace function public.g_add_movement(
  p_shift uuid, p_user text, p_kind text, p_amount numeric, p_bonus_type text, p_bonus_value numeric,
  p_chip uuid, p_wallet uuid, p_ad uuid default null) returns uuid
language plpgsql security definer set search_path=public as $$
declare si record; v_id uuid := gen_random_uuid();
begin
  select * into si from public.g_shift_info(p_shift);
  perform public.g_post_movement(v_id,true,now(),p_kind,p_user,p_amount,p_bonus_type,p_bonus_value,p_chip,p_wallet,p_ad,si.cid,si.cname,p_shift);
  return v_id;
end $$;

create or replace function public.g_can_edit(p_ts timestamptz) returns boolean
language sql stable security definer set search_path=public as $$
  select public.g_is_admin() or (public.g_is_staff() and public.g_setting_bool('op_can_edit') and public.g_in_window(p_ts))
$$;

create or replace function public.g_edit_movement(
  p_shift uuid, p_id uuid, p_user text, p_amount numeric, p_bonus_type text, p_bonus_value numeric,
  p_chip uuid, p_wallet uuid, p_ad uuid default null) returns void
language plpgsql security definer set search_path=public as $$
declare si record; m public.g_movements;
begin
  select * into si from public.g_shift_info(p_shift);
  select * into m from public.g_movements where id=p_id for update;
  if not found then raise exception 'Ese movimiento no existe.'; end if;
  if not public.g_can_edit(m.ts) then raise exception 'No tenés permiso para editar este movimiento.'; end if;
  delete from public.g_wallet_tx where movement_id=p_id;
  delete from public.g_chip_tx where movement_id=p_id;
  perform public.g_post_movement(p_id,false,m.ts,m.kind,p_user,p_amount,p_bonus_type,p_bonus_value,p_chip,p_wallet,p_ad,m.cajero_id,m.cajero_name,m.shift_id);
  perform public.g_log('mov_editar', jsonb_build_object('id',p_id,'antes',to_jsonb(m),'por',si.cname), si.cname);
end $$;

create or replace function public.g_delete_movement(p_shift uuid, p_id uuid) returns void
language plpgsql security definer set search_path=public as $$
declare si record; m public.g_movements;
begin
  select * into si from public.g_shift_info(p_shift);
  select * into m from public.g_movements where id=p_id for update;
  if not found then raise exception 'Ese movimiento no existe.'; end if;
  if not public.g_can_edit(m.ts) then raise exception 'No tenés permiso para anular este movimiento.'; end if;
  delete from public.g_wallet_tx where movement_id=p_id;
  delete from public.g_chip_tx where movement_id=p_id;
  delete from public.g_movements where id=p_id;
  perform public.g_log('mov_anular', jsonb_build_object('id',p_id,'mov',to_jsonb(m),'por',si.cname), si.cname);
end $$;

-- Billeteras y fichas: alta, ajustes y transferencias (solo admin)
create or replace function public.g_create_wallet(p_name text, p_owner text, p_color text, p_initial numeric) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid := gen_random_uuid(); v_name text := btrim(coalesce(p_name,''));
begin
  if not public.g_is_admin() then raise exception 'Solo el admin puede crear billeteras.'; end if;
  if char_length(v_name)<1 or char_length(v_name)>40 then raise exception 'Escribí el nombre de la billetera.'; end if;
  if exists(select 1 from public.g_wallets where lower(name)=lower(v_name)) then raise exception 'Ya existe una billetera con ese nombre.'; end if;
  insert into public.g_wallets(id,name,owner,color) values (v_id,v_name,left(btrim(coalesce(p_owner,'')),40),
    case when p_color ~ '^#[0-9a-fA-F]{6}$' then p_color else '#00e676' end);
  if coalesce(p_initial,0)<>0 then
    insert into public.g_wallet_tx(wallet_id,kind,amount,descr,cajero) values (v_id,'inicial',round(p_initial,2),'Saldo inicial','Admin');
  end if;
  perform public.g_log('billetera_crear', jsonb_build_object('id',v_id,'name',v_name,'inicial',p_initial));
  return v_id;
end $$;

create or replace function public.g_create_chip(p_name text, p_initial numeric) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid := gen_random_uuid(); v_name text := btrim(coalesce(p_name,''));
begin
  if not public.g_is_admin() then raise exception 'Solo el admin puede crear fichas.'; end if;
  if char_length(v_name)<1 or char_length(v_name)>40 then raise exception 'Escribí el nombre de la ficha.'; end if;
  if exists(select 1 from public.g_chips where lower(name)=lower(v_name)) then raise exception 'Ya existe una ficha con ese nombre.'; end if;
  insert into public.g_chips(id,name) values (v_id,v_name);
  if coalesce(p_initial,0)<>0 then
    insert into public.g_chip_tx(chip_id,kind,amount,descr,cajero) values (v_id,'inicial',round(p_initial,2),'Stock inicial','Admin');
  end if;
  perform public.g_log('ficha_crear', jsonb_build_object('id',v_id,'name',v_name,'inicial',p_initial));
  return v_id;
end $$;

create or replace function public.g_wallet_adjust(p_wallet uuid, p_kind text, p_amount numeric, p_descr text) returns void
language plpgsql security definer set search_path=public as $$
declare w public.g_wallets;
begin
  if not public.g_is_admin() then raise exception 'Solo el admin puede hacer ajustes manuales.'; end if;
  if p_kind not in ('ajuste+','ajuste-') then raise exception 'Tipo inválido.'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'El monto tiene que ser mayor a 0.'; end if;
  select * into w from public.g_wallets where id=p_wallet for update;
  if not found then raise exception 'Billetera inexistente.'; end if;
  if p_kind='ajuste-' and w.balance<p_amount then raise exception 'La billetera no tiene saldo suficiente (hay %).', w.balance; end if;
  insert into public.g_wallet_tx(wallet_id,kind,amount,descr,cajero)
  values (p_wallet,p_kind,case when p_kind='ajuste+' then round(p_amount,2) else -round(p_amount,2) end, left(coalesce(nullif(btrim(p_descr),''),'Ajuste manual'),200),'Admin');
  perform public.g_log('billetera_ajuste', jsonb_build_object('wallet',p_wallet,'kind',p_kind,'amount',p_amount,'descr',p_descr));
end $$;

create or replace function public.g_wallet_transfer(p_from uuid, p_to uuid, p_amount numeric, p_descr text) returns void
language plpgsql security definer set search_path=public as $$
declare a public.g_wallets; b public.g_wallets; v_d text;
begin
  if not public.g_is_admin() then raise exception 'Solo el admin puede transferir entre billeteras.'; end if;
  if p_from=p_to then raise exception 'Elegí dos billeteras distintas.'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'El monto tiene que ser mayor a 0.'; end if;
  select * into a from public.g_wallets where id=least(p_from,p_to) for update;
  select * into b from public.g_wallets where id=greatest(p_from,p_to) for update;
  select * into a from public.g_wallets where id=p_from;
  select * into b from public.g_wallets where id=p_to;
  if a.id is null or b.id is null then raise exception 'Billetera inexistente.'; end if;
  if a.balance<p_amount then raise exception 'La billetera de origen no tiene saldo suficiente (hay %).', a.balance; end if;
  v_d := left(coalesce(nullif(btrim(p_descr),''),'Transferencia'),150);
  insert into public.g_wallet_tx(wallet_id,kind,amount,descr,cajero) values (p_from,'transf_out',-round(p_amount,2),v_d||' → '||b.name,'Admin');
  insert into public.g_wallet_tx(wallet_id,kind,amount,descr,cajero) values (p_to,'transf_in',round(p_amount,2),v_d||' ← '||a.name,'Admin');
  perform public.g_log('billetera_transf', jsonb_build_object('from',p_from,'to',p_to,'amount',p_amount));
end $$;

create or replace function public.g_chip_adjust(p_chip uuid, p_kind text, p_amount numeric, p_descr text) returns void
language plpgsql security definer set search_path=public as $$
declare c public.g_chips;
begin
  if not public.g_is_admin() then raise exception 'Solo el admin puede hacer ajustes manuales.'; end if;
  if p_kind not in ('ajuste+','ajuste-','compra') then raise exception 'Tipo inválido.'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'La cantidad tiene que ser mayor a 0.'; end if;
  select * into c from public.g_chips where id=p_chip for update;
  if not found then raise exception 'Ficha inexistente.'; end if;
  if p_kind='ajuste-' and c.balance<p_amount then raise exception 'No alcanza el stock (hay %).', c.balance; end if;
  insert into public.g_chip_tx(chip_id,kind,amount,descr,cajero)
  values (p_chip,p_kind,case when p_kind='ajuste-' then -round(p_amount,2) else round(p_amount,2) end, left(coalesce(nullif(btrim(p_descr),''),initcap(p_kind)),200),'Admin');
  perform public.g_log('ficha_ajuste', jsonb_build_object('chip',p_chip,'kind',p_kind,'amount',p_amount,'descr',p_descr));
end $$;

-- Gastos
create or replace function public.g_add_expense(
  p_shift uuid, p_cat uuid, p_amount numeric, p_wallet uuid, p_descr text, p_responsible text, p_doc text default null) returns uuid
language plpgsql security definer set search_path=public as $$
declare si record; c public.g_expense_cats; w public.g_wallets; v_id uuid := gen_random_uuid();
begin
  select * into si from public.g_shift_info(p_shift);
  select * into c from public.g_expense_cats where id=p_cat and active;
  if not found then raise exception 'Elegí una categoría válida.'; end if;
  if c.is_salary then raise exception 'Los sueldos se pagan desde la pestaña Cajeros.'; end if;
  if p_amount is null or p_amount<=0 or p_amount>100000000 then raise exception 'El monto tiene que ser mayor a 0.'; end if;
  select * into w from public.g_wallets where id=p_wallet for update;
  if not found or w.archived then raise exception 'Elegí una billetera válida.'; end if;
  if w.balance<p_amount then raise exception 'La billetera no tiene saldo suficiente (hay %).', w.balance; end if;
  insert into public.g_expenses(id,cat_id,cat_name,amount,wallet_id,descr,responsible,doc_path,cajero)
  values (v_id,c.id,c.name,round(p_amount,2),p_wallet,left(coalesce(p_descr,''),300),left(coalesce(p_responsible,''),60),nullif(p_doc,''),si.cname);
  insert into public.g_wallet_tx(wallet_id,kind,amount,descr,expense_id,cajero)
  values (p_wallet,'gasto',-round(p_amount,2),'Gasto de oficina ('||c.name||'): '||left(coalesce(p_descr,''),120),v_id,si.cname);
  return v_id;
end $$;

create or replace function public.g_update_expense(
  p_shift uuid, p_id uuid, p_cat uuid, p_amount numeric, p_wallet uuid, p_descr text, p_responsible text) returns void
language plpgsql security definer set search_path=public as $$
declare si record; e public.g_expenses; c public.g_expense_cats; w public.g_wallets;
begin
  select * into si from public.g_shift_info(p_shift);
  select * into e from public.g_expenses where id=p_id for update;
  if not found then raise exception 'Ese gasto no existe.'; end if;
  if e.adm_only and not public.g_is_admin() then raise exception 'Sin permisos.'; end if;
  if not public.g_can_edit(e.ts) then raise exception 'No tenés permiso para editar este gasto.'; end if;
  if e.adm_only then raise exception 'Los pagos de sueldos se anulan desde la pestaña Cajeros.'; end if;
  select * into c from public.g_expense_cats where id=p_cat;
  if not found or c.is_salary then raise exception 'Elegí una categoría válida.'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'El monto tiene que ser mayor a 0.'; end if;
  delete from public.g_wallet_tx where expense_id=p_id;
  select * into w from public.g_wallets where id=p_wallet for update;
  if not found or w.archived then raise exception 'Elegí una billetera válida.'; end if;
  if w.balance<p_amount then raise exception 'La billetera no tiene saldo suficiente (hay %).', w.balance; end if;
  update public.g_expenses set cat_id=c.id, cat_name=c.name, amount=round(p_amount,2), wallet_id=p_wallet,
    descr=left(coalesce(p_descr,''),300), responsible=left(coalesce(p_responsible,''),60) where id=p_id;
  insert into public.g_wallet_tx(wallet_id,ts,kind,amount,descr,expense_id,cajero)
  values (p_wallet,e.ts,'gasto',-round(p_amount,2),'Gasto de oficina ('||c.name||'): '||left(coalesce(p_descr,''),120),p_id,e.cajero);
  perform public.g_log('gasto_editar', jsonb_build_object('id',p_id,'antes',to_jsonb(e),'por',si.cname), si.cname);
end $$;

create or replace function public.g_delete_expense(p_shift uuid, p_id uuid) returns void
language plpgsql security definer set search_path=public as $$
declare si record; e public.g_expenses;
begin
  select * into si from public.g_shift_info(p_shift);
  select * into e from public.g_expenses where id=p_id for update;
  if not found then raise exception 'Ese gasto no existe.'; end if;
  if e.adm_only and not public.g_is_admin() then raise exception 'Sin permisos.'; end if;
  if not public.g_can_edit(e.ts) then raise exception 'No tenés permiso para borrar este gasto.'; end if;
  delete from public.g_salary_payments where expense_id=p_id;
  delete from public.g_wallet_tx where expense_id=p_id;
  delete from public.g_expenses where id=p_id;
  perform public.g_log('gasto_borrar', jsonb_build_object('id',p_id,'gasto',to_jsonb(e),'por',si.cname), si.cname);
end $$;

-- Sueldos (solo admin): genera un gasto "sueldos" y descuenta de la billetera, oculto para el operador
create or replace function public.g_pay_salary(p_cajero uuid, p_amount numeric, p_wallet uuid, p_period text, p_note text) returns uuid
language plpgsql security definer set search_path=public as $$
declare cj public.g_cajeros; w public.g_wallets; c public.g_expense_cats; v_exp uuid := gen_random_uuid(); v_pay uuid := gen_random_uuid();
begin
  if not public.g_is_admin() then raise exception 'Solo el admin puede pagar sueldos.'; end if;
  select * into cj from public.g_cajeros where id=p_cajero;
  if not found then raise exception 'Cajero inexistente.'; end if;
  if p_period !~ '^[0-9]{4}-[0-9]{2}$' then raise exception 'Período inválido.'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'El monto tiene que ser mayor a 0.'; end if;
  select * into w from public.g_wallets where id=p_wallet for update;
  if not found or w.archived then raise exception 'Elegí una billetera válida.'; end if;
  if w.balance<p_amount then raise exception 'La billetera no tiene saldo suficiente (hay %).', w.balance; end if;
  select * into c from public.g_expense_cats where is_salary limit 1;
  if not found then insert into public.g_expense_cats(name,is_salary) values ('sueldos',true) returning * into c; end if;
  insert into public.g_expenses(id,cat_id,cat_name,amount,wallet_id,descr,responsible,adm_only,cajero)
  values (v_exp,c.id,c.name,round(p_amount,2),p_wallet,lower(cj.name)||coalesce(' · '||nullif(btrim(p_note),''),''),'',true,'Admin');
  insert into public.g_wallet_tx(wallet_id,kind,amount,descr,expense_id,cajero,adm_only)
  values (p_wallet,'sueldo',-round(p_amount,2),'Gasto de oficina (sueldos): '||lower(cj.name),v_exp,'Admin',true);
  insert into public.g_salary_payments(id,cajero_id,period,amount,wallet_id,expense_id,note)
  values (v_pay,p_cajero,p_period,round(p_amount,2),p_wallet,v_exp,left(coalesce(p_note,''),150));
  perform public.g_log('sueldo_pago', jsonb_build_object('cajero',cj.name,'amount',p_amount,'period',p_period));
  return v_pay;
end $$;

-- Publicidad
create or replace function public.g_ads_active() returns table(id uuid, name text, msgs bigint)
language sql stable security definer set search_path=public as $$
  select a.id, a.name,
    a.init_msgs + coalesce((select sum(m.qty) from public.g_ad_msgs m where m.ad_id=a.id),0)
               + coalesce((select sum(j.delta) from public.g_ad_adjust j where j.ad_id=a.id and j.field='msgs'),0)
    from public.g_ads a where public.g_is_staff() and a.status='activa' order by a.created_at desc
$$;

create or replace function public.g_ad_add_msg(p_shift uuid, p_ad uuid, p_qty int default 1) returns void
language plpgsql security definer set search_path=public as $$
declare si record; a public.g_ads;
begin
  select * into si from public.g_shift_info(p_shift);
  select * into a from public.g_ads where id=p_ad;
  if not found or a.status<>'activa' then raise exception 'Esa campaña no está activa.'; end if;
  if p_qty is null or p_qty<1 or p_qty>1000 then raise exception 'Cantidad inválida.'; end if;
  insert into public.g_ad_msgs(ad_id,qty,cajero) values (p_ad,p_qty,si.cname);
end $$;

-- Estadísticas de campañas (solo admin). p_total=true: histórico completo; false: solo el período.
create or replace function public.g_ads_stats(p_from timestamptz, p_to timestamptz, p_total boolean, p_status text default null) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare r jsonb;
begin
  if not public.g_is_admin() then raise exception 'Solo el admin.'; end if;
  select coalesce(jsonb_agg(row_to_json(x) order by x.created_at desc),'[]'::jsonb) into r from (
    select a.id, a.name, a.status, a.start_date, a.end_date, a.created_at, a.invest, a.init_msgs, a.init_loads, a.init_income,
      (a.invest + coalesce((select sum(c.amount) from public.g_ad_costs c where c.ad_id=a.id),0)) as inversion,
      (case when p_total then a.init_msgs else 0 end
        + coalesce((select sum(m.qty) from public.g_ad_msgs m where m.ad_id=a.id and (p_total or (m.ts>=p_from and m.ts<p_to))),0)
        + coalesce((select sum(j.delta) from public.g_ad_adjust j where j.ad_id=a.id and j.field='msgs' and (p_total or (j.ts>=p_from and j.ts<p_to))),0)) as msgs,
      (case when p_total then a.init_loads else 0 end
        + coalesce((select count(*) from public.g_movements v where v.ad_id=a.id and v.kind='carga' and (p_total or (v.ts>=p_from and v.ts<p_to))),0)
        + coalesce((select sum(j.delta) from public.g_ad_adjust j where j.ad_id=a.id and j.field='loads' and (p_total or (j.ts>=p_from and j.ts<p_to))),0)) as loads,
      (case when p_total then a.init_income else 0 end
        + coalesce((select sum(v.amount) from public.g_movements v where v.ad_id=a.id and v.kind='carga' and (p_total or (v.ts>=p_from and v.ts<p_to))),0)
        + coalesce((select sum(j.delta) from public.g_ad_adjust j where j.ad_id=a.id and j.field='income' and (p_total or (j.ts>=p_from and j.ts<p_to))),0)) as income
    from public.g_ads a
    where (p_status is null and a.status<>'archivada') or (p_status is not null and a.status=p_status)
  ) x;
  return r;
end $$;

-- Métricas (solo admin)
create or replace function public.g_metrics(p_from timestamptz, p_to timestamptz) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare r jsonb; v_in numeric; v_out numeric; v_exp numeric; v_inv numeric; v_bonus numeric; v_with int; v_wo int; v_ent numeric; v_sal numeric;
begin
  if not public.g_is_admin() then raise exception 'Solo el admin.'; end if;
  select coalesce(sum(amount) filter (where kind='carga'),0), coalesce(sum(amount) filter (where kind='retiro'),0),
         coalesce(sum(bonus) filter (where kind='carga'),0),
         count(*) filter (where kind='carga' and bonus>0), count(*) filter (where kind='carga' and bonus=0)
    into v_in, v_out, v_bonus, v_with, v_wo from public.g_movements where ts>=p_from and ts<p_to;
  select coalesce(sum(amount),0) into v_exp from public.g_expenses where ts>=p_from and ts<p_to;
  select coalesce((select sum(invest) from public.g_ads where start_date >= (p_from at time zone 'America/Argentina/Buenos_Aires')::date
                                                     and start_date <= ((p_to - interval '1 second') at time zone 'America/Argentina/Buenos_Aires')::date),0)
       + coalesce((select sum(amount) from public.g_ad_costs where ts>=p_from and ts<p_to),0) into v_inv;
  select coalesce(sum(amount) filter (where amount>0),0), coalesce(-sum(amount) filter (where amount<0),0)
    into v_ent, v_sal from public.g_wallet_tx where ts>=p_from and ts<p_to and kind not in ('inicial','transf_in','transf_out');
  r := jsonb_build_object(
    'ingresos',v_in,'retiros',v_out,'gastos',v_exp,'inversion',v_inv,'bonos',v_bonus,'con_bono',v_with,'sin_bono',v_wo,
    'entradas',v_ent,'salidas',v_sal,
    'gastos_cat',(select coalesce(jsonb_agg(jsonb_build_object('cat',cat_name,'total',t) order by t desc),'[]'::jsonb)
                    from (select cat_name, sum(amount) t from public.g_expenses where ts>=p_from and ts<p_to group by cat_name) q),
    'cajeros',(select coalesce(jsonb_agg(jsonb_build_object('name',cajero_name,'cargas',cargas,'retiros',retiros,'ops',ops,'cargas_n',cargas_n) order by cargas desc),'[]'::jsonb)
                 from (select cajero_name,
                              coalesce(sum(amount) filter (where kind='carga'),0) cargas, coalesce(sum(amount) filter (where kind='retiro'),0) retiros,
                              count(*) ops, count(*) filter (where kind='carga') cargas_n
                         from public.g_movements where ts>=p_from and ts<p_to group by cajero_name) q),
    'billeteras',(select coalesce(jsonb_agg(jsonb_build_object('name',w.name,'color',w.color,'saldo',w.balance,
                     'entradas',coalesce(x.e,0),'salidas',coalesce(x.s,0)) order by w.name),'[]'::jsonb)
                    from public.g_wallets w
                    left join (select wallet_id, sum(amount) filter (where amount>0) e, -sum(amount) filter (where amount<0) s
                                 from public.g_wallet_tx where ts>=p_from and ts<p_to and kind not in ('inicial','transf_in','transf_out') group by wallet_id) x on x.wallet_id=w.id
                   where not w.archived or x.wallet_id is not null));
  return r;
end $$;

-- ---------- 12) Quién puede llamar a las funciones ----------
do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace
            where n.nspname='public' and p.proname like 'g\_%' escape '\' loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;

-- ---------- 13) Comprobantes de gastos (archivos privados; solo el admin los abre) ----------
do $$ begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets(id,name,public) values ('g-docs','g-docs',false) on conflict (id) do nothing;
    drop policy if exists g_docs_ins on storage.objects;
    create policy g_docs_ins on storage.objects for insert to authenticated with check (bucket_id='g-docs' and public.g_is_staff());
    drop policy if exists g_docs_sel on storage.objects;
    create policy g_docs_sel on storage.objects for select to authenticated using (bucket_id='g-docs' and public.g_is_admin());
    drop policy if exists g_docs_del on storage.objects;
    create policy g_docs_del on storage.objects for delete to authenticated using (bucket_id='g-docs' and public.g_is_admin());
  end if;
end $$;

-- =====================================================================
--  PASO FINAL (corré esto UNA vez, cambiando los mails por los reales):
--  1) En Supabase → Authentication → Users → Add user: creá el usuario ADMIN y el usuario OPERADOR (con contraseña, "Auto Confirm User" tildado).
--  2) Después corré estas dos líneas con sus mails:
--
--  insert into public.g_roles(user_id,role) select id,'admin'    from auth.users where email='MAIL_DEL_ADMIN@ejemplo.com'    on conflict (user_id) do update set role='admin';
--  insert into public.g_roles(user_id,role) select id,'operador' from auth.users where email='MAIL_DEL_OPERADOR@ejemplo.com' on conflict (user_id) do update set role='operador';
-- =====================================================================
