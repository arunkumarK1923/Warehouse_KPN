
-- ============ Typed master tables ============
create table public.divisions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_divisions_code on public.divisions(code);

create table public.departments (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  division_code text references public.divisions(code) on update cascade on delete set null,
  description text,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_departments_code on public.departments(code);
create index idx_departments_division on public.departments(division_code);

create table public.brands (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  division_code text references public.divisions(code) on update cascade on delete set null,
  vendor text,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_brands_code on public.brands(code);
create index idx_brands_division on public.brands(division_code);

create table public.warehouses (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  city text,
  capacity integer,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_warehouses_code on public.warehouses(code);

alter table public.divisions enable row level security;
alter table public.departments enable row level security;
alter table public.brands enable row level security;
alter table public.warehouses enable row level security;

create policy "auth read divisions" on public.divisions for select to authenticated using (true);
create policy "admin write divisions" on public.divisions for all to authenticated using (has_role(auth.uid(),'admin')) with check (has_role(auth.uid(),'admin'));
create policy "auth read departments" on public.departments for select to authenticated using (true);
create policy "admin write departments" on public.departments for all to authenticated using (has_role(auth.uid(),'admin')) with check (has_role(auth.uid(),'admin'));
create policy "auth read brands" on public.brands for select to authenticated using (true);
create policy "admin write brands" on public.brands for all to authenticated using (has_role(auth.uid(),'admin')) with check (has_role(auth.uid(),'admin'));
create policy "auth read warehouses" on public.warehouses for select to authenticated using (true);
create policy "admin write warehouses" on public.warehouses for all to authenticated using (has_role(auth.uid(),'admin')) with check (has_role(auth.uid(),'admin'));

create trigger trg_divisions_updated before update on public.divisions for each row execute function public.update_updated_at_column();
create trigger trg_departments_updated before update on public.departments for each row execute function public.update_updated_at_column();
create trigger trg_brands_updated before update on public.brands for each row execute function public.update_updated_at_column();
create trigger trg_warehouses_updated before update on public.warehouses for each row execute function public.update_updated_at_column();

-- ============ Audit events ============
create table public.audit_events (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid,
  actor_email text,
  module text not null,
  action text not null, -- INSERT | UPDATE | DELETE
  record_id text,
  before_data jsonb,
  after_data jsonb,
  created_at timestamptz not null default now()
);
create index idx_audit_module on public.audit_events(module);
create index idx_audit_created on public.audit_events(created_at desc);

alter table public.audit_events enable row level security;
create policy "auth read audit" on public.audit_events for select to authenticated using (true);
create policy "auth insert audit" on public.audit_events for insert to authenticated with check (true);

-- ============ Sync + audit trigger on master_records ============
create or replace function public.master_records_after_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_module text;
  v_data jsonb;
  v_old jsonb;
  v_action text;
  v_record_id text;
begin
  v_action := tg_op;
  if v_action = 'DELETE' then
    v_module := old.module;
    v_record_id := old.record_id;
    v_data := null;
    v_old := old.data;
  else
    v_module := new.module;
    v_record_id := new.record_id;
    v_data := new.data;
    v_old := case when v_action='UPDATE' then old.data else null end;
  end if;

  select email into v_email from public.profiles where user_id = coalesce(new.created_by, old.created_by) limit 1;

  insert into public.audit_events(actor_id, actor_email, module, action, record_id, before_data, after_data)
  values (coalesce(new.created_by, old.created_by), v_email, v_module, v_action, v_record_id, v_old, v_data);

  -- Sync typed tables for selected modules
  if v_module = 'division' then
    if v_action = 'DELETE' then
      delete from public.divisions where code = v_record_id;
    else
      insert into public.divisions(code, name, description, status)
      values (v_record_id, coalesce(v_data->>'name', v_record_id), v_data->>'description', coalesce(v_data->>'status','active'))
      on conflict (code) do update set
        name = excluded.name,
        description = excluded.description,
        status = excluded.status,
        updated_at = now();
    end if;
  elsif v_module = 'department' then
    if v_action = 'DELETE' then
      delete from public.departments where code = v_record_id;
    else
      insert into public.departments(code, name, division_code, description, status)
      values (v_record_id, coalesce(v_data->>'name', v_record_id), v_data->>'division', v_data->>'description', coalesce(v_data->>'status','active'))
      on conflict (code) do update set
        name = excluded.name, division_code = excluded.division_code,
        description = excluded.description, status = excluded.status, updated_at = now();
    end if;
  elsif v_module = 'brand' then
    if v_action = 'DELETE' then
      delete from public.brands where code = v_record_id;
    else
      insert into public.brands(code, name, division_code, vendor, status)
      values (v_record_id, coalesce(v_data->>'name', v_record_id), v_data->>'division', v_data->>'vendor', coalesce(v_data->>'status','active'))
      on conflict (code) do update set
        name = excluded.name, division_code = excluded.division_code,
        vendor = excluded.vendor, status = excluded.status, updated_at = now();
    end if;
  elsif v_module = 'warehouse' then
    if v_action = 'DELETE' then
      delete from public.warehouses where code = v_record_id;
    else
      insert into public.warehouses(code, name, city, capacity, status)
      values (v_record_id, coalesce(v_data->>'name', v_record_id), v_data->>'city',
              nullif(v_data->>'capacity','')::int, coalesce(v_data->>'status','active'))
      on conflict (code) do update set
        name = excluded.name, city = excluded.city,
        capacity = excluded.capacity, status = excluded.status, updated_at = now();
    end if;
  end if;

  return coalesce(new, old);
end;
$$;

create trigger trg_master_records_audit
after insert or update or delete on public.master_records
for each row execute function public.master_records_after_change();

-- ============ Realtime ============
alter publication supabase_realtime add table public.master_records;
alter publication supabase_realtime add table public.audit_events;
