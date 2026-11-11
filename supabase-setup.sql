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
  using ((select auth.jwt() ->> 'email') in ('teacher@harin.example.com','g1@harin.example.com','g2@harin.example.com','g3@harin.example.com','observer@harin.example.com','present@harin.example.com'));

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

-- 교사 계정만 수업 계정 6개의 비밀번호를 바꾸는 함수 (교사 화면 '계정 비밀번호 설정'에서 사용)
create or replace function public.harin_set_password(target text, new_password text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if (select auth.jwt() ->> 'email') is distinct from 'teacher@harin.example.com' then
    raise exception '교사 계정만 비밀번호를 바꿀 수 있습니다' using errcode = '42501';
  end if;
  if target not in ('teacher','g1','g2','g3','observer','present') then
    raise exception '바꿀 수 없는 계정입니다' using errcode = '22023';
  end if;
  if new_password is null or length(new_password) < 6 or length(new_password) > 64 then
    raise exception '비밀번호는 6~64자로 정해 주세요' using errcode = '22023';
  end if;
  update auth.users set encrypted_password = extensions.crypt(new_password, extensions.gen_salt('bf')), updated_at = now()
   where email = target || '@harin.example.com';
  if not found then raise exception '계정을 찾을 수 없습니다' using errcode = 'P0002'; end if;
end; $$;
revoke all on function public.harin_set_password(text, text) from public, anon;
grant execute on function public.harin_set_password(text, text) to authenticated;

-- v1.7.0: PPT 편집 내용 저장 행 'deck', QR 바로 입장 키
alter table public.lesson_state drop constraint if exists lesson_state_id_check;
alter table public.lesson_state add constraint lesson_state_id_check check (id in ('control','g1','g2','g3','deck'));
insert into public.lesson_state (id) values ('deck') on conflict (id) do nothing;
create table if not exists public.harin_qr_keys (id text primary key check (id in ('g1','g2','g3')), key text not null, updated_at timestamptz not null default now());
alter table public.harin_qr_keys enable row level security;
create policy "harin teacher and present read qr keys" on public.harin_qr_keys for select to authenticated
  using ((select auth.jwt() ->> 'email') in ('teacher@harin.example.com','present@harin.example.com'));
-- harin_issue_qr_keys(): 교사만, 모둠 3개 비밀번호를 무작위 키로 바꾸고 harin_qr_keys에 저장
-- harin_set_password(): 직접 바꾸면 해당 모둠의 QR 키 삭제 (전체 정의는 Supabase 마이그레이션 harin_class_deck_and_qr_keys 참고)
