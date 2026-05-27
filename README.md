# Supabase Branching — Concepts


---

## A practical scenario (so the rest makes sense)

Imagine you run a **coffee shop app** on Supabase. Production has:
- `orders` table with 50,000 rows
- `users` table with 10,000 customers
- A few Edge Functions
- Row-Level Security (RLS) policies

Tomorrow you want to **add a "loyalty points" feature**. You need:
- A new `loyalty_points` column on `users`
- A new `rewards` table
- A new RLS policy
- A migration

**Where do you build and test this?**

---

## Why we need branching

Without branching, your options are all bad:

1. **Build directly on production** → one bad migration drops a column, real customer data is gone. Terrifying.
2. **Run a local Supabase instance** (`supabase start`) → works, but doesn't match production. No real auth users, no real Edge Function secrets, no real storage buckets. "Works on my laptop" syndrome.
3. **Spin up a second Supabase project manually** → tedious. You'd have to copy schema, seed data, reconfigure auth, sync env vars. Every dev on the team duplicates this.
4. **Share one "staging" project across the whole team** → Alice's migration conflicts with Bob's. They overwrite each other. Whose schema wins?

The core problem: **databases don't branch like code does.** Git lets you make a feature branch in 1 second. Postgres does not.

---

## What branching is

A **Supabase branch** is a full, isolated Supabase environment (database + auth + storage + Edge Functions + API keys) that gets created automatically when you push a Git branch.

Mental model:

```
Git branch:        feature/loyalty-points
                          │
                          ▼
Supabase branch:   db-feature-loyalty-points.supabase.co
                   (its own Postgres, its own auth, its own keys)
```

It's tied to your Git workflow. You `git push` → Supabase spins up a preview environment for that branch. You merge the PR → migrations run on production.

---

## Problems it solves

| Problem | How branching solves it |
|---|---|
| Risky migrations on prod | Migrations run on the branch first; you see them work before merging |
| Devs stepping on each other | Each PR gets its **own** branch DB |
| Local ≠ production drift | Branch DB inherits production's schema; matches reality |
| Manual env duplication | Created automatically on `git push` |
| Code review without DB review | Reviewers can hit the branch's API endpoint with the actual change live |

---

## Persistent vs. Preview branches

This is the key distinction.

**Preview branches** (the default)
- Tied 1:1 to a Git branch / PR
- Created on push, **destroyed on merge or PR close**
- Ephemeral — meant for "build the feature, test it, merge, gone"
- Each PR is isolated from every other PR

**Persistent branches**
- Long-lived. Don't get torn down when a PR closes.
- Used for **staging**, **QA**, **demo**, or any environment that needs to outlive a single feature
- Example: a `staging` branch your QA team always points to, accumulating multiple merged features before promotion to prod
- You name them explicitly and they stay until you delete them

The typical workflow ends up being:

```
main (production)
  ▲
  │  merge
  │
staging (persistent branch) ──── QA team tests here
  ▲
  │  merge
  │
feature/loyalty-points (preview branch, auto-created, auto-destroyed)
feature/dark-mode      (preview branch)
feature/refund-flow    (preview branch)
```

---

# Practical Walkthrough

We'll build the coffee shop app, then add the loyalty-points feature on a Supabase preview branch — exactly the scenario from the top of this README.

## Prerequisites

| Tool | Why | Install |
|---|---|---|
| Supabase CLI | Init project, write migrations, link to cloud | `brew install supabase/tap/supabase` |
| Git | Branching is driven by Git | preinstalled on macOS |
| Docker | Required for the local Supabase stack | Docker Desktop |
| A Supabase project on **Pro plan** | Branching is paid-tier only | supabase.com → New Project → Pro |
| A GitHub repo | Supabase watches GitHub to create preview branches | github.com |

Check what you have:

```bash
supabase --version
git --version
docker --version
```

---

## Step 1 — Initialize the local Supabase project

In an empty directory:

```bash
supabase init
```

This creates a `supabase/` folder with `config.toml` and a `migrations/` folder. Nothing is in the cloud yet — this is purely local scaffolding.

---

## Step 2 — Build the "production" coffee shop schema

Create the first migration:

```bash
supabase migration new initial_schema
```

That creates a file like `supabase/migrations/<timestamp>_initial_schema.sql`. Open it and paste:

```sql
-- users: customers of the coffee shop
create table public.users (
  id uuid primary key default gen_random_uuid(),
  email text unique not null,
  full_name text,
  created_at timestamptz default now()
);

-- orders: every coffee sold
create table public.orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.users(id) on delete cascade,
  item text not null,
  price_cents int not null,
  created_at timestamptz default now()
);

-- Row-Level Security so users can only see their own orders
alter table public.orders enable row level security;

create policy "users see own orders"
  on public.orders for select
  using (auth.uid() = user_id);
```

