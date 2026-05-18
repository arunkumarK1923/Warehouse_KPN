
drop policy if exists "auth insert audit" on public.audit_events;
revoke execute on function public.master_records_after_change() from public, authenticated, anon;
