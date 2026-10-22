-- Coffee Shop App, Supabase schema, Sprint 0 (directory only)
-- Stage 6 build spec (approved Oct 22, 2026): Supabase holds the curated
-- Detroit directory and, from Sprint 6, optional account sync. User data
-- tables (visits, want_to_go, companions, settings) are added in Sprint 6
-- with row level security keyed to the owner. They are deliberately NOT
-- created here, so Sprint 0 ships the directory foundation only.
--
-- Status: written and reviewed, NOT yet applied. The Supabase project
-- itself is created under Risha's account (account holder step in the
-- Sprint 0 report). Run this file once in the project's SQL editor (or
-- as the first migration) after the project exists, then record the date
-- applied in the Sprint 0 section of the testing log.
--
-- Data honesty rules carried in the schema itself:
-- * Every shop carries a source and a last_verified_date. A row without
--   them is incomplete by construction (both are NOT NULL).
-- * A photo reference may be set only when photo_rights records the basis
--   for using it (shop provided, licensed, or created by us). No scraped
--   map or review site photos, per the build spec.

create extension if not exists "pgcrypto";

create table if not exists public.shops (
    id                uuid primary key default gen_random_uuid(),
    name              text not null,
    address           text not null,
    neighborhood      text not null,
    latitude          double precision not null,
    longitude         double precision not null,
    kind              text not null check (kind in ('independent', 'chain')),
    -- Weekly hours as JSON, one object per weekday, for example
    -- {"mon": {"open": "07:00", "close": "18:00"}, "tue": null}
    -- A null day means closed that day. Open Now is computed on device
    -- from this data and the phone clock (Story S3).
    hours             jsonb not null default '{}'::jsonb,
    tags              text[] not null default '{}',
    photo_url         text,
    photo_rights       text check (photo_rights in ('shop_provided', 'licensed', 'created_by_us')),
    source            text not null,
    last_verified_date date not null,
    is_published      boolean not null default false,
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    constraint shops_photo_rights_required
        check (photo_url is null or photo_rights is not null)
);

create index if not exists shops_neighborhood_idx on public.shops (neighborhood);
create index if not exists shops_published_idx on public.shops (is_published);

-- The directory is public read for published shops only. Writes happen
-- through our curation process with the service role, never from the app.
alter table public.shops enable row level security;

drop policy if exists "Published shops are readable" on public.shops;
create policy "Published shops are readable"
    on public.shops
    for select
    using (is_published = true);

-- Sprint 0 verification (from the build plan's definition of done):
-- after applying this file, insert one test shop with a source and a
-- last_verified_date, confirm it can be read back, then delete it and
-- record the result in 06-build/testing-log.md.
