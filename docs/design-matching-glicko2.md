# Glicko-2 알고리즘 상세

> 분리 출처: design-matching.md §3 (레이팅 시스템)
> 참고: Mark Glickman, "The Glicko-2 Rating System" (2001, Boston University)

---

## 1. 파라미터 (핀돌 기준값)

| 파라미터 | 기본값 | 설명 |
|----------|--------|------|
| μ (rating) | 1000 | 추정 실력 (기존 스케일 유지) |
| φ (RD) | 350 | 불확실성 — 높을수록 불확실 |
| σ (volatility) | 0.06 | 성적 변동성 |
| τ (tau) | 0.5 | 시스템 상수 (σ 변화량 제한) |

> Glicko-2 표준 기본값은 1500이지만 핀돌은 기존 점수 체계(1000 기준) 유지를 위해 1000 사용.
> 공식 예제: μ=1500, φ=200, σ=0.06, 3경기 후 μ'=1464.06, φ'=151.52.

---

## 2. 전체 업데이트 의사코드

```
function updateGlicko2(player, opponents):
  τ = 0.5

  μ_prime = (μ - 1500) / 173.7178
  φ_prime = φ / 173.7178

  if opponents is empty:
    φ_star = sqrt(φ_prime² + σ²)
    player.rd = φ_star × 173.7178
    return

  v = 0; Δ = 0

  for each (opponent, result) in opponents:
    μ_j = (opponent.rating - 1500) / 173.7178
    φ_j = opponent.rd / 173.7178
    g_φ_j = 1 / sqrt(1 + 3φ_j²/π²)
    E_j = 1 / (1 + exp(-g_φ_j × (μ_prime - μ_j)))
    v += g_φ_j² × E_j × (1 - E_j)
    Δ += g_φ_j × (result - E_j)

  v = 1/v; Δ = v × Δ

  // Step 3: 새로운 σ' (Illinois 알고리즘으로 수렴)
  σ_new = Illinois(a=ln(σ²), Δ, φ_prime, v, τ)

  φ_star = sqrt(φ_prime² + σ_new²)
  φ_new = 1 / sqrt(1/φ_star² + 1/v)
  μ_new = μ_prime + φ_new² × (Δ/v)

  player.rating = μ_new × 173.7178 + 1500
  player.rd = max(φ_new × 173.7178, 30.0)   // RD 최솟값 30
  player.rating = max(player.rating, 100.0)  // 레이팅 최솟값 100
  player.volatility = σ_new
```

---

## 3. Illinois 알고리즘 (σ 수렴)

Illinois 알고리즘은 볼라틸리티 σ를 수렴시키는 수치 해석 방법이다. Regula Falsi(거짓 위치법)의 변형으로, 수렴 속도가 빠르고 안정적이다.

```
function Illinois(a, Δ, φ, v, τ):
  // 목적함수 f(x) = 0 풀기
  // f(x) = exp(x)(Δ² - φ² - v - exp(x)) / (2(φ² + v + exp(x))²) - (x - a) / τ²

  ε = 0.000001  // 수렴 허용 오차
  A = a
  B = findInitialB(Δ, φ, v, τ, a)  // f(B) > 0 인 초기값 탐색

  fA = f(A); fB = f(B)

  while |B - A| > ε:
    C = A + (A - B) × fA / (fB - fA)
    fC = f(C)

    if fC × fB < 0:
      A = B; fA = fB
    else:
      fA = fA / 2  // Illinois 보정

    B = C; fB = fC

  return exp(B / 2)
```

**초기 B 탐색 (`findInitialB`)**:
- `Δ² > φ² + v` 이면: `B = ln(Δ² - φ² - v)`
- 아니면: k=1 씩 증가하며 `f(a - kτ) < 0` 될 때까지 탐색, `B = a - kτ`

---

## 4. RD 시간 감쇠 (비활동 유저)

```
function applyRdDecay(player, currentTime):
  daysSinceLastGame = (currentTime - player.glickoLastUpdatedAt) / 86400000

  if daysSinceLastGame >= 30:
    periods = floor(daysSinceLastGame / 30)
    φ = player.glickoRd / 173.7178
    for i in range(periods):
      φ = min(sqrt(φ² + σ²), 350 / 173.7178)  // 상한 350
    player.glickoRd = φ × 173.7178
```

매칭 큐 워커 실행 시 `decayRD()` 호출로 반영.

- 30일 비활동마다 1 period 경과
- φ 상한은 350 (초기값 이상 올라가지 않음)
- σ는 decay 시 변경하지 않음 (실제 게임 결과 기반으로만 갱신)

---

## 5. 점수 필드 분리

| 필드 | 역할 | 유저 노출 |
|------|------|-----------|
| `glickoRating` | 내부 MMR — 매칭 상대 탐색에만 사용 | 비공개 |
| `displayScore` | 유저에게 보이는 점수 = round(glickoRating) + 활동 보너스 | 공개 |
| `currentScore` | deprecated — displayScore와 동기화, 구버전 클라이언트 호환용 | 공개 |

```
displayScore = round(glickoRating) + 활동 보너스
currentScore = displayScore  // 기존 시스템 호환
```

- 거절 시: `displayScore`만 -15점 차감, `glickoRating` 불변
- 클라이언트: `displayScore` 우선 표시, null이면 `currentScore` 폴백

---

## 6. TypeScript 인터페이스

```typescript
// server/src/shared/utils/glicko2.ts
export interface Glicko2Player {
  rating: number;     // μ (기본 1000)
  rd: number;         // φ (기본 350)
  volatility: number; // σ (기본 0.06)
}

export interface Glicko2Opponent {
  rating: number;
  rd: number;
  result: 1 | 0.5 | 0;  // 승/무/패
}

export interface Glicko2Result {
  newRating: number;
  newRd: number;
  newVolatility: number;
  ratingChange: number;  // 표시용 변동량
}
```
