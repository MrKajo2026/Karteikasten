-- Karteikasten v2: Karten einzeln, Lernstand pro Person, gemeinsame Sets, Ordner, Bilder.
-- Im Supabase SQL Editor komplett einfügen und "Run" klicken. Kann gefahrlos mehrfach ausgeführt werden.
-- Bestehende Lernsets bleiben erhalten; die App übernimmt sie beim ersten Start automatisch ins neue Format.

-- ---------- Hilfsfunktion: darf der angemeldete Nutzer dieses Set sehen? ----------
create table if not exists public.set_members (
  set_id   text not null references public.sets(id) on delete cascade,
  user_id  uuid not null references auth.users(id) on delete cascade,
  added_at timestamptz not null default now(),
  primary key (set_id, user_id)
);

create or replace function public.can_access_set(sid text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.sets s where s.id = sid and s.user_id = auth.uid())
      or exists (select 1 from public.set_members m where m.set_id = sid and m.user_id = auth.uid());
$$;

-- ---------- Sets: Eigentümer und Mitglieder lesen/bearbeiten, nur Eigentümer löscht ----------
drop policy if exists "eigene sets lesen"     on public.sets;
drop policy if exists "eigene sets anlegen"   on public.sets;
drop policy if exists "eigene sets aendern"   on public.sets;
drop policy if exists "eigene sets loeschen"  on public.sets;
drop policy if exists "sets lesen"    on public.sets;
drop policy if exists "sets anlegen"  on public.sets;
drop policy if exists "sets aendern"  on public.sets;
drop policy if exists "sets loeschen" on public.sets;
create policy "sets lesen"    on public.sets for select using (public.can_access_set(id));
create policy "sets anlegen"  on public.sets for insert with check (user_id = auth.uid());
create policy "sets aendern"  on public.sets for update using (public.can_access_set(id)) with check (public.can_access_set(id));
create policy "sets loeschen" on public.sets for delete using (user_id = auth.uid());

-- ---------- Karten ----------
create table if not exists public.cards (
  id         text primary key,
  set_id     text not null references public.sets(id) on delete cascade,
  t          text not null default '',
  d          text not null default '',
  img        text,
  pos        double precision not null default 0,
  updated_at timestamptz not null default now()
);
create index if not exists cards_set_idx on public.cards(set_id, pos);
alter table public.cards enable row level security;
drop policy if exists "karten" on public.cards;
create policy "karten" on public.cards for all
  using (public.can_access_set(set_id)) with check (public.can_access_set(set_id));

-- ---------- Lernstand pro Person und Set ----------
create table if not exists public.progress (
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  set_id     text not null references public.sets(id) on delete cascade,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (user_id, set_id)
);
alter table public.progress enable row level security;
drop policy if exists "eigener lernstand" on public.progress;
create policy "eigener lernstand" on public.progress for all
  using (user_id = auth.uid()) with check (user_id = auth.uid() and public.can_access_set(set_id));

-- ---------- Persönliche Daten (Ordner) ----------
create table if not exists public.user_data (
  user_id    uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.user_data enable row level security;
drop policy if exists "eigene daten" on public.user_data;
create policy "eigene daten" on public.user_data for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------- Mitglieder: lesen erlaubt, Ändern nur über die Funktionen unten ----------
alter table public.set_members enable row level security;
drop policy if exists "mitglieder lesen"   on public.set_members;
drop policy if exists "set verlassen"      on public.set_members;
create policy "mitglieder lesen" on public.set_members for select using (public.can_access_set(set_id));
create policy "set verlassen"    on public.set_members for delete using (user_id = auth.uid());

-- Set per E-Mail teilen (nur Eigentümer). Rückgabe: ok | not_owner | no_user | self
drop function if exists public.share_set(text, text);
create or replace function public.share_set(sid text, p_email text)
returns text language plpgsql security definer set search_path = public as $$
declare uid uuid;
begin
  if not exists (select 1 from public.sets where id = sid and user_id = auth.uid()) then return 'not_owner'; end if;
  select u.id into uid from auth.users u where lower(u.email) = lower(trim(p_email));
  if uid is null then return 'no_user'; end if;
  if uid = auth.uid() then return 'self'; end if;
  insert into public.set_members(set_id, user_id) values (sid, uid) on conflict do nothing;
  return 'ok';
end $$;

-- Freigabe entfernen (nur Eigentümer)
create or replace function public.unshare_set(sid text, p_uid uuid)
returns text language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.sets where id = sid and user_id = auth.uid()) then return 'not_owner'; end if;
  delete from public.set_members where set_id = sid and user_id = p_uid;
  return 'ok';
end $$;

-- Wer hat Zugriff auf das Set (für die Anzeige)
create or replace function public.set_people(sid text)
returns table(user_id uuid, email text, role text) language sql stable security definer set search_path = public as $$
  select s.user_id, u.email::text, 'owner' from public.sets s join auth.users u on u.id = s.user_id
   where s.id = sid and public.can_access_set(sid)
  union all
  select m.user_id, u.email::text, 'member' from public.set_members m join auth.users u on u.id = m.user_id
   where m.set_id = sid and public.can_access_set(sid);
$$;

-- ---------- Bilder (privater Speicher, Ordner = Set-ID) ----------
insert into storage.buckets (id, name, public) values ('card-images', 'card-images', false)
  on conflict (id) do nothing;
drop policy if exists "kartenbilder lesen"    on storage.objects;
drop policy if exists "kartenbilder anlegen"  on storage.objects;
drop policy if exists "kartenbilder aendern"  on storage.objects;
drop policy if exists "kartenbilder loeschen" on storage.objects;
create policy "kartenbilder lesen"    on storage.objects for select to authenticated
  using (bucket_id = 'card-images' and public.can_access_set((storage.foldername(name))[1]));
create policy "kartenbilder anlegen"  on storage.objects for insert to authenticated
  with check (bucket_id = 'card-images' and public.can_access_set((storage.foldername(name))[1]));
create policy "kartenbilder aendern"  on storage.objects for update to authenticated
  using (bucket_id = 'card-images' and public.can_access_set((storage.foldername(name))[1]));
create policy "kartenbilder loeschen" on storage.objects for delete to authenticated
  using (bucket_id = 'card-images' and public.can_access_set((storage.foldername(name))[1]));

-- ---------- Rechte für angemeldete Nutzer ----------
revoke all on public.cards, public.progress, public.user_data, public.set_members from anon;
grant select, insert, update, delete on public.sets, public.cards, public.progress, public.user_data to authenticated;
grant select, delete on public.set_members to authenticated;
revoke execute on function public.share_set(text, text), public.unshare_set(text, uuid), public.set_people(text), public.can_access_set(text) from public, anon;
grant execute on function public.share_set(text, text), public.unshare_set(text, uuid), public.set_people(text), public.can_access_set(text) to authenticated;
