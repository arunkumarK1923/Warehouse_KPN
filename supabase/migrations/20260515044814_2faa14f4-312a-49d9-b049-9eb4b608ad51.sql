
drop table if exists public.division cascade;
drop table if exists public.department cascade;
drop table if exists public.brand cascade;
drop table if exists public.quality_spec cascade;
drop table if exists public.pricing cascade;
drop table if exists public.promotion cascade;
drop table if exists public.warehouse cascade;
drop table if exists public.outlet_mapping cascade;
drop table if exists public.vendor_mapping cascade;
drop table if exists public.digital_asset cascade;
drop table if exists public.bulk_upload cascade;
drop table if exists public.api_integration cascade;

create table public.master_records (
  id uuid primary key default gen_random_uuid(),
  module text not null,
  record_id text not null,
  data jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (module, record_id)
);
create index idx_master_records_module on public.master_records(module);

alter table public.master_records enable row level security;

create policy "Authenticated read master_records"
  on public.master_records for select to authenticated using (true);
create policy "Admins write master_records"
  on public.master_records for all to authenticated
  using (public.has_role(auth.uid(), 'admin'))
  with check (public.has_role(auth.uid(), 'admin'));

create trigger trg_master_records_updated
  before update on public.master_records
  for each row execute function public.update_updated_at_column();
