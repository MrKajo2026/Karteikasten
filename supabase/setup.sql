-- Karteikasten: Tabelle für Lernsets, jede Person sieht nur ihre eigenen.
-- Im Supabase-Dashboard unter "SQL Editor" einfügen und "Run" klicken.

create table if not exists public.sets (
  id          text primary key,
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  doc         jsonb not null,
  updated_at  timestamptz not null default now()
);

alter table public.sets enable row level security;

drop policy if exists "eigene sets lesen"     on public.sets;
drop policy if exists "eigene sets anlegen"   on public.sets;
drop policy if exists "eigene sets aendern"   on public.sets;
drop policy if exists "eigene sets loeschen"  on public.sets;

create policy "eigene sets lesen"    on public.sets for select using (user_id = auth.uid());
create policy "eigene sets anlegen"  on public.sets for insert with check (user_id = auth.uid());
create policy "eigene sets aendern"  on public.sets for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "eigene sets loeschen" on public.sets for delete using (user_id = auth.uid());

create index if not exists sets_user_idx on public.sets(user_id);

-- Zugriff nur für angemeldete Nutzer freigeben (nötig, wenn "Automatically expose new tables" aus ist).
-- Welche Zeilen sie sehen, regeln die Policies oben.
revoke all on public.sets from anon;
grant select, insert, update, delete on public.sets to authenticated;
