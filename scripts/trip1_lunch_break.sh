#!/usr/bin/env bash
# =============================================================================
# Trip 1 — Lunch Break at Uni Ulm
#
# Simulates a user planning a 1-hour lunch break from the university.
#   Start/End : Uni Ulm (lat: 48.423058, lon: 9.958076)
#   Duration  : ~1 h total
#   Activities:
#     1. Eat  — 5 min, within 200 m of the university
#     2. Walk — 30 min, around the campus area
#
# Usage:
#   ./trip1_lunch_break.sh [BASE_URL]
#   QUESTMAP_API_URL=http://localhost:8000 ./trip1_lunch_break.sh
#
# Requires: curl, jq
# =============================================================================

set -euo pipefail

BASE_URL="${QUESTMAP_API_URL:-${1:-http://localhost:8000}}"
DRAFT_ID="draft-lunch-$(date +%s)"

# ── Colour helpers ────────────────────────────────────────────────────────────
C_INFO='\033[0;36m'   # cyan
C_WARN='\033[1;33m'   # yellow
C_OK='\033[0;32m'     # green
C_ERR='\033[0;31m'    # red
C_RESET='\033[0m'

log()          { echo -e "${C_INFO}[INFO   ]${C_RESET} $*"; }
log_question() { echo -e "${C_WARN}[QUESTION]${C_RESET} $*"; }
log_answer()   { echo -e "${C_OK}[ANSWER ]${C_RESET} $*"; }
log_plan()     { echo -e "${C_OK}[PLAN   ]${C_RESET} $*"; }
log_error()    { echo -e "${C_ERR}[ERROR  ]${C_RESET} $*" >&2; }

# ── Dependency check ──────────────────────────────────────────────────────────
for cmd in curl jq; do
  if ! command -v "$cmd" &>/dev/null; then
    log_error "Required command '$cmd' not found."
    exit 1
  fi
done

# ── 1. Create planning session ────────────────────────────────────────────────
log "Starting trip-planning session  (Trip 1 — Lunch Break @ Uni Ulm)"
log "Backend: ${BASE_URL}"
log "Draft ID: ${DRAFT_ID}"

SESSION_RESPONSE=$(curl -sf -X POST "${BASE_URL}/trip-planning/sessions" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg draftId "${DRAFT_ID}" \
    '{
      draftId: $draftId,
      startLocation: {lat: 48.423058, lon: 9.958076, label: "Uni Ulm"},
      endLocation:   {lat: 48.423058, lon: 9.958076, label: "Uni Ulm"},
      transportModes: ["walk"],
      steps: [
        {
          id: "step-eat",
          type: "eat",
          title: "Eat",
          details: "Quick lunch or snack near the university",
          time: {durationMinutes: 5},
          location: {
            type: "areaCircle",
            center: {lat: 48.423058, lon: 9.958076},
            radiusMeters: 200
          },
          iconKey: "restaurant",
          colorValue: 4293869636
        },
        {
          id: "step-walk",
          type: "walk",
          title: "Walk",
          details: "Relaxing walk around the campus area",
          time: {durationMinutes: 30},
          location: {
            type: "aroundPoint",
            point: {lat: 48.423058, lon: 9.958076}
          },
          iconKey: "directions_walk",
          colorValue: 4279242334
        }
      ]
    }'
  )")

SESSION_ID=$(echo "${SESSION_RESPONSE}" | jq -r '.sessionId // empty')
if [[ -z "${SESSION_ID}" ]]; then
  log_error "Failed to obtain session ID. Response was:"
  echo "${SESSION_RESPONSE}" | jq . >&2 || echo "${SESSION_RESPONSE}" >&2
  exit 1
fi
log "Session created: ${SESSION_ID}"

# ── 2. Answer helper ──────────────────────────────────────────────────────────
post_answer() {
  local QUESTION_ID="$1"
  local VALUE_JSON="$2"  # raw JSON value (e.g. true, 5, "opt-id")

  local HTTP_STATUS
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "${BASE_URL}/trip-planning/sessions/${SESSION_ID}/answers" \
    -H "Content-Type: application/json" \
    -d "{\"questionId\": \"${QUESTION_ID}\", \"value\": ${VALUE_JSON}}")

  if [[ "${HTTP_STATUS}" == "204" ]]; then
    log_answer "Answer accepted (HTTP 204)."
  else
    log_error "Unexpected HTTP ${HTTP_STATUS} when posting answer."
  fi
}

