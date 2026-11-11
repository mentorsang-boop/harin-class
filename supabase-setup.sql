-- 하린의 첫 직장 한 달 · 수업도구 DB 설정 (school-promo-booking 프로젝트에 적용됨)
-- 행 4개: control(교사 타이머·해설), g1, g2, g3(모둠 기록)
-- 수업 계정 4개(teacher/g1/g2/g3 @harin.example.com)만 읽고 쓸 수 있음

create table if not exists public.lesson_state (
  id text primary key check (id in ('control','g1','g2','g3')),
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.lesson_state enable row level security;

create policy "harin class accounts read" on public.lesson_state
  for select to authenticated
  using ((select auth.jwt() ->> 'email') in ('teacher@harin.example.com','g1@harin.example.com','g2@harin.example.com','g3@harin.example.com'));

create policy "harin teacher writes all" on public.lesson_state
  for update to authenticated
  using ((select auth.jwt() ->> 'email') = 'teacher@harin.example.com')
  with check ((select auth.jwt() ->> 'email') = 'teacher@harin.example.com');

create policy "harin group writes own row" on public.lesson_state
  for update to authenticated
  using ((select auth.jwt() ->> 'email') = id || '@harin.example.com')
  with check ((select auth.jwt() ->> 'email') = id || '@harin.example.com');

revoke all on public.lesson_state from anon;
grant select, update on public.lesson_state to authenticated;

insert into public.lesson_state (id) values ('control'),('g1'),('g2'),('g3') on conflict (id) do nothing;

do $$ begin
  alter publication supabase_realtime add table public.lesson_state;
exception when duplicate_object then null; end $$;

-- 수업 계정은 Supabase 대시보드 > Authentication > Add user 로 만들거나,
-- 비밀번호를 바꿀 때도 대시보드에서 해당 사용자의 비밀번호를 재설정하세요.
