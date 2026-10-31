-- Group rounds: friends play one round together, each player keeps their own
-- score, and everyone's card updates live as scores come in.
--
-- Run once in the Supabase dashboard (SQL Editor > New query > paste > Run).
-- Accounts come from Supabase Auth (Sign in with Google or Apple only).
--
-- Who can do what (row level security):
--   * You only ever see rounds you're playing in, and the players and scores in them.
--   * You only write your own scores.
--   * Rounds are started and joined through the two functions below, never by
--     writing the tables directly, so join codes and seats can't be faked.

-- Tables ----------------------------------------------------------------------

-- One row per account, made automatically when someone first signs in.
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '' check (char_length(display_name) <= 40),
  created_at timestamptz not null default now()
);

-- A round friends play together. The six-letter code is what friends type to join.
create table public.group_rounds (
  id uuid primary key default gen_random_uuid(),
  join_code text not null unique check (join_code ~ '^[A-HJKMNP-Z2-9]{6}$'),
  -- Kept when the host deletes their account, so the others keep their round.
  host_id uuid references auth.users (id) on delete set null,
  course_id text not null check (char_length(course_id) between 1 and 120),
  course_name text not null check (char_length(course_name) between 1 and 120),
  tee text not null default '' check (char_length(tee) <= 40),
  created_at timestamptz not null default now(),
  finished_at timestamptz
);
create index group_rounds_host_recent on public.group_rounds (host_id, created_at);

