-- ============================================
-- PINDOR 시드 데이터 (골프, 사당역 중심)
-- ============================================

-- 사당역 좌표: 37.4764, 126.9816
-- 주변 좌표 ±0.005 범위로 분산

BEGIN;

-- ──────────────────────────────────────
-- 1. 기존 유저 본인인증 처리
-- ──────────────────────────────────────
UPDATE users SET
  is_verified = true,
  verified_at = NOW(),
  gender = COALESCE(gender, 'MALE'),
  birth_date = COALESCE(birth_date, '1992-01-15'),
  phone_number = COALESCE(phone_number, '01000000001'),
  real_name = COALESCE(real_name, nickname)
WHERE status = 'ACTIVE';

-- ──────────────────────────────────────
-- 2. 가짜 유저 20명 생성
-- ──────────────────────────────────────
INSERT INTO users (id, email, nickname, profile_image_url, gender, birth_date, phone_number, real_name, is_verified, verified_at, status, created_at, updated_at, last_login_at)
VALUES
  ('a0000001-0000-4000-8000-000000000001', 'seed01@test.com', '버디킹', NULL, 'MALE',   '1990-03-15', '01011110001', '김태현', true, NOW(), 'ACTIVE', NOW() - interval '30 days', NOW(), NOW() - interval '1 hour'),
  ('a0000001-0000-4000-8000-000000000002', 'seed02@test.com', '이글헌터', NULL, 'MALE',   '1988-07-22', '01011110002', '박준호', true, NOW(), 'ACTIVE', NOW() - interval '28 days', NOW(), NOW() - interval '2 hours'),
  ('a0000001-0000-4000-8000-000000000003', 'seed03@test.com', '페어웨이퀸', NULL, 'FEMALE', '1993-11-08', '01011110003', '이서연', true, NOW(), 'ACTIVE', NOW() - interval '27 days', NOW(), NOW() - interval '30 minutes'),
  ('a0000001-0000-4000-8000-000000000004', 'seed04@test.com', '드라이버황제', NULL, 'MALE',   '1985-01-30', '01011110004', '정민수', true, NOW(), 'ACTIVE', NOW() - interval '25 days', NOW(), NOW() - interval '3 hours'),
  ('a0000001-0000-4000-8000-000000000005', 'seed05@test.com', '퍼팅마스터', NULL, 'MALE',   '1991-05-17', '01011110005', '최영진', true, NOW(), 'ACTIVE', NOW() - interval '24 days', NOW(), NOW() - interval '45 minutes'),
  ('a0000001-0000-4000-8000-000000000006', 'seed06@test.com', '그린위의요정', NULL, 'FEMALE', '1995-09-03', '01011110006', '한지민', true, NOW(), 'ACTIVE', NOW() - interval '22 days', NOW(), NOW() - interval '1 hour'),
  ('a0000001-0000-4000-8000-000000000007', 'seed07@test.com', '아이언맨골프', NULL, 'MALE',   '1987-12-11', '01011110007', '강도윤', true, NOW(), 'ACTIVE', NOW() - interval '21 days', NOW(), NOW() - interval '5 hours'),
  ('a0000001-0000-4000-8000-000000000008', 'seed08@test.com', '홀인원전설', NULL, 'MALE',   '1992-06-25', '01011110008', '윤성호', true, NOW(), 'ACTIVE', NOW() - interval '20 days', NOW(), NOW() - interval '2 hours'),
  ('a0000001-0000-4000-8000-000000000009', 'seed09@test.com', '스윙요정', NULL, 'FEMALE', '1994-02-14', '01011110009', '김하은', true, NOW(), 'ACTIVE', NOW() - interval '19 days', NOW(), NOW() - interval '20 minutes'),
  ('a0000001-0000-4000-8000-000000000010', 'seed10@test.com', '캐디출신프로', NULL, 'MALE',   '1986-08-07', '01011110010', '임재혁', true, NOW(), 'ACTIVE', NOW() - interval '18 days', NOW(), NOW() - interval '4 hours'),
  ('a0000001-0000-4000-8000-000000000011', 'seed11@test.com', '보기플레이어', NULL, 'MALE',   '1996-04-19', '01011110011', '송민재', true, NOW(), 'ACTIVE', NOW() - interval '17 days', NOW(), NOW() - interval '1 hour'),
  ('a0000001-0000-4000-8000-000000000012', 'seed12@test.com', '나이스샷', NULL, 'FEMALE', '1991-10-28', '01011110012', '오수빈', true, NOW(), 'ACTIVE', NOW() - interval '16 days', NOW(), NOW() - interval '6 hours'),
  ('a0000001-0000-4000-8000-000000000013', 'seed13@test.com', '파워드라이버', NULL, 'MALE',   '1989-03-02', '01011110013', '배현우', true, NOW(), 'ACTIVE', NOW() - interval '15 days', NOW(), NOW() - interval '3 hours'),
  ('a0000001-0000-4000-8000-000000000014', 'seed14@test.com', '그늘진숲속', NULL, 'MALE',   '1993-07-16', '01011110014', '류동현', true, NOW(), 'ACTIVE', NOW() - interval '14 days', NOW(), NOW() - interval '50 minutes'),
  ('a0000001-0000-4000-8000-000000000015', 'seed15@test.com', '투온달인', NULL, 'FEMALE', '1990-12-05', '01011110015', '신예진', true, NOW(), 'ACTIVE', NOW() - interval '13 days', NOW(), NOW() - interval '2 hours'),
  ('a0000001-0000-4000-8000-000000000016', 'seed16@test.com', '벙커탈출왕', NULL, 'MALE',   '1988-09-21', '01011110016', '조상현', true, NOW(), 'ACTIVE', NOW() - interval '12 days', NOW(), NOW() - interval '7 hours'),
  ('a0000001-0000-4000-8000-000000000017', 'seed17@test.com', '주말골퍼', NULL, 'MALE',   '1994-01-09', '01011110017', '문준서', true, NOW(), 'ACTIVE', NOW() - interval '10 days', NOW(), NOW() - interval '1 hour'),
  ('a0000001-0000-4000-8000-000000000018', 'seed18@test.com', '스크린골프장인', NULL, 'MALE',   '1997-06-14', '01011110018', '장우진', true, NOW(), 'ACTIVE', NOW() - interval '8 days', NOW(), NOW() - interval '30 minutes'),
  ('a0000001-0000-4000-8000-000000000019', 'seed19@test.com', '라운딩메이트', NULL, 'FEMALE', '1992-11-30', '01011110019', '권나영', true, NOW(), 'ACTIVE', NOW() - interval '6 days', NOW(), NOW() - interval '4 hours'),
  ('a0000001-0000-4000-8000-000000000020', 'seed20@test.com', '파3전문가', NULL, 'MALE',   '1990-05-08', '01011110020', '황석진', true, NOW(), 'ACTIVE', NOW() - interval '5 days', NOW(), NOW() - interval '15 minutes')
