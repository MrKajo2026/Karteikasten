-- Karteikasten v3: Profilbilder.
-- Im Supabase SQL Editor einfügen und "Run" klicken. Kann gefahrlos mehrfach ausgeführt werden.
-- Jede Person darf nur ihr eigenes Bild hochladen/ändern; angemeldete Nutzer der App dürfen Profilbilder sehen.

insert into storage.buckets (id, name, public) values ('avatars', 'avatars', false)
  on conflict (id) do nothing;

drop policy if exists "profilbilder lesen"    on storage.objects;
drop policy if exists "profilbild anlegen"    on storage.objects;
drop policy if exists "profilbild aendern"    on storage.objects;
drop policy if exists "profilbild loeschen"   on storage.objects;
create policy "profilbilder lesen"  on storage.objects for select to authenticated
  using (bucket_id = 'avatars');
create policy "profilbild anlegen"  on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "profilbild aendern"  on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "profilbild loeschen" on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
