-- ============================================================
-- SwimFitPro — Supabase Schema
-- Run this in the Supabase SQL editor (Project → SQL Editor → New query)
-- Every table has RLS enabled. Users can only read/write their own rows.
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- EXTENSIONS
-- ────────────────────────────────────────────────────────────
create extension if not exists "uuid-ossp";


-- ────────────────────────────────────────────────────────────
-- 1. PROFILES
-- One row per user. Mirror of S.profile + top-level S settings.
-- Created automatically on first sign-up via auth trigger.
-- ────────────────────────────────────────────────────────────
create table if not exists profiles (
  id              uuid primary key references auth.users(id) on delete cascade,
  name            text,
  club            text,
  dob             date,
  gender          text check (gender in ('male','female','other')),
  primary_stroke  text,
  secondary_stroke text,
  primary_events  text[]    default '{}',
  long_term_goals text[]    default '{}',
  country         text,
  province        text,
  preferred_standard text   default 'provchamp',
  club_logo_url   text,                        -- stored in Supabase Storage, not base64
  use_kg          boolean   default true,
  use_km          boolean   default true,
  app_theme       text      default 'original',
  equipment_mode  text      default 'gym' check (equipment_mode in ('bodyweight','minimal','gym')),
  workout_mode    text      default 'standard' check (workout_mode in ('standard','goal')),
  active_standard text      default 'provchamp',
  swim_phase      text      default 'sprint',
  program_week    integer   default 1,
  program_cycle   integer   default 1,
  season_km_target numeric  default 500,
  swim_km_total   numeric   default 0,
  short_term_goals jsonb    default '[]',
  goal_program    jsonb,                       -- {meetId, goals[], weeksToMeet, startDate, phase}
  off_season      jsonb     default '{"active":false,"nextSeasonStart":"","phases":[]}',
  created_at      timestamptz default now(),
  updated_at      timestamptz default now()
);

alter table profiles enable row level security;

create policy "Users can view own profile"
  on profiles for select using (auth.uid() = id);

create policy "Users can insert own profile"
  on profiles for insert with check (auth.uid() = id);

create policy "Users can update own profile"
  on profiles for update using (auth.uid() = id);


