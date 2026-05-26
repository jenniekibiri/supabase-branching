alter table public.users
    add column loyalty_points int not null default 0;
create table public.rewards (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    cost_points int not null
  );
alter table public.rewards enable row level security;
create policy "anyone can read rewards"
    on public.rewards for select
    using (true);
insert into public.rewards (name, cost_points) values
    ('Free espresso', 50),
    ('Free pastry',   80);