-- Who's playing. Seats 0 to 3 are the rows of the card, in the order people joined.
create table public.round_players (
  round_id uuid not null references public.group_rounds (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  seat smallint not null check (seat between 0 and 3),
  display_name text not null check (char_length(display_name) between 1 and 40),
  joined_at timestamptz not null default now(),
  primary key (round_id, user_id),
  unique (round_id, seat)
);

-- One row per player per hole. 0 strokes means the score was cleared.
create table public.scores (
  round_id uuid not null,
  user_id uuid not null,
  hole smallint not null check (hole between 1 and 18),
  strokes smallint not null check (strokes between 0 and 20),
  updated_at timestamptz not null default now(),
  primary key (round_id, user_id, hole),
  foreign key (round_id, user_id) references public.round_players (round_id, user_id) on delete cascade
);

-- Helpers ---------------------------------------------------------------------

-- Whether the signed-in person plays in this round. Security definer, so the
-- policies below can ask without tripping over round_players' own policy.
create function public.is_round_player(p_round uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.round_players
    where round_id = p_round and user_id = (select auth.uid())
  );
$$;

-- A name for the card: trimmed, at most 40 letters, "Player" when blank.
create function public.clean_name(p_name text)
returns text
language sql immutable set search_path = ''
as $$
  select left(coalesce(nullif(btrim(p_name), ''), 'Player'), 40);
$$;

-- A fresh six-letter code from letters and digits that can't be mixed up
-- (no I, L, O, 0 or 1), from the random part of a UUID.
create function public.new_join_code()
returns text
language plpgsql volatile set search_path = ''
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_bytes bytea := uuid_send(gen_random_uuid());
  v_code text := '';
begin
  for i in 0..5 loop
    v_code := v_code || substr(v_alphabet, 1 + get_byte(v_bytes, i) % length(v_alphabet), 1);
  end loop;
  return v_code;
end;
$$;

-- Makes the profile row when someone signs in for the first time, with the
-- name Google gives (Apple gives none here; the app fills it in).
create function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    left(coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', ''), 40)
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- What the app calls -------------------------------------------------------------

-- Starts a group round with the caller in seat 0, and returns it with its code.
-- At most 20 a day per person, so a stuck app can't fill the database.
create function public.start_group_round(p_course_id text, p_course_name text, p_tee text, p_display_name text)
returns public.group_rounds
language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_round public.group_rounds;
begin
  if v_user is null then
    raise exception 'Sign in first' using errcode = 'GR003';
  end if;
  if (select count(*) from public.group_rounds
      where host_id = v_user and created_at > now() - interval '1 day') >= 20 then
    raise exception 'Too many group rounds today' using errcode = 'GR004';
  end if;
  for attempt in 1..20 loop
    begin
      insert into public.group_rounds (join_code, host_id, course_id, course_name, tee)
      values (public.new_join_code(), v_user, p_course_id, p_course_name, coalesce(p_tee, ''))
      returning * into v_round;
      exit;
    exception when unique_violation then
      -- That code is taken; try another.
    end;
  end loop;
  if v_round.id is null then
    raise exception 'Could not make a join code' using errcode = 'GR005';
  end if;
  insert into public.round_players (round_id, user_id, seat, display_name)
  values (v_round.id, v_user, 0, public.clean_name(p_display_name));
  return v_round;
end;
$$;

-- Joins the round with this code in the first free seat, and returns it.
-- Codes work for a day, until the host finishes, and for up to four players.
-- Joining a round you're already in just returns it (a new phone, say).
create function public.join_group_round(p_code text, p_display_name text)
returns public.group_rounds
language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_round public.group_rounds;
  v_seat smallint;
begin
  if v_user is null then
    raise exception 'Sign in first' using errcode = 'GR003';
  end if;
  select * into v_round from public.group_rounds
  where join_code = upper(btrim(p_code))
  for update;
  if v_round.id is null or v_round.finished_at is not null
     or v_round.created_at < now() - interval '1 day' then
    raise exception 'No round with that code' using errcode = 'GR001';
  end if;
  if exists (select 1 from public.round_players where round_id = v_round.id and user_id = v_user) then
    return v_round;
  end if;
  select s into v_seat
  from generate_series(0, 3) as s
  where s not in (select seat from public.round_players where round_id = v_round.id)
  order by s
  limit 1;
  if v_seat is null then
    raise exception 'This round is full' using errcode = 'GR002';
  end if;
  insert into public.round_players (round_id, user_id, seat, display_name)
  values (v_round.id, v_user, v_seat, public.clean_name(p_display_name));
  return v_round;
end;
$$;

-- The host finished: the code stops working. Scores stay.
create function public.finish_group_round(p_round uuid)
returns void
language sql security definer set search_path = ''
as $$
  update public.group_rounds
  set finished_at = now()
  where id = p_round and host_id = (select auth.uid()) and finished_at is null;
$$;

-- Deletes the caller's account and everything that's theirs: profile, seats
-- and scores. Rounds they hosted stay for the others. (Apple requires apps
-- with accounts to offer this.)
create function public.delete_my_account()
returns void
language sql security definer set search_path = ''
as $$
  delete from auth.users where id = (select auth.uid());
$$;

-- Access ----------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.group_rounds enable row level security;
alter table public.round_players enable row level security;
alter table public.scores enable row level security;

create policy "See your own profile" on public.profiles
  for select to authenticated using (id = (select auth.uid()));
create policy "Change your own profile" on public.profiles
  for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy "Players see their rounds" on public.group_rounds
  for select to authenticated using (public.is_round_player(id));

create policy "Players see who's playing" on public.round_players
  for select to authenticated using (public.is_round_player(round_id));

create policy "Players see the scores" on public.scores
  for select to authenticated using (public.is_round_player(round_id));
create policy "Players add their own scores" on public.scores
  for insert to authenticated
  with check (user_id = (select auth.uid()) and public.is_round_player(round_id));
create policy "Players change their own scores" on public.scores
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()) and public.is_round_player(round_id));

-- Only what the app needs, and nothing for people who aren't signed in.
revoke all on public.profiles, public.group_rounds, public.round_players, public.scores from anon, authenticated;
grant select, update (display_name) on public.profiles to authenticated;
grant select on public.group_rounds, public.round_players to authenticated;
grant select, insert, update on public.scores to authenticated;

revoke execute on function
  public.is_round_player(uuid), public.clean_name(text), public.new_join_code(), public.handle_new_user(),
  public.start_group_round(text, text, text, text), public.join_group_round(text, text),
  public.finish_group_round(uuid), public.delete_my_account()
from public, anon, authenticated;
grant execute on function
  public.is_round_player(uuid),
  public.start_group_round(text, text, text, text), public.join_group_round(text, text),
  public.finish_group_round(uuid), public.delete_my_account()
to authenticated;

-- Live updates: phones in a round hear new players and scores as they happen.
-- Realtime checks the policies above, so nobody hears another group's round.
alter publication supabase_realtime add table public.scores, public.round_players;