-- ────────────────────────────────────────────────────────────
-- 2. SETTINGS
-- Lightweight key/value overflow for anything not in profiles.
-- Use this for things that change frequently (readiness, sleep).
-- ────────────────────────────────────────────────────────────
create table if not exists settings (
  id              uuid primary key default uuid_generate_v4(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  today_readiness integer   default 3 check (today_readiness between 1 and 5),
  today_sleep     numeric   default 8,
  active_meet_id  text,
  race_mode_dismissed_date text,
  updated_at      timestamptz default now(),
  unique (user_id)
);

alter table settings enable row level security;

create policy "Users can manage own settings"
  on settings for all using (auth.uid() = user_id);


-- ────────────────────────────────────────────────────────────
-- 3. SEASON TEMPLATE
-- S.seasonTemplate — one per user, the weekly plan blueprint.
-- ────────────────────────────────────────────────────────────
create table if not exists season_template (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  start_date  date,
  end_date    date,
  days        jsonb default '{}',   -- {0:[],1:[],2:[],...6:[]} day-of-week → session array
  updated_at  timestamptz default now(),
  unique (user_id)
);

alter table season_template enable row level security;

create policy "Users can manage own season template"
  on season_template for all using (auth.uid() = user_id);


-- ────────────────────────────────────────────────────────────
-- 4. DAY SCHEDULE
-- S.daySchedule — per-day overrides on top of the season template.
-- Key was YYYY-MM-DD string; here it's a proper date column.
-- ────────────────────────────────────────────────────────────
create table if not exists day_schedule (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  day_date    date not null,
  sessions    text[]    default '{}',
  override    boolean   default false,
  removed     boolean   default false,
  updated_at  timestamptz default now(),
  unique (user_id, day_date)
);

alter table day_schedule enable row level security;

create policy "Users can manage own day schedule"
  on day_schedule for all using (auth.uid() = user_id);

create index idx_day_schedule_user_date on day_schedule(user_id, day_date);


-- ────────────────────────────────────────────────────────────
-- 5. DRYLAND HISTORY
-- S.history — one row per completed dryland/OOS session.
-- ────────────────────────────────────────────────────────────
create table if not exists dryland_history (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  session_date  date not null,
  day_type      text,             -- 'upper'|'lower'|'power'|'mobility'|'oos_strength' etc.
  blocks        jsonb default '[]', -- [{name, exercises:[{name,sets,reps,load}]}]
  rpe           integer check (rpe between 1 and 10),
  adapt_note    jsonb,            -- {label, reason, icon, color} if engine adapted the session
  duration_min  integer,
  created_at    timestamptz default now()
);

alter table dryland_history enable row level security;

create policy "Users can manage own dryland history"
  on dryland_history for all using (auth.uid() = user_id);

create index idx_dryland_history_user_date on dryland_history(user_id, session_date);


-- ────────────────────────────────────────────────────────────
-- 6. SESSION RPE LOG
-- S.sessionRPELog — [{date, rpe, load}]
-- ────────────────────────────────────────────────────────────
create table if not exists session_rpe_log (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  session_date  date not null,
  rpe           integer check (rpe between 1 and 10),
  load_mult     numeric,          -- the readiness multiplier at time of session
  created_at    timestamptz default now()
);

alter table session_rpe_log enable row level security;

create policy "Users can manage own RPE log"
  on session_rpe_log for all using (auth.uid() = user_id);

create index idx_rpe_log_user_date on session_rpe_log(user_id, session_date);


-- ────────────────────────────────────────────────────────────
-- 7. CHECKIN HISTORY
-- S.checkinHistory — daily sleep + readiness log.
-- ────────────────────────────────────────────────────────────
create table if not exists checkin_history (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  checkin_date  date not null,
  sleep_hours   numeric,
  readiness     integer check (readiness between 1 and 5),
  created_at    timestamptz default now(),
  unique (user_id, checkin_date)
);

alter table checkin_history enable row level security;

create policy "Users can manage own checkin history"
  on checkin_history for all using (auth.uid() = user_id);

create index idx_checkin_user_date on checkin_history(user_id, checkin_date);


-- ────────────────────────────────────────────────────────────
-- 8. POOL LOG
-- S.poolLog — [{date, feel, timedSwim, timedTime, distKm, notes}]
-- ────────────────────────────────────────────────────────────
create table if not exists pool_log (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  session_date  date not null,
  feel          integer check (feel between 1 and 5),
  timed_swim    boolean   default false,
  timed_time    text,             -- stored as mm:ss.xx string
  dist_km       numeric,
  notes         text,
  created_at    timestamptz default now()
);

alter table pool_log enable row level security;

create policy "Users can manage own pool log"
  on pool_log for all using (auth.uid() = user_id);

create index idx_pool_log_user_date on pool_log(user_id, session_date);


-- ────────────────────────────────────────────────────────────
-- 9. SWIM KM LOG
-- S.swimKmLog — [{date, km}]
-- ────────────────────────────────────────────────────────────
create table if not exists swim_km_log (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  log_date      date not null,
  km            numeric not null,
  created_at    timestamptz default now()
);

alter table swim_km_log enable row level security;

create policy "Users can manage own swim km log"
  on swim_km_log for all using (auth.uid() = user_id);

create index idx_swim_km_user_date on swim_km_log(user_id, log_date);


-- ────────────────────────────────────────────────────────────
-- 10. TIME HISTORY
-- S.timeHistory — {event: [{pool, time, date, note}]}
-- Flattened to one row per entry for proper querying.
-- ────────────────────────────────────────────────────────────
create table if not exists time_history (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  event         text not null,    -- '100 Free', '200 Fly' etc.
  pool          text not null check (pool in ('lcm','scm')),
  time_str      text not null,    -- '1:02.34'
  time_seconds  numeric,          -- computed on insert for sorting/comparison
  swim_date     date,
  note          text,
  created_at    timestamptz default now()
);

alter table time_history enable row level security;

create policy "Users can manage own time history"
  on time_history for all using (auth.uid() = user_id);

create index idx_time_history_user_event on time_history(user_id, event, pool);


-- ────────────────────────────────────────────────────────────
-- 11. MEETS
-- S.meets — [{id, name, date, endDate, pool, location}]
-- ────────────────────────────────────────────────────────────
create table if not exists meets (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  client_id     text,             -- original localStorage id, for migration mapping
  name          text not null,
  meet_date     date not null,
  end_date      date,
  pool          text check (pool in ('lcm','scm')),
  location      text,
  created_at    timestamptz default now()
);

alter table meets enable row level security;

create policy "Users can manage own meets"
  on meets for all using (auth.uid() = user_id);

create index idx_meets_user_date on meets(user_id, meet_date);


-- ────────────────────────────────────────────────────────────
-- 12. MEET RACES
-- S.meetRaces — [{id, meetId, event, pool, seedTime, day, session}]
-- ────────────────────────────────────────────────────────────
create table if not exists meet_races (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  meet_id       uuid references meets(id) on delete cascade,
  client_id     text,             -- original localStorage id
  event         text not null,
  pool          text check (pool in ('lcm','scm')),
  seed_time     text,
  race_day      integer,          -- 1-based day number within meet
  session       text check (session in ('prelims','finals','timed_final')),
  created_at    timestamptz default now()
);

alter table meet_races enable row level security;

create policy "Users can manage own meet races"
  on meet_races for all using (auth.uid() = user_id);

create index idx_meet_races_user_meet on meet_races(user_id, meet_id);


-- ────────────────────────────────────────────────────────────
-- 13. MEET RACE LOG
-- S.meetRaceLog — [{id, meetId, raceId, time, coachTags, coachNotes, ts}]
-- ────────────────────────────────────────────────────────────
create table if not exists meet_race_log (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  meet_id       uuid references meets(id) on delete cascade,
  race_id       uuid references meet_races(id) on delete cascade,
  time_str      text,
  time_seconds  numeric,
  coach_tags    text[]    default '{}',
  coach_notes   text,
  logged_at     timestamptz default now()
);

alter table meet_race_log enable row level security;

create policy "Users can manage own race log"
  on meet_race_log for all using (auth.uid() = user_id);

create index idx_race_log_user_meet on meet_race_log(user_id, meet_id);


-- ────────────────────────────────────────────────────────────
-- 14. BODY STATS
-- S.bodyStats + S.weightTrendLog
-- ────────────────────────────────────────────────────────────
create table if not exists body_stats (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  weight_kg     numeric,
  height_cm     numeric,
  body_fat_pct  numeric,
  updated_at    timestamptz default now(),
  unique (user_id)
);

alter table body_stats enable row level security;

create policy "Users can manage own body stats"
  on body_stats for all using (auth.uid() = user_id);

create table if not exists weight_trend_log (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  log_date      date not null,
  weight_kg     numeric not null,
  created_at    timestamptz default now()
);

alter table weight_trend_log enable row level security;

create policy "Users can manage own weight trend"
  on weight_trend_log for all using (auth.uid() = user_id);

create index idx_weight_trend_user_date on weight_trend_log(user_id, log_date);


-- ────────────────────────────────────────────────────────────
-- 15. ONE RM LOG
-- S.oneRM — {exercise: weight_kg} + S.oneRMDate
-- ────────────────────────────────────────────────────────────
create table if not exists one_rm (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  exercise      text not null,
  weight_kg     numeric not null,
  tested_date   date,
  created_at    timestamptz default now(),
  unique (user_id, exercise)
);

alter table one_rm enable row level security;

create policy "Users can manage own 1RM"
  on one_rm for all using (auth.uid() = user_id);


-- ────────────────────────────────────────────────────────────
-- 16. MOBILITY LOG
-- S.mobilityLog — [YYYY-MM-DD]
-- ────────────────────────────────────────────────────────────
create table if not exists mobility_log (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  log_date      date not null,
  created_at    timestamptz default now(),
  unique (user_id, log_date)
);

alter table mobility_log enable row level security;

create policy "Users can manage own mobility log"
  on mobility_log for all using (auth.uid() = user_id);


-- ────────────────────────────────────────────────────────────
-- 17. HYDRATION LOG
-- S.hydrationLog — {YYYY-MM-DD: count}
-- ────────────────────────────────────────────────────────────
create table if not exists hydration_log (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  log_date      date not null,
  glass_count   integer   default 0,
  updated_at    timestamptz default now(),
  unique (user_id, log_date)
);

alter table hydration_log enable row level security;

create policy "Users can manage own hydration log"
  on hydration_log for all using (auth.uid() = user_id);


-- ────────────────────────────────────────────────────────────
-- 18. MEAL COMPLIANCE
-- S.mealCompliance — {YYYY-MM-DD: {pre, intra, post}}
-- ────────────────────────────────────────────────────────────
create table if not exists meal_compliance (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  log_date      date not null,
  pre           boolean default false,
  intra         boolean default false,
  post          boolean default false,
  updated_at    timestamptz default now(),
  unique (user_id, log_date)
);

alter table meal_compliance enable row level security;

create policy "Users can manage own meal compliance"
  on meal_compliance for all using (auth.uid() = user_id);


-- ────────────────────────────────────────────────────────────
-- 19. CUSTOM TARGET MEETS
-- S.customTargetMeets — [{id, meetId, name, times:{event:{lcm,scm}}}]
-- ────────────────────────────────────────────────────────────
create table if not exists custom_target_meets (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  meet_id       uuid references meets(id) on delete set null,
  name          text not null,
  target_times  jsonb default '{}',   -- {event: {lcm: '1:02.34', scm: '1:01.00'}}
  created_at    timestamptz default now()
);

alter table custom_target_meets enable row level security;

create policy "Users can manage own target meets"
  on custom_target_meets for all using (auth.uid() = user_id);


-- ────────────────────────────────────────────────────────────
-- 20. SUBSCRIPTIONS
-- Tracks Stripe subscription state per user.
-- Updated by Stripe webhook → Supabase edge function.
-- ────────────────────────────────────────────────────────────
create table if not exists subscriptions (
  id                  uuid primary key default uuid_generate_v4(),
  user_id             uuid not null references auth.users(id) on delete cascade,
  stripe_customer_id  text,
  stripe_sub_id       text,
  plan                text default 'free' check (plan in ('free','pro','annual')),
  status              text default 'trialing' check (status in ('trialing','active','past_due','canceled','expired')),
  trial_end           timestamptz,
  current_period_end  timestamptz,
  created_at          timestamptz default now(),
  updated_at          timestamptz default now(),
  unique (user_id)
);

alter table subscriptions enable row level security;

create policy "Users can view own subscription"
  on subscriptions for select using (auth.uid() = user_id);

-- Note: subscriptions are written by the Stripe webhook edge function
-- using the service role key — not by the client directly.


-- ────────────────────────────────────────────────────────────
-- TRIGGER: auto-create profile + settings + subscription rows on signup
-- ────────────────────────────────────────────────────────────
create or replace function handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into profiles (id) values (new.id);
  insert into settings (user_id) values (new.id);
  insert into subscriptions (user_id, plan, status, trial_end)
    values (new.id, 'free', 'trialing', now() + interval '30 days');
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure handle_new_user();


-- ────────────────────────────────────────────────────────────
-- TRIGGER: keep profiles.updated_at current
-- ────────────────────────────────────────────────────────────
create or replace function update_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_updated_at
  before update on profiles
  for each row execute procedure update_updated_at();

create trigger settings_updated_at
  before update on settings
  for each row execute procedure update_updated_at();

create trigger body_stats_updated_at
  before update on body_stats
  for each row execute procedure update_updated_at();

create trigger subscriptions_updated_at
  before update on subscriptions
  for each row execute procedure update_updated_at();
