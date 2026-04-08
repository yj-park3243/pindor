#!/bin/bash
# 간단한 HTTP 서버로 테스트 클라이언트 서빙
cd "$(dirname "$0")"
echo "Test client: http://localhost:9090"
python3 -m http.server 9090