ON CONFLICT (id) DO NOTHING;

-- ──────────────────────────────────────
-- 3. 유저 위치 설정 (사당역 주변)
-- ──────────────────────────────────────

-- 기존 유저 위치
INSERT INTO user_locations (id, user_id, home_point, home_address, match_radius_km, updated_at)
SELECT gen_random_uuid(), id,
  ST_SetSRID(ST_MakePoint(126.9816 + (random()-0.5)*0.008, 37.4764 + (random()-0.5)*0.006), 4326),
  '서울 동작구 사당동', 10, NOW()
FROM users
WHERE status = 'ACTIVE'
  AND id NOT IN (SELECT user_id FROM user_locations)
ON CONFLICT DO NOTHING;

-- ──────────────────────────────────────
-- 4. 골프 스포츠 프로필 (다양한 점수/티어)
-- ──────────────────────────────────────

-- 티어별 점수 분포:
-- GRANDMASTER: 1800+, MASTER: 1650-1799, PLATINUM: 1500-1649
-- GOLD: 1300-1499, SILVER: 1100-1299, BRONZE: 900-1099, IRON: 100-899

INSERT INTO sports_profiles (
  id, user_id, sport_type, display_name, initial_score, current_score, display_score,
  tier, is_verified, games_played, wins, losses, draws, win_streak, loss_streak,
  no_show_count, casual_score, casual_win, casual_loss, extra_data, is_active,
  glicko_rating, glicko_rd, glicko_volatility, is_placement,
  created_at, updated_at
) VALUES
  -- GRANDMASTER (1명)
  (gen_random_uuid(), 'a0000001-0000-4000-8000-000000000001', 'GOLF', '버디킹', 1000, 1850, 1850, 'GRANDMASTER', false, 42, 30, 10, 2, 5, 0, 0, 1000, 0, 0, '{}', true, 1850, 80, 0.06, false, NOW() - interval '30 days', NOW()),
  -- MASTER (2명)
  (gen_random_uuid(), 'a0000001-0000-4000-8000-000000000002', 'GOLF', '이글헌터', 1000, 1720, 1720, 'MASTER', false, 38, 26, 10, 2, 3, 0, 0, 1000, 0, 0, '{}', true, 1720, 85, 0.06, false, NOW() - interval '28 days', NOW()),
  (gen_random_uuid(), 'a0000001-0000-4000-8000-000000000003', 'GOLF', '페어웨이퀸', 1000, 1680, 1680, 'MASTER', false, 35, 24, 9, 2, 2, 0, 0, 1000, 0, 0, '{}', true, 1680, 88, 0.06, false, NOW() - interval '27 days', NOW()),
  -- PLATINUM (3명)
  (gen_random_uuid(), 'a0000001-0000-4000-8000-000000000004', 'GOLF', '드라이버황제', 1000, 1620, 1620, 'PLATINUM', false, 32, 21, 9, 2, 4, 0, 0, 1000, 0, 0, '{}', true, 1620, 90, 0.06, false, NOW() - interval '25 days', NOW()),
  (gen_random_uuid(), 'a0000001-0000-4000-8000-000000000005', 'GOLF', '퍼팅마스터', 1000, 1560, 1560, 'PLATINUM', false, 30, 20, 8, 2, 1, 0, 0, 1000, 0, 0, '{}', true, 1560, 92, 0.06, false, NOW() - interval '24 days', NOW()),
  (gen_random_uuid(), 'a0000001-0000-4000-8000-000000000006', 'GOLF', '그린위의요정', 1000, 1510, 1510, 'PLATINUM', false, 28, 18, 8, 2, 0, 1, 0, 1000, 0, 0, '{}', true, 1510, 95, 0.06, false, NOW() - interval '22 days', NOW()),
  -- GOLD (4명)
  (gen_random_uuid(), 'a0000001-0000-4000-8000-000000000007', 'GOLF', '아이언맨골프', 1000, 1450, 1450, 'GOLD', false, 25, 16, 7, 2, 2, 0, 0, 1000, 0, 0, '{}', true, 1450, 100, 0.06, false, NOW() - interval '21 days', NOW()),
  (gen_random_uuid(), 'a0000001-0000-4000-8000-000000000008', 'GOLF', '홀인원전설', 1000, 1400, 1400, 'GOLD', false, 24, 15, 7, 2, 1, 0, 0, 1000, 0, 0, '{}', true, 1400, 102, 0.06, false, NOW() - interval '20 days', NOW()),
  (gen_random_uuid(), 'a0000001-0000-4000-8000-000000000009', 'GOLF', '스윙요정', 1000, 1360, 1360, 'GOLD', false, 22, 14, 6, 2, 3, 0, 0, 1000, 0, 0, '{}', true, 1360, 105, 0.06, false, NOW() - interval '19 days', NOW()),
  (gen_random_uuid(), 'a0000001-0000-4000-8000-000000000010', 'GOLF', '캐디출신프로', 1000, 1310, 1310, 'GOLD', false, 20, 13, 5, 2, 0, 2, 0, 1000, 0, 0, '{}', true, 1310, 108, 0.06, false, NOW() - interval '18 days', NOW()),
  -- SILVER (4명)
  (gen_random_uuid(), 'a0000001-0000-4000-8000-000000000011', 'GOLF', '보기플레이어', 1000, 1260, 1260, 'SILVER', false, 18, 11, 5, 2, 1, 0, 0, 1000, 0, 0, '{}', true, 1260, 112, 0.06, false, NOW() - interval '17 days', NOW()),
  (gen_random_uuid(), 'a0000001-0000-4000-8000-000000000012', 'GOLF', '나이스샷', 1000, 1200, 1200, 'SILVER', false, 16, 10, 5, 1, 2, 0, 0, 1000, 0, 0, '{}', true, 1200, 115, 0.06, false, NOW() - interval '16 days', NOW()),
  (gen_random_uuid(), 'a0000001-0000-4000-8000-000000000013', 'GOLF', '파워드라이버', 1000, 1150, 1150, 'SILVER', false, 15, 9, 5, 1, 0, 1, 0, 1000, 0, 0, '{}', true, 1150, 118, 0.06, false, NOW() - interval '15 days', NOW()),
  (gen_random_uuid(), 'a0000001-0000-4000-8000-000000000014', 'GOLF', '그늘진숲속', 1000, 1110, 1110, 'SILVER', false, 14, 8, 5, 1, 1, 0, 0, 1000, 0, 0, '{}', true, 1110, 120, 0.06, false, NOW() - interval '14 days', NOW()),
  -- BRONZE (4명)
  (gen_random_uuid(), 'a0000001-0000-4000-8000-000000000015', 'GOLF', '투온달인', 1000, 1050, 1050, 'BRONZE', false, 12, 7, 4, 1, 0, 1, 0, 1000, 0, 0, '{}', true, 1050, 125, 0.06, false, NOW() - interval '13 days', NOW()),
  (gen_random_uuid(), 'a0000001-0000-4000-8000-000000000016', 'GOLF', '벙커탈출왕', 1000, 1000, 1000, 'BRONZE', false, 11, 6, 4, 1, 1, 0, 0, 1000, 0, 0, '{}', true, 1000, 128, 0.06, false, NOW() - interval '12 days', NOW()),
  (gen_random_uuid(), 'a0000001-0000-4000-8000-000000000017', 'GOLF', '주말골퍼', 1000, 960, 960, 'BRONZE', false, 10, 5, 4, 1, 0, 2, 0, 1000, 0, 0, '{}', true, 960, 132, 0.06, false, NOW() - interval '10 days', NOW()),
  (gen_random_uuid(), 'a0000001-0000-4000-8000-000000000018', 'GOLF', '스크린골프장인', 1000, 920, 920, 'BRONZE', false, 10, 5, 4, 1, 2, 0, 0, 1000, 0, 0, '{}', true, 920, 135, 0.06, false, NOW() - interval '8 days', NOW()),
  -- IRON (2명)
  (gen_random_uuid(), 'a0000001-0000-4000-8000-000000000019', 'GOLF', '라운딩메이트', 1000, 850, 850, 'IRON', false, 8, 3, 4, 1, 0, 1, 0, 1000, 0, 0, '{}', true, 850, 145, 0.06, false, NOW() - interval '6 days', NOW()),
  (gen_random_uuid(), 'a0000001-0000-4000-8000-000000000020', 'GOLF', '파3전문가', 1000, 780, 780, 'IRON', false, 6, 2, 3, 1, 0, 2, 0, 1000, 0, 0, '{}', true, 780, 155, 0.06, false, NOW() - interval '5 days', NOW())
