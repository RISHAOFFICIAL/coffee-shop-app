-- Coffee Shop App, Supabase user data schema, Sprint 6 (accounts and sync)
-- Story S14: the backup tables for a signed in user's own data. Every row
-- belongs to one owner, and row level security makes that a hard rule: no
-- user can read, write, or delete another user's rows, even by mistake.
-- The app only ever uses the anon key with the user's own access token;
-- the service role key never leaves the server side (the delete-account
-- edge function is the only thing that uses it).
--
-- Status: written and reviewed, NOT yet applied. The Supabase project
-- itself does not exist yet (Sprint 0 account holder step). After the
-- project exists, run schema.sql first, then this file, in the project's
-- SQL editor (or as the second migration), and record the date applied in
-- the Sprint 6 section of the testing log.
--
-- Privacy rules carried in the schema itself:
-- * Every table has an owner id referencing auth.users with ON DELETE
--   CASCADE: deleting the auth user deletes the rows, so account deletion
--   cannot leave a user's log behind.
-- * RLS is enabled on every table, with owner-only policies for all four
--   operations. There is no public read anywhere in this file.
-- * Photos live in the private visit-photos bucket, one folder per owner,
--   and storage policies only allow the owner into their own folder.
-- * Nothing here stores a name, email, or location beyond what the visit
--   itself already holds: shop name, neighborhood, and address are the
--   same fields the app stores on the phone.

create extension if not exists "pgcrypto";

-- Visits: the backed up log. Columns mirror VisitDTO in
-- CoffeeShopApp/Data/SupabaseSyncClient.swift, snake_case on the wire.
create table if not exists public.visits (
    id                  uuid primary key,
    owner_id            uuid not null references auth.users (id) on delete cascade,
    shop_id             uuid not null,
    shop_name           text not null,
    neighborhood        text not null default '',
    address             text not null default '',
    checked_in_at       timestamptz not null,
    source              text not null default 'manual',
    rating              integer check (rating is null or (rating between 1 and 5)),
    tags                text[] not null default '{}',
    order_text          text,
    note                text,
    companion_ids       uuid[] not null default '{}',
    photo_path          text,
    is_unverified_shop  boolean not null default false,
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now()
);
create index if not exists visits_owner_id_idx on public.visits (owner_id);
create index if not exists visits_owner_checked_in_idx on public.visits (owner_id, checked_in_at desc);

-- Want To Go: saved shops, not visits. Columns mirror WantToGoDTO.
create table if not exists public.want_to_go (
    id                  uuid primary key,
    owner_id            uuid not null references auth.users (id) on delete cascade,
    shop_id             uuid not null,
    shop_name           text not null,
    neighborhood        text not null default '',
    address             text not null default '',
    shared_by           text,
    note_from_sharer    text,
    added_at            timestamptz not null default now(),
    updated_at          timestamptz not null default now()
);
create index if not exists want_to_go_owner_id_idx on public.want_to_go (owner_id);

-- Companions: who she was with. Names only, no contact info, and the
-- app never imports contacts. The unique index keeps one row per name
-- per owner, case insensitive, matching the app's dedupe rule.
create table if not exists public.companions (
    id                  uuid primary key,
    owner_id            uuid not null references auth.users (id) on delete cascade,
    name                text not null,
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now()
);
create index if not exists companions_owner_id_idx on public.companions (owner_id);
create unique index if not exists companions_owner_name_idx
    on public.companions (owner_id, lower(name));

-- Settings: one row per user, keyed by user id. Only the settings the
-- app syncs live here; first launch state and the reminder dismissal
-- stay on the phone. Columns mirror UserSettingsDTO.
create table if not exists public.user_settings (
    user_id                         uuid primary key references auth.users (id) on delete cascade,
    auto_check_in_prompts_enabled   boolean not null default true,
    share_notes_by_default          boolean not null default false,
    sharer_name                     text,
    updated_at                      timestamptz not null default now()
);

-- Row level security: owner only, on every table, for every operation.
alter table public.visits enable row level security;
alter table public.want_to_go enable row level security;
alter table public.companions enable row level security;
alter table public.user_settings enable row level security;

create policy "Owners manage their own visits"
    on public.visits for all
    using (auth.uid() = owner_id)
    with check (auth.uid() = owner_id);

create policy "Owners manage their own want to go list"
    on public.want_to_go for all
    using (auth.uid() = owner_id)
    with check (auth.uid() = owner_id);

create policy "Owners manage their own companions"
    on public.companions for all
    using (auth.uid() = owner_id)
    with check (auth.uid() = owner_id);

create policy "Owners manage their own settings"
    on public.user_settings for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- Visit photos: a private bucket, one folder per owner. The app uploads
-- to <owner id>/<visit id>.jpg and downloads from the same path. The
-- storage policies allow the owner only into their own folder; the first
-- path segment must equal their auth id.
insert into storage.buckets (id, name, public)
values ('visit-photos', 'visit-photos', false)
on conflict (id) do nothing;

create policy "Owners read their own visit photos"
    on storage.objects for select
    using (
        bucket_id = 'visit-photos'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

create policy "Owners upload their own visit photos"
    on storage.objects for insert
    with check (
        bucket_id = 'visit-photos'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

create policy "Owners replace their own visit photos"
    on storage.objects for update
    using (
        bucket_id = 'visit-photos'
        and (storage.foldername(name))[1] = auth.uid()::text
    )
    with check (
        bucket_id = 'visit-photos'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

create policy "Owners delete their own visit photos"
    on storage.objects for delete
    using (
        bucket_id = 'visit-photos'
        and (storage.foldername(name))[1] = auth.uid()::text
    );
