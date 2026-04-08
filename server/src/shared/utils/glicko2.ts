// Glicko-2 system constants
const TAU = 0.5; // system constant (controls volatility change rate)
const EPSILON = 0.000001; // convergence tolerance
const GLICKO2_SCALE = 173.7178; // 400/ln(10)

export interface Glicko2Rating {
  rating: number;     // μ (Glicko-1 scale, base 1000)
  rd: number;         // Rating Deviation (Glicko-1 scale)
  volatility: number; // σ
}

export interface Glicko2Result {
  opponentRating: number;
  opponentRd: number;
  score: number; // 1.0 = win, 0.5 = draw, 0.0 = loss
}

// Convert Glicko-1 scale to Glicko-2 internal scale
function toGlicko2Scale(rating: number): number {
  return (rating - 1000) / GLICKO2_SCALE; // Use 1000 as base instead of 1500
}

function toGlicko2RD(rd: number): number {
  return rd / GLICKO2_SCALE;
}

// Convert back to Glicko-1 scale
function fromGlicko2Scale(mu: number): number {
  return mu * GLICKO2_SCALE + 1000;
}

function fromGlicko2RD(phi: number): number {
  return phi * GLICKO2_SCALE;
}

// g(φ) function
function g(phi: number): number {
  return 1 / Math.sqrt(1 + 3 * phi * phi / (Math.PI * Math.PI));
}

// E(μ, μj, φj) function — expected score
function E(mu: number, muj: number, phij: number): number {
  return 1 / (1 + Math.exp(-g(phij) * (mu - muj)));
}

/**
 * Update Glicko-2 rating after a set of games in one rating period.
 * Pass results=[] to apply only the RD decay for an inactive period.
 */
export function updateGlicko2(
  player: Glicko2Rating,
  results: Glicko2Result[],
): Glicko2Rating {
  if (results.length === 0) {
    // No games: only RD increases (uncertainty grows)
    const phi = toGlicko2RD(player.rd);
    const newPhi = Math.sqrt(phi * phi + player.volatility * player.volatility);
    return {
      rating: player.rating,
      rd: Math.min(fromGlicko2RD(newPhi), 350), // cap at 350
      volatility: player.volatility,
    };
  }

  const mu = toGlicko2Scale(player.rating);
  const phi = toGlicko2RD(player.rd);

  // Step 3: Compute v (estimated variance)
  let vInv = 0;
  for (const result of results) {
    const muj = toGlicko2Scale(result.opponentRating);
    const phij = toGlicko2RD(result.opponentRd);
    const gPhij = g(phij);
    const eVal = E(mu, muj, phij);
    vInv += gPhij * gPhij * eVal * (1 - eVal);
  }
  const v = 1 / vInv;

  // Step 4: Compute delta
  let delta = 0;
  for (const result of results) {
    const muj = toGlicko2Scale(result.opponentRating);
    const phij = toGlicko2RD(result.opponentRd);
    delta += g(phij) * (result.score - E(mu, muj, phij));
  }
  delta *= v;

  // Step 5: Determine new volatility via Illinois algorithm
  const a = Math.log(player.volatility * player.volatility);
  const phiSquared = phi * phi;
  const deltaSquared = delta * delta;

  function f(x: number): number {
    const ex = Math.exp(x);
    const d = phiSquared + v + ex;
    return (ex * (deltaSquared - phiSquared - v - ex)) / (2 * d * d) - (x - a) / (TAU * TAU);
  }

  let A = a;
  let B: number;
  if (deltaSquared > phiSquared + v) {
    B = Math.log(deltaSquared - phiSquared - v);
  } else {
    let k = 1;
    while (f(a - k * TAU) < 0) k++;
    B = a - k * TAU;
  }

  let fA = f(A);
  let fB = f(B);
  while (Math.abs(B - A) > EPSILON) {
    const C = A + (A - B) * fA / (fB - fA);
    const fC = f(C);
    if (fC * fB <= 0) {
      A = B;
      fA = fB;
    } else {
      fA = fA / 2;
    }
    B = C;
    fB = fC;
  }
  const newSigma = Math.exp(A / 2);

  // Step 6: Update RD (pre-rating period)
  const phiStar = Math.sqrt(phiSquared + newSigma * newSigma);

  // Step 7: Update rating and RD
  const newPhi = 1 / Math.sqrt(1 / (phiStar * phiStar) + 1 / v);
  const newMu = mu + newPhi * newPhi * (delta / v);

  return {
    rating: Math.max(100, Math.round(fromGlicko2Scale(newMu))), // min 100
    rd: Math.min(fromGlicko2RD(newPhi), 350), // cap at initial RD
    volatility: newSigma,
  };
}

/**
 * Increase RD over time (for inactive players).
 * Call this before matching to account for inactivity.
 * @param rd current Rating Deviation
 * @param volatility current volatility (σ)
 * @param periodsSinceLastGame number of rating periods without games
 */
export function decayRD(rd: number, volatility: number, periodsSinceLastGame: number): number {
  const phi = toGlicko2RD(rd);
  const decayed = Math.sqrt(phi * phi + periodsSinceLastGame * volatility * volatility);
  return Math.min(fromGlicko2RD(decayed), 350);
}
