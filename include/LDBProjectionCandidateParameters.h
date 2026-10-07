#pragma once
// Experimental named host controls mapped onto existing reserved ABI slots.
// Candidate UI model: 0 Off, 1 Equidistant, 2 Stereographic.
#include "LDBOpticsParameters.h"
#include <algorithm>
#include <cmath>

inline void LDBSetProjectionCandidate(LDBOpticsParameters& p, int model,
                                     double amountPercent, double angleDegrees,
                                     int framing) {
    p.reservedV4_3 = std::isfinite(amountPercent) ? float(std::clamp(amountPercent, 0.0, 100.0)*.01) : 0.0f;
    p.reservedV4_4 = model==1 ? 1.0f : (model==2 ? 3.0f : 0.0f);
    p.reservedV4_5 = std::isfinite(angleDegrees) ? float(std::clamp(angleDegrees, 0.0, 89.0)) : 0.0f;
    p.reservedV4_7 = framing==0 ? 0.0f : (framing==2 ? 1.0f : .55f);
}
inline bool LDBProjectionCandidateActive(const LDBOpticsParameters& p) {
    return std::isfinite(p.reservedV4_3) && p.reservedV4_3>1e-6f &&
           std::isfinite(p.reservedV4_5) && p.reservedV4_5>0.0f &&
           (p.reservedV4_4==1.0f || p.reservedV4_4==3.0f);
}