# Auto-answer logic for Trip 1:
#   yesNo      → true  (accept all suggestions during a short lunch break)
#   number     → 5     (matches the 5-minute eat step duration)
#   text       → "casual lunch near campus"
#   selection  → first option id
#   routeChoice→ first option id
handle_question() {
  local QUESTION_JSON="$1"
  local QID KIND PROMPT

  QID=$(echo "${QUESTION_JSON}"    | jq -r '.id')
  KIND=$(echo "${QUESTION_JSON}"   | jq -r '.kind')
  PROMPT=$(echo "${QUESTION_JSON}" | jq -r '.prompt')

  log_question "Kind=${KIND}  |  ${PROMPT}"

  # Print available options if any
  local OPT_COUNT
  OPT_COUNT=$(echo "${QUESTION_JSON}" | jq '.options | length')
  if [[ "${OPT_COUNT}" -gt 0 ]]; then
    echo "${QUESTION_JSON}" | jq -r '.options[] | "  • [\(.id)] \(.title)"'
  fi

  local ANSWER_VALUE
  case "${KIND}" in
    yesNo)
      ANSWER_VALUE="true"
      ;;
    number)
      ANSWER_VALUE="5"
      ;;
    text)
      ANSWER_VALUE='"casual lunch near campus"'
      ;;
    selection | routeChoice)
      local FIRST_ID
      FIRST_ID=$(echo "${QUESTION_JSON}" | jq -r '.options[0].id // ""')
      if [[ -n "${FIRST_ID}" && "${FIRST_ID}" != "null" ]]; then
        ANSWER_VALUE="\"${FIRST_ID}\""
      else
        ANSWER_VALUE='"default"'
      fi
      ;;
    *)
      ANSWER_VALUE='"yes"'
      ;;
  esac

  log_answer "Responding to '${QID}' with: ${ANSWER_VALUE}"
  post_answer "${QID}" "${ANSWER_VALUE}"
}

# ── 3. Stream SSE events ──────────────────────────────────────────────────────
log "Connecting to event stream …"

FINAL_PLAN=""
DONE=0
EVENT_DATA=""

while IFS= read -r line; do
  # Skip SSE keepalive comments
  [[ "${line}" == :* ]] && continue

  if [[ "${line}" == data:* ]]; then
    # Accumulate data lines (spec allows multi-line data)
    local_data="${line#data:}"
    local_data="${local_data# }"
    EVENT_DATA+="${local_data}"

  elif [[ -z "${line}" && -n "${EVENT_DATA}" ]]; then
    # Blank line = end of event; dispatch it
    TYPE=$(echo "${EVENT_DATA}" | jq -r '.type // ""' 2>/dev/null || true)

    case "${TYPE}" in
      status)
        MSG=$(echo "${EVENT_DATA}" | jq -r '.message // "Working…"')
        log "Status: ${MSG}"
        ;;

      question)
        QUESTION=$(echo "${EVENT_DATA}" | jq -c '.question')
        handle_question "${QUESTION}"
        ;;

      partialPlan)
        TITLE=$(echo "${EVENT_DATA}" | jq -r '.plan.title // "Partial plan"')
        log "Partial plan: ${TITLE}"
        ;;

      finalPlan)
        FINAL_PLAN=$(echo "${EVENT_DATA}" | jq -c '.plan')
        TITLE=$(echo "${EVENT_DATA}" | jq -r '.plan.title // "Trip plan"')
        log_plan "Final plan received: ${TITLE}"
        DONE=1
        ;;

      error)
        MSG=$(echo "${EVENT_DATA}" | jq -r '.message // "Unknown error"')
        log_error "Planning failed: ${MSG}"
        DONE=1
        ;;

      done)
        log "Stream closed by server."
        DONE=1
        ;;
    esac

    EVENT_DATA=""

    [[ "${DONE}" -eq 1 ]] && break
  fi

done < <(curl -sf -N \
  -H "Accept: text/event-stream" \
  "${BASE_URL}/trip-planning/sessions/${SESSION_ID}/events" 2>&1 || true)

# ── 4. Print result ───────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════"
echo "  TRIP 1 — LUNCH BREAK @ UNI ULM"
echo "  Session : ${SESSION_ID}"
echo "════════════════════════════════════════════════════════════"

if [[ -n "${FINAL_PLAN}" ]]; then
  log_plan "Final plan:"
  echo "${FINAL_PLAN}" | jq .
else
  log "No final plan in stream. Fetching session snapshot …"
  curl -sf "${BASE_URL}/trip-planning/sessions/${SESSION_ID}" | jq . || \
    log_error "Could not fetch session snapshot."
fi
