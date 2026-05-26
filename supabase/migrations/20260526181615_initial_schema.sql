create table public.users (
    id uuid primary key default gen_random_uuid(),
    email text unique not null,
    full_name text,
    created_at timestamptz default now()
  );
create table public.orders (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references public.users(id) on delete
  cascade,
    item text not null,
    price_cents int not null,
    created_at timestamptz default now()
  );
alter table public.orders enable row level security;
create policy "users see own orders"
    on public.orders for select
    using (auth.uid() = user_id);
