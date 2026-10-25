-- Karteikasten v4: Korrektur – neue Lernsets anlegen.
-- Im Supabase SQL Editor einfügen und "Run" klicken. Kann gefahrlos mehrfach ausgeführt werden.
-- Ursache: Beim Anlegen (upsert) prüft die Datenbank auch die Leseregel für das neue Set.
-- Die bisherige Regel konnte das gerade entstehende Set noch nicht sehen und lehnte ab.
-- Neu: Wer das Set anlegt (user_id = eigene ID), darf es immer lesen und ändern.

drop policy if exists "sets lesen"   on public.sets;
drop policy if exists "sets aendern" on public.sets;
create policy "sets lesen"   on public.sets for select
  using (user_id = auth.uid() or public.can_access_set(id));
create policy "sets aendern" on public.sets for update
  using (user_id = auth.uid() or public.can_access_set(id))
  with check (user_id = auth.uid() or public.can_access_set(id));