This is our **production baseline**. Test it locally:

```bash
supabase start         # boots local Postgres + auth + storage in Docker
supabase db reset      # applies all migrations to the local DB
```

Visit the local Studio at `http://localhost:54323` to confirm the tables exist.

---

## Step 3 — Put it in a Git repo and push to GitHub

```bash
git init
git add .
git commit -m "Initial coffee shop schema"

# Create the repo on github.com first, then:
git remote add origin git@github.com:<you>/supabase-branching-learning.git
git branch -M main
git push -u origin main
```

Branching only works when Supabase can read your migrations from GitHub, so this step is non-optional.

---

## Step 4 — Link your local project to your Supabase Pro project

```bash
supabase login          # opens browser
supabase link --project-ref <your-project-ref>
```

You find `<your-project-ref>` in the Supabase dashboard URL: `app.supabase.com/project/<ref>`.

---

## Step 5 — Push the initial schema to production

```bash
supabase db push
```

This runs your migrations against the linked cloud project. Now production matches your local schema.

> ⚠️ This is the first command that touches real cloud data. Run it on an empty project.

---

## Step 6 — Enable branching + connect GitHub

In the Supabase dashboard:

1. Project → **Branches** (left sidebar)
2. **Enable Branching** → confirm
3. **Connect GitHub repository** → pick the repo from Step 3
4. Set the **production branch** to `main`
5. Set the **supabase directory** to `supabase` (default)

From now on, every `git push` to a branch with changes in `supabase/migrations/` will create a preview branch.

---

## Step 7 — Build the loyalty feature on a Git branch

```bash
git checkout -b feature/loyalty-points
supabase migration new loyalty_points
```

Paste into the new migration file:

```sql
-- Add points balance to every user
alter table public.users
  add column loyalty_points int not null default 0;

-- Rewards customers can redeem
create table public.rewards (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  cost_points int not null
);

alter table public.rewards enable row level security;

create policy "anyone can read rewards"
  on public.rewards for select
  using (true);

-- Seed a couple of rewards
insert into public.rewards (name, cost_points) values
  ('Free espresso', 50),
  ('Free pastry',   80);
```

Test locally first:

```bash
supabase db reset      # re-runs all migrations on local DB
```

---

## Step 8 — Push the branch → preview branch appears

```bash
git add .
git commit -m "Add loyalty points feature"
git push -u origin feature/loyalty-points
```

Open a Pull Request on GitHub. Within ~1 minute:

- The Supabase **Branches** tab shows a new preview branch named after your Git branch
- The PR gets a comment from the Supabase GitHub app with the branch's API URL + anon key
- Both migrations (initial schema + loyalty points) have already run on the preview's Postgres

You now have a **completely isolated Supabase environment** for this PR — its own DB, its own auth users, its own keys.

---

## Step 9 — Test against the preview

Point your app (or `curl`/Postman) at the preview branch's API URL using the preview's anon key. Insert a row into `rewards`, check `loyalty_points` exists, try the RLS policy. Production is untouched.

---

## Step 10 — Merge → production migration

When you merge the PR into `main`:

- Supabase runs the new migration on **production**
- The preview branch is **destroyed**
- Production now has `loyalty_points` and `rewards`

The Git merge is the deployment.

---

## Step 11 — Create a persistent `staging` branch

For a long-lived QA environment that survives across many PRs:

```bash
supabase branches create staging --persistent
```

Or in the dashboard: **Branches** → **Create branch** → toggle **Persistent**.

Now `staging` lives forever (until you delete it). You can merge multiple feature branches into it, let QA bash on it for a week, then promote to production when you're ready.

---

## Cleanup (when the talk is over)

```bash
supabase branches delete <branch-name>     # remove preview branches
supabase stop                              # stop local Docker stack
```

And in the dashboard you can disable branching to stop incurring branch-compute cost.

---

# Quick reference — commands cheat sheet

```bash
supabase init                              # scaffold project
supabase migration new <name>              # create migration file
supabase start                             # boot local stack
supabase db reset                          # re-apply migrations locally
supabase login                             # auth CLI to cloud
supabase link --project-ref <ref>          # connect local to cloud project
supabase db push                           # push migrations to linked project
supabase branches list                     # list cloud branches
supabase branches create <name>            # create a preview branch
supabase branches create <name> --persistent   # create a persistent branch
supabase branches delete <name>            # delete a branch
```
