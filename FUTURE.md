# SwimFitPro — Future Considerations

A living log of features that are architecturally sound but need additional input signals or UX groundwork before they can be built properly. Revisit these as the data layer matures.

---

## 1. Adaptive Training — "What Needs Work" Layer
**Logged:** Build 69  
**Status:** Deferred — missing input signal

**The idea:**  
Dryland sessions adapt not just to readiness and RPE, but to specific movement quality gaps — e.g. "weak hip hinge", "poor overhead stability", "left/right imbalance". The engine would weight exercises toward those deficits automatically.

**What's needed before building:**
- Movement quality tracking inside the workout logger (rate each exercise: easy / hard / struggled)
- Coach/athlete feedback loop — a simple post-session "flag" (e.g. "hip hinge felt weak today")
- Minimum ~4 weeks of logged sessions to detect patterns vs. noise
- Possibly a baseline movement screen (separate from the strength baseline already in app)

**How it connects to existing architecture:**
- `autoDryland()` already selects exercises by phase and stroke — this layer would add a deficit-weighting pass on top
- Store deficit flags in `S.movementFlags` (array of `{muscle, flag, date}`)
- `getSessionsForDate()` or the workout builder reads flags and adjusts exercise selection/order

**Scientific backing:**  
Individualised weakness correction is standard in elite dryland programs (Rushall & Pyke, ASCA frameworks). The readiness-modulated engine (Build 69) is the prerequisite — don't build this without it.

---

## 2. Load Tracking — Reps/Sets Completed vs. Prescribed
**Logged:** Build 69  
**Status:** Deferred — needs workout logger upgrade

**The idea:**  
Track actual reps and load completed during each dryland session, not just whether it was done. Use the delta between prescribed and completed to infer fatigue, adaptation, and readiness for progression.

**What's needed:**
- In-session logging UI (during workout, not just post-session RPE)
- Progressive overload model (e.g. 2-for-2 rule: if athlete completes all reps with 2 reps in reserve for 2 sessions, increase load)
- Storage: extend `S.history` entries to include `{exercise, setsCompleted, repsCompleted, loadKg}`

**How it connects:**
- RPE log already exists — this adds granularity below the session level
- Feeds directly into "What Needs Work" layer above
- Could surface as a "progression ready" flag on the Dryland tab

---

## 3. Injury / Soreness Flag System
**Logged:** Build 69  
**Status:** Deferred — needs UX design

**The idea:**  
Swimmer can flag a body region as sore or injured (shoulder, lower back, knee etc.). Engine automatically excludes exercises that load that region and substitutes alternatives.

**What's needed:**
- Simple body-map UI (tap a region to flag it)
- Exercise library tagged by primary/secondary muscle group (partially exists)
- Substitution logic in the workout builder
- Auto-clear after X days or manual clear

**Scientific backing:**  
Load management around injury is fundamental. Avoiding aggravation while maintaining training stimulus is well-documented in sports medicine.

---

## 4. Coach Feedback Loop
**Logged:** Build 69  
**Status:** Deferred — needs multi-user/coach architecture

**The idea:**  
A coach can view athlete data and annotate sessions — "focus on hip drive this week", "reduce upper body load". Annotations feed into the adaptive engine.

**What's needed:**  
- Coach/athlete account linking (significant auth infrastructure)
- Shared data view for coach
- Annotation model on sessions and weeks
- This is essentially a v2 product feature, not a v1 enhancement

---

## Notes
- All deferred features assume the readiness-modulated engine (Build 69) is in place first
- Priority order when ready to build: Load Tracking → What Needs Work → Injury Flags → Coach Loop
- Revisit after 3 months of real user data — patterns will clarify what matters most