ON CONFLICT DO NOTHING;

-- 기존 유저(질풍제왕) 프로필 점수 업데이트 (배치 안 된 상태면 적당한 점수 부여)
UPDATE sports_profiles SET
  current_score = 1280, display_score = 1280, tier = 'SILVER',
  games_played = 15, wins = 9, losses = 5, draws = 1,
  is_placement = false, glicko_rating = 1280, glicko_rd = 110
WHERE user_id = '9c0befe9-e2ac-4950-81c5-227068a931de' AND sport_type = 'GOLF';

-- yongju Park에 골프 프로필 생성 (없으면)
INSERT INTO sports_profiles (
  id, user_id, sport_type, display_name, initial_score, current_score, display_score,
  tier, is_verified, games_played, wins, losses, draws, win_streak, loss_streak,
  no_show_count, casual_score, casual_win, casual_loss, extra_data, is_active,
  glicko_rating, glicko_rd, glicko_volatility, is_placement,
  created_at, updated_at
)
SELECT gen_random_uuid(), '5749fc4a-6afb-4926-9566-a00f551e02da', 'GOLF', 'yongju Park',
  1000, 1380, 1380, 'GOLD', false, 20, 13, 5, 2, 1, 0, 0, 1000, 0, 0, '{}', true,
  1380, 100, 0.06, false, NOW() - interval '20 days', NOW()
