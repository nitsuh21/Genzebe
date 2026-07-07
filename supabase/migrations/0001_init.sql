-- GenzeBet backend schema.
-- Paste into the Supabase SQL editor (or run via `supabase db push`).

-- ---------------------------------------------------------------------------
-- Profiles: one row per auth user, mirrored from Google metadata on signup.
-- ---------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  display_name text,
  photo_url text,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "Users can read their own profile"
  on public.profiles for select
  using (auth.uid() = id);

create policy "Users can update their own profile"
  on public.profiles for update
  using (auth.uid() = id);

-- ---------------------------------------------------------------------------
-- Plans: catalog of tiers. Only freemium is purchasable today; others are
-- announced in-app as coming soon.
-- ---------------------------------------------------------------------------
create table public.plans (
  code text primary key,
  name text not null,
  price_etb_minor integer not null default 0,
  is_available boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.plans enable row level security;

create policy "Plans are readable by any signed-in user"
  on public.plans for select
  to authenticated
  using (true);

insert into public.plans (code, name, price_etb_minor, is_available) values
  ('freemium', 'Freemium', 0, true),
  ('plus', 'Genze Plus', 0, false),
  ('circle', 'Genze Circle', 0, false);

-- ---------------------------------------------------------------------------
-- Subscriptions: the user's active plan. Freemium is auto-provisioned by the
-- signup trigger below, so every account always has exactly one active row.
-- Writes are server-side only (service role / future payment webhook) —
-- clients can read but never grant themselves a plan.
-- ---------------------------------------------------------------------------
create table public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  plan_code text not null references public.plans (code),
  status text not null default 'active' check (status in ('active', 'cancelled', 'expired')),
  started_at timestamptz not null default now(),
  expires_at timestamptz,
  created_at timestamptz not null default now()
);

create unique index one_active_subscription_per_user
  on public.subscriptions (user_id)
  where status = 'active';

alter table public.subscriptions enable row level security;

create policy "Users can read their own subscription"
  on public.subscriptions for select
  using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Signup trigger: create profile + freemium subscription for each new user.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, display_name, photo_url)
  values (
    new.id,
    coalesce(new.email, ''),
    new.raw_user_meta_data ->> 'full_name',
    new.raw_user_meta_data ->> 'avatar_url'
  )
  on conflict (id) do nothing;

  insert into public.subscriptions (user_id, plan_code, status)
  values (new.id, 'freemium', 'active')
  on conflict do nothing;

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
