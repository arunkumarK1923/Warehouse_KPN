
-- =========================
-- AUTH & ROLES
-- =========================
create type public.app_role as enum ('admin', 'user');

create table public.profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  email text,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.profiles enable row level security;

create table public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.app_role not null,
  created_at timestamptz not null default now(),
  unique (user_id, role)
);
alter table public.user_roles enable row level security;

create or replace function public.has_role(_user_id uuid, _role public.app_role)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.user_roles where user_id = _user_id and role = _role)
$$;

-- updated_at helper
create or replace function public.update_updated_at_column()
returns trigger language plpgsql set search_path = public as $$
begin new.updated_at = now(); return new; end;
$$;

-- Auto profile + role on signup
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (user_id, email, display_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'display_name', new.email));

  if new.email = 'arunkathir2002ak@gmail.com' then
    insert into public.user_roles (user_id, role) values (new.id, 'admin')
    on conflict do nothing;
  else
    insert into public.user_roles (user_id, role) values (new.id, 'user')
    on conflict do nothing;
  end if;
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- Profile policies
create policy "Users view own profile" on public.profiles
  for select to authenticated using (auth.uid() = user_id);
create policy "Admins view all profiles" on public.profiles
  for select to authenticated using (public.has_role(auth.uid(), 'admin'));
create policy "Users update own profile" on public.profiles
  for update to authenticated using (auth.uid() = user_id);

create trigger trg_profiles_updated before update on public.profiles
for each row execute function public.update_updated_at_column();

-- user_roles policies (admin-managed)
create policy "Users view own roles" on public.user_roles
  for select to authenticated using (auth.uid() = user_id);
create policy "Admins view all roles" on public.user_roles
  for select to authenticated using (public.has_role(auth.uid(), 'admin'));
create policy "Admins manage roles" on public.user_roles
  for all to authenticated
  using (public.has_role(auth.uid(), 'admin'))
  with check (public.has_role(auth.uid(), 'admin'));

-- =========================
-- Generic helper to apply RLS to master tables
-- (read: any authenticated; write: admin only)
-- =========================

-- DIVISION
create table public.division (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  status text not null default 'Active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- DEPARTMENT
create table public.department (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  division text,
  description text,
  status text not null default 'Active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- BRAND
create table public.brand (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  vendor text,
  category text,
  status text not null default 'Active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- QUALITY SPEC
create table public.quality_spec (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  parameter text,
  acceptable_range text,
  unit text,
  status text not null default 'Active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- PRICING
create table public.pricing (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  sku text not null,
  mrp numeric,
  selling_price numeric,
  cost_price numeric,
  effective_from date,
  status text not null default 'Active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- PROMOTION
create table public.promotion (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  discount_pct numeric,
  start_date date,
  end_date date,
  status text not null default 'Active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- WAREHOUSE
create table public.warehouse (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  location text,
  capacity numeric,
  manager text,
  status text not null default 'Active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- OUTLET MAPPING
create table public.outlet_mapping (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  outlet text not null,
  warehouse text,
  region text,
  status text not null default 'Active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- VENDOR MAPPING
create table public.vendor_mapping (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  vendor text not null,
  brand text,
  category text,
  contact text,
  status text not null default 'Active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- DIGITAL ASSET
create table public.digital_asset (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  asset_type text,
  url text,
  tags text,
  status text not null default 'Active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- BULK UPLOAD history
create table public.bulk_upload (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  module text not null,
  file_name text,
  records integer default 0,
  status text not null default 'Pending',
  uploaded_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- API INTEGRATION
create table public.api_integration (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  category text, -- connection / key / webhook / log
  endpoint text,
  api_key text,
  status text not null default 'Active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Enable RLS + policies + updated_at triggers for all data tables
do $$
declare t text;
begin
  for t in select unnest(array[
    'division','department','brand','quality_spec','pricing','promotion',
    'warehouse','outlet_mapping','vendor_mapping','digital_asset',
    'bulk_upload','api_integration'
  ]) loop
    execute format('alter table public.%I enable row level security;', t);
    execute format($p$create policy "Authenticated read %1$I" on public.%1$I for select to authenticated using (true);$p$, t);
    execute format($p$create policy "Admins write %1$I" on public.%1$I for all to authenticated using (public.has_role(auth.uid(), 'admin')) with check (public.has_role(auth.uid(), 'admin'));$p$, t);
    execute format('create trigger trg_%1$I_updated before update on public.%1$I for each row execute function public.update_updated_at_column();', t);
  end loop;
end $$;
