#!/bin/bash
# 매칭 관련 데이터 전체 초기화 (테스트용)
# 사용법: bash reset-matching.sh

set -e

KEY="$HOME/WebProject2/match/spots-key.pem"
HOST="ec2-user@43.203.165.114"
DB_CMD="PGPASSWORD='SpotsDB2026!' psql -h spots-db.cuhooenm6qww.ap-northeast-2.rds.amazonaws.com -U spots_admin -d spots"

echo "⚠️  매칭 관련 데이터를 모두 삭제합니다."
echo "   (match_requests, matches, match_acceptances, games, chat, score_histories 등)"
echo ""
read -p "정말 삭제하시겠습니까? (y/N): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
  echo "취소됨."
  exit 0
fi

echo ""
echo ">>> 매칭 데이터 삭제 중..."

ssh -i "$KEY" "$HOST" "$DB_CMD -c \"
-- FK 순서대로 삭제
DELETE FROM score_histories;
DELETE FROM result_confirmations;
DELETE FROM game_result_proofs;
DELETE FROM games;
DELETE FROM match_acceptances;
DELETE FROM messages;
DELETE FROM chat_rooms;
DELETE FROM matches;
DELETE FROM match_requests;
DELETE FROM notifications WHERE type IN ('MATCH_FOUND', 'MATCH_ACCEPTED', 'MATCH_REJECTED', 'MATCH_CANCELLED', 'MATCH_PENDING_ACCEPT', 'GAME_RESULT', 'CHAT_MESSAGE', 'CHAT_IMAGE');

-- 확인
SELECT 'match_requests' AS tbl, COUNT(*) FROM match_requests
UNION ALL SELECT 'matches', COUNT(*) FROM matches
UNION ALL SELECT 'match_acceptances', COUNT(*) FROM match_acceptances
UNION ALL SELECT 'games', COUNT(*) FROM games
UNION ALL SELECT 'chat_rooms', COUNT(*) FROM chat_rooms
UNION ALL SELECT 'messages', COUNT(*) FROM messages
UNION ALL SELECT 'score_histories', COUNT(*) FROM score_histories;
\""

echo ""
echo "✅ 매칭 데이터 초기화 완료!"
