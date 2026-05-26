 alter table public.rewards
    add column description text;

  update public.rewards
    set description = 'A perfect way to use your loyalty 
  points';