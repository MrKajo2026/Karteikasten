# Karteikasten

Vokabeltrainer mit Lernsets, Ordnern, Suche, Foto-Import, Karteikarten (Wischen), Lernen (adaptiv), Test, Zuordnen, Wiederholen nach Fächern, Aussprache, Bildern und gemeinsamen Sets.

- `index.html` – die App (GitHub Pages)
- `supabase/setup.sql` – Grundtabelle (Version 1)
- `supabase/setup-v2.sql` – Update für Version 2: Karten, Lernstand pro Person, Teilen, Ordner, Bilder
- `supabase/setup-v3.sql` – Profilbilder
- `supabase/functions/scan/index.ts` – Fotoerkennung (in Supabase als Funktion `smart-service` deployt)