WHERE NOT EXISTS (
  SELECT 1 FROM sports_profiles WHERE user_id = '5749fc4a-6afb-4926-9566-a00f551e02da' AND sport_type = 'GOLF'
);

-- ──────────────────────────────────────
-- 5. 매칭 + 채팅방 + 게임 결과 생성 (완료된 매칭 8개)
-- ──────────────────────────────────────

-- 매칭 데이터를 생성하려면 requester_profile_id, opponent_profile_id 필요
-- DO 블록으로 처리

DO $$
DECLARE
  profiles uuid[];
  user_ids uuid[];
  p_count int;
  i int;
  j int;
  m_id uuid;
  cr_id uuid;
  g_id uuid;
  winner_idx int;
  req_score int;
  opp_score int;
  match_date date;
  venue text;
  venues text[] := ARRAY[
    '사당 골프존', '남성역 스크린골프', '이수 골프연습장',
    '방배 골프아카데미', '서초 그린골프', '동작 골프파크',
    '사당동 프로골프', '남현동 골프레인지'
  ];
BEGIN
  -- 프로필 ID 배열 수집 (GOLF만)
  SELECT array_agg(sp.id ORDER BY sp.current_score DESC),
         array_agg(sp.user_id ORDER BY sp.current_score DESC)
  INTO profiles, user_ids
  FROM sports_profiles sp
  WHERE sp.sport_type = 'GOLF' AND sp.is_active = true;

  p_count := array_length(profiles, 1);

  IF p_count < 2 THEN
    RAISE NOTICE 'Not enough profiles to create matches';
    RETURN;
  END IF;

  -- 완료된 매칭 10개 생성
  FOR i IN 1..10 LOOP
    -- 랜덤 페어링 (인접한 랭크끼리)
    j := 1 + (i * 2 - 1) % (p_count - 1);
    IF j >= p_count THEN j := p_count - 1; END IF;

    m_id := gen_random_uuid();
    cr_id := gen_random_uuid();
    g_id := gen_random_uuid();
    match_date := CURRENT_DATE - (20 - i * 2);
    venue := venues[1 + (i - 1) % array_length(venues, 1)];

    -- 승자 랜덤 (약간 상위 랭크 유리)
    IF random() < 0.6 THEN winner_idx := j; ELSE winner_idx := j + 1; END IF;

    -- 골프 스코어 (72 기준 ±15)
    req_score := 72 + floor(random() * 20 - 10)::int;
    opp_score := 72 + floor(random() * 20 - 10)::int;
    -- 승자 스코어가 더 낮게 (골프는 낮을수록 좋음)
    IF winner_idx = j AND req_score > opp_score THEN
      req_score := opp_score - floor(random() * 5 + 1)::int;
    ELSIF winner_idx = j + 1 AND opp_score > req_score THEN
      opp_score := req_score - floor(random() * 5 + 1)::int;
    END IF;

    -- 채팅방 생성
    INSERT INTO chat_rooms (id, match_id, room_type, status, last_message_at, created_at)
    VALUES (cr_id, m_id, 'MATCH', 'ARCHIVED', match_date + interval '18 hours', match_date - interval '1 day');

    -- 매칭 생성
    INSERT INTO matches (id, requester_profile_id, opponent_profile_id, sport_type,
      scheduled_date, venue_name, status, chat_room_id, confirmed_at, completed_at,
      created_at, updated_at, desired_date)
    VALUES (m_id, profiles[j], profiles[j+1], 'GOLF',
      match_date, venue, 'COMPLETED', cr_id,
      match_date - interval '12 hours', match_date + interval '20 hours',
      match_date - interval '2 days', match_date + interval '20 hours', match_date);

    -- 게임 결과 생성
    INSERT INTO games (id, match_id, sport_type, venue_name, played_at,
      score_data, result_status, winner_profile_id,
      requester_score, opponent_score,
      requester_claimed_result, opponent_claimed_result,
      verified_at, created_at, updated_at, proof_image_urls)
    VALUES (g_id, m_id, 'GOLF', venue, match_date + interval '16 hours',
      jsonb_build_object('requester', req_score, 'opponent', opp_score),
      'VERIFIED', profiles[winner_idx],
      req_score, opp_score,
      CASE WHEN winner_idx = j THEN 'WIN' ELSE 'LOSS' END,
      CASE WHEN winner_idx = j + 1 THEN 'WIN' ELSE 'LOSS' END,
      match_date + interval '19 hours',
      match_date + interval '17 hours', match_date + interval '19 hours',
      '{}');

    -- 채팅 메시지 몇 개 삽입
    INSERT INTO messages (id, chat_room_id, sender_id, message_type, content, created_at)
    VALUES
      (gen_random_uuid(), cr_id, user_ids[j], 'TEXT', '안녕하세요! 매칭 잡혔네요 ⛳', match_date - interval '1 day' + interval '10 hours'),
      (gen_random_uuid(), cr_id, user_ids[j+1], 'TEXT', '반갑습니다! 골프 좋아하시나봐요', match_date - interval '1 day' + interval '10 hours 5 minutes'),
      (gen_random_uuid(), cr_id, user_ids[j], 'TEXT', venue || '에서 만날까요?', match_date - interval '1 day' + interval '10 hours 15 minutes'),
      (gen_random_uuid(), cr_id, user_ids[j+1], 'TEXT', '좋습니다! ' || to_char(match_date, 'MM월 DD일') || ' 오후 2시 어떠세요?', match_date - interval '1 day' + interval '11 hours'),
      (gen_random_uuid(), cr_id, user_ids[j], 'TEXT', '딱 좋네요! 그때 뵙겠습니다 👍', match_date - interval '1 day' + interval '11 hours 10 minutes'),
      (gen_random_uuid(), cr_id, user_ids[j+1], 'TEXT', '오늘 라운딩 즐거웠습니다! 다음에 또 하죠', match_date + interval '18 hours');
  END LOOP;

  -- 진행 중 매칭 2개 (CHAT 상태)
  FOR i IN 1..2 LOOP
    j := 3 + i * 4;
    IF j >= p_count THEN j := p_count - 2; END IF;

    m_id := gen_random_uuid();
    cr_id := gen_random_uuid();
    match_date := CURRENT_DATE + i;
    venue := venues[i + 3];

    INSERT INTO chat_rooms (id, match_id, room_type, status, last_message_at, created_at)
    VALUES (cr_id, m_id, 'MATCH', 'ACTIVE', NOW() - interval '2 hours', NOW() - interval '1 day');

    INSERT INTO matches (id, requester_profile_id, opponent_profile_id, sport_type,
      scheduled_date, venue_name, status, chat_room_id,
      created_at, updated_at, desired_date)
    VALUES (m_id, profiles[j], profiles[j+1], 'GOLF',
      match_date, venue, 'CHAT', cr_id,
      NOW() - interval '1 day', NOW(), match_date);

    INSERT INTO messages (id, chat_room_id, sender_id, message_type, content, created_at)
    VALUES
      (gen_random_uuid(), cr_id, user_ids[j], 'TEXT', '안녕하세요! 골프 한 판 하시죠', NOW() - interval '23 hours'),
      (gen_random_uuid(), cr_id, user_ids[j+1], 'TEXT', '좋죠! 어디서 만날까요?', NOW() - interval '22 hours'),
      (gen_random_uuid(), cr_id, user_ids[j], 'TEXT', venue || ' 어떨까요? ' || to_char(match_date, 'MM월 DD일') || ' 오후에', NOW() - interval '4 hours'),
      (gen_random_uuid(), cr_id, user_ids[j+1], 'TEXT', '완벽합니다! 2시에 만나요 🏌️', NOW() - interval '2 hours');
  END LOOP;

  -- CONFIRMED 매칭 1개
  m_id := gen_random_uuid();
  cr_id := gen_random_uuid();
  match_date := CURRENT_DATE + 1;

  INSERT INTO chat_rooms (id, match_id, room_type, status, last_message_at, created_at)
  VALUES (cr_id, m_id, 'MATCH', 'ACTIVE', NOW() - interval '1 hour', NOW() - interval '2 days');

  INSERT INTO matches (id, requester_profile_id, opponent_profile_id, sport_type,
    scheduled_date, venue_name, status, chat_room_id, confirmed_at,
    created_at, updated_at, desired_date)
  VALUES (m_id, profiles[1], profiles[4], 'GOLF',
    match_date, '사당 골프존', 'CONFIRMED', cr_id, NOW() - interval '1 hour',
    NOW() - interval '2 days', NOW(), match_date);

  INSERT INTO messages (id, chat_room_id, sender_id, message_type, content, created_at)
  VALUES
    (gen_random_uuid(), cr_id, user_ids[1], 'TEXT', '내일 라운딩 확정이죠?', NOW() - interval '3 hours'),
    (gen_random_uuid(), cr_id, user_ids[4], 'TEXT', '네! 사당 골프존 2시에 뵙겠습니다', NOW() - interval '2 hours'),
    (gen_random_uuid(), cr_id, user_ids[1], 'TEXT', '좋습니다! 내일 뵙겠습니다 🤝', NOW() - interval '1 hour');

END $$;

-- ──────────────────────────────────────
-- 6. 랭킹 엔트리 생성 (사당역 핀 기준)
-- ──────────────────────────────────────
DELETE FROM ranking_entries WHERE sport_type = 'GOLF';

INSERT INTO ranking_entries (id, pin_id, sports_profile_id, sport_type, rank, score, tier, games_played, updated_at)
SELECT
  gen_random_uuid(),
  'b95b3652-8b03-4615-9a29-6071a0e8b1f1'::uuid,  -- 사당역 핀
  sp.id,
  'GOLF',
  ROW_NUMBER() OVER (ORDER BY sp.current_score DESC),
  sp.current_score,
  sp.tier,
  sp.games_played,
  NOW()
FROM sports_profiles sp
WHERE sp.sport_type = 'GOLF' AND sp.is_active = true
ORDER BY sp.current_score DESC;

COMMIT;
