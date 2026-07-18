# Relay — Live Demo Plan

## Demo objective

In under three minutes, prove one complete loop:

> **Relay understands the care plan, discovers a real-world barrier the encounter could not see, and converts it into a verified downstream action or upstream escalation.**

The judges should leave remembering:

1. **The chart stops at the encounter. Relay does not.**
2. **The agent combines clinical context with live evidence from the patient’s world.**
3. **It closes the loop through fulfillment or escalation—not another report or dashboard.**

The Monica workflow is the demonstration. Care-plan execution is the platform.

---

## Demo format

- **No slides.** Begin inside the working Relay application.
- **Target length:** 2 minutes 40 seconds. Preserve 20 seconds of buffer.
- **Primary surfaces:** iPad walkthrough → generated clinician report in the browser.
- **Do not show:** source code, terminal logs, architecture diagrams, model names, raw FHIR JSON, or setup screens unless asked during Q&A.
- **One live interaction:** the agent sees and reacts to a planted hazard.
- **One decisive finding:** the home or equipment makes the discharge plan infeasible.
- **One economic action:** coverage-aware fulfillment or an escalation with a named owner.

---

## The story

Monica Hilpert is a 76-year-old synthetic patient leaving skilled nursing rehabilitation. She is severely deconditioned, has osteoporosis and back and hip pain, is afraid of standing, and lives alone.

Her chart can describe her risk and prescribe a plan. It cannot see the apartment she is returning to.

Relay conducts the post-encounter follow-through. Monica’s caregiver walks the home with an iPad. Relay reads the chart, guides the walkthrough, sees hazards, measures the environment, asks clarifying questions, checks whether the care plan is feasible, and creates the appropriate actions for the care team.

---

## Exact three-minute run of show

### 0:00–0:20 — Open with the patient and the gap

**Screen:** Relay start screen showing Monica, not a title slide.

**Say:**

> “This is Monica. She’s 76, leaving skilled nursing rehab after a hospital stay. She has osteoporosis, severe deconditioning, back and hip pain, and she lives alone. Her care team knows all of that. What they cannot see is the home they’re sending her back to.”

Then tap **Start walkthrough**.

### 0:20–0:35 — Define Relay while it starts

**Screen:** Live RoomPlan camera and voice connection.

**Say:**

> “Relay turns the care plan into a real-world follow-through workflow. Monica’s niece can walk the apartment with an iPad before Monica comes home.”

Do not explain LiDAR, Haiku, Sonnet, ElevenLabs, FastAPI, or FHIR here.

### 0:35–1:05 — Live perception and conversation

**Action:** Walk toward one planted loose rug or extension cord in the main path. Hold the frame steady until Relay produces a callout.

**Agent should say something like:**

> “That loose rug is in the main walking path. A walker wheel could catch on it.”

If the confirmation overlay appears, answer it live with one tap or voice.

**Say only if needed:**

> “That is not a generic object label. Relay is prioritizing what it sees for Monica’s mobility, osteoporosis, and living situation.”

Allow one short agent question, then answer naturally. Do not conduct a long conversation.

### 1:05–1:35 — The decisive care-plan mismatch

**Action:** Complete or reveal the bathroom/doorway assessment.

**Required beat:**

> “Relay measured this doorway at 27 inches. Monica’s walker is 28. The current discharge plan physically cannot work.”

This measurement must come from an actual RoomPlan result or a clearly identified previously captured portion of Monica’s assessment. Never claim a staged number was measured live if it was not.

**Say:**

> “The important part is not that it found another hazard. It found evidence that has to travel back upstream and change the plan before discharge.”

### 1:35–2:25 — Show the action, not just the finding

Tap **End walkthrough**, then open the generated clinician report.

The report should land directly on a concise action summary showing:

- The critical finding and photo.
- The exact measurement.
- Why it matters for Monica.
- Coverage status.
- Required documentation or approval.
- Assigned owner.
- Deadline or urgency.
- Fulfillment or escalation status.

**Say:**

> “Relay does not stop at a report. For a covered item, it verifies the benefit, prepares the documentation, routes the order for clinician approval, sends it to an eligible supplier, and tracks delivery. If the plan itself is impossible—like this doorway—it escalates to OT and the discharge coordinator with the evidence needed to change it.”

Show one action card, not every finding.

Suggested action card:

| Field | Demo value |
|---|---|
| Barrier | Bathroom doorway narrower than prescribed walker |
| Status | Discharge-plan exception |
| Coverage | Replacement mobility device requires clinical review |
| Owner | OT + discharge coordinator |
| Required by | Before discharge Friday |
| Next action | Reassess equipment fit or home/discharge plan |

Then briefly show a second, simpler example:

> “A covered walker can be prepared for approval and fulfillment. A grab bar is generally not covered by Original Medicare, so Relay routes that through the patient’s plan benefits, social work, or a self-pay option instead of pretending it is covered.”

### 2:25–2:50 — Expand from Monica to Relay

Keep the live report on screen.

**Say:**

> “Monica’s home assessment is the first workflow. The same loop applies after any encounter: medication pickup, wound supplies, symptom check-ins, transportation, referrals, or home services. Relay keeps advancing the care plan until it is completed or reaches the right human.”

### 2:50–3:00 — Close

**Say:**

> “Abridge captures the encounter. Relay carries the care forward—because care does not end when the encounter does.”

Stop. Do not add an architecture summary.

---

## What must be visible in the product

### iPad start screen

The opening surface should establish the story without a slide:

- **Relay** product name.
- “Care does not end at the encounter.”
- Monica Hilpert, 76.
- “Post-acute discharge follow-through.”
- Three chart-grounded facts: osteoporosis, severe deconditioning, lives alone.
- One primary button: **Start Monica’s walkthrough**.

### Live walkthrough

- Camera/RoomPlan view is visually dominant.
- Agent’s latest line is readable.
- Voice connection status is small and nontechnical.
- Confirmation card supports a single yes/no answer.
- Avoid showing backend host/IP controls during the judged demo.
- Avoid room pickers or debugging controls unless essential.

### Clinician action report

The report should lead with **What needs to happen before discharge**, not a long list of findings.

Recommended order:

1. Discharge blockers.
2. Actions, owners, deadlines, and status.
3. Evidence: image, measurement, and patient-specific rationale.
4. Coverage and documentation requirements.
5. Patient/caregiver responses.
6. Remaining lower-severity findings.
7. FHIR write-back as a quiet implementation detail.

The current report leads with graded findings and places actions fourth. For the demo, invert that hierarchy.

---

## Live versus pre-captured evidence

The safest truthful structure is a **hybrid live assessment**:

- Pre-capture the difficult bathroom and doorway portion using the real iPad and RoomPlan.
- Begin the judged demo by continuing Monica’s existing assessment.
- Add one new live hazard in front of the judges.
- Finish the assessment and generate the combined report live.

This remains a live product demonstration: the agent is observing, conversing, updating state, and producing the final action plan in real time. It also avoids betting the entire presentation on RoomPlan discovering a useful doorway inside the judging area.

State this plainly if needed:

> “Her niece scanned the bathroom earlier. I’m continuing the assessment here with the final walking area.”

Do not silently present pre-captured evidence as a measurement taken in the judging room.

---

## Hazard kit

Use no more than two planted items:

- A loose throw rug in the walking path.
- An extension cord crossing or approaching the path.

The rug is the primary live target. The cord is backup.

Avoid a crowded collection of props. It makes the system look like a generic hazard detector and distracts from the care-plan execution story.

---

## Failure ladder

The fallback should preserve the same story rather than switching to a different demo.

### Level 1 — Full live loop

- Live voice.
- Live camera callout.
- Live confirmation.
- Live report generation.
- Previously captured doorway measurement included transparently.

### Level 2 — Voice fails

- Continue the RoomPlan and frame upload.
- Read the on-screen callout.
- Answer confirmation by tapping.
- Generate the report normally.

**Recovery line:**

> “The voice layer dropped, but the clinical workflow is still live—the evidence is already entering Monica’s assessment.”

### Level 3 — Live perception is slow or misses the rug

- Hold still for one additional frame cycle.
- Move to the cord backup.
- If still unsuccessful, finish the assessment and show the pre-captured evidence in the live report.

Do not repeatedly wave the camera at the object.

### Level 4 — RoomPlan fails in the venue

- Use the transparently pre-captured bathroom measurement.
- Continue the live camera assessment.

### Level 5 — Network or backend failure

- Keep a completed Monica run loaded locally in the browser.
- Walk through the evidence and action path without pretending the current scan completed.

**Recovery line:**

> “The live connection dropped, so I’m opening the last assessment produced by this same workflow.”

Never apologize at length. Recover once and continue the clinical story.

---

## Product changes required before rehearsal

### P0 — Required for the story

- Rename visible product surfaces from **Steady** to **Relay**.
- Put “Care does not end at the encounter” on the start screen.
- Add Monica’s three chart-grounded facts to the opening surface.
- Remove or hide the backend-host field during demo mode.
- Support continuing a pre-captured Monica assessment rather than always creating a blank run.
- Make the generated report open immediately after finishing.
- Reorder the report so blockers and actions appear before the full finding list.
- Add explicit **coverage, owner, status, deadline, and next action** fields.
- Make the doorway mismatch an upstream discharge-plan exception, not only a DME recommendation.

### P1 — Valuable if P0 is stable

- Add a visible fulfillment lifecycle: `identified → documentation ready → approval required → routed → delivered`.
- Show source labels: chart, caregiver, camera, LiDAR, payer policy.
- Add one one-click clinician action such as **Approve draft** or **Send to OT queue**, with a demo-safe confirmation.
- Add a “continue assessment” mode with the bathroom evidence already present.

### Cut from the judged flow

- Raw FHIR bundle.
- SAM segmentation masks.
- Architecture explanations.
- More than two live hazards.
- A long voice conversation.
- Claims of a measured readmission reduction.
- Automatic purchasing without approval or verified coverage.

---

## Rehearsal checklist

### Technical

- Backend health endpoint returns successfully.
- Mac IP and iPad backend host match.
- ngrok/custom-LLM endpoint is current.
- ElevenLabs voice connects from the venue network.
- iPad is charged and connected to backup power.
- RoomPlan and camera frame upload work simultaneously.
- Browser report is open in a pinned tab.
- Pre-captured Monica run is available locally.
- A second completed report is available as last-resort backup.
- Notifications and sleep are disabled on Mac and iPad.

### Demo data

- Bathroom measurement is real and correctly labeled.
- Walker width is explicitly a demo scenario input.
- Monica’s chart facts are separated from scenario assumptions.
- At least one critical finding has a photo and specific recommendation.
- Coverage language is accurate and does not promise payment.
- All clinical actions remain draft or approval-gated.

### Performance

- Rehearse the complete demo five times.
- Two rehearsals must use the primary live path.
- One must intentionally disable voice.
- One must intentionally use the saved-report fallback.
- Final two rehearsals must finish under 2:40 without rushing.
- Stop immediately after the closing line.

---

## Likely judge questions

### “Is this replacing an occupational therapist?”

> “No. Relay extends OT and care-transition capacity. It gathers evidence, resolves routine actions, and sends professionals the cases that require judgment—with the home context already attached.”

### “How do you trust the vision model?”

> “Every material finding is tied to an image, measurement, chart fact, or caregiver confirmation. Relay does not create a risk score or independently change the care plan. Uncertain and high-impact actions are approval-gated.”

### “Why does this need to be an agent?”

> “Because the work does not end with classification. Relay has to gather missing evidence, ask follow-up questions, check benefits, prepare documentation, route actions across systems, confirm fulfillment, and escalate exceptions.”

### “Who pays?”

> “The strongest buyers are organizations carrying transition and utilization risk: Medicare Advantage plans, ACOs, health systems, SNFs, and post-acute networks. For Monica, SNFs already have payment tied to 30-day readmissions and successful community discharge.”

### “Can it really order equipment automatically?”

> “Relay verifies coverage and prepares the order for the required clinical approval. Once approved, it can route it to an eligible supplier and track delivery. It does not invent coverage or bypass prescribing authority.”

### “Is this only for falls?”

> “No. Home readiness is the first workflow. The core engine converts any care plan into verified post-encounter actions—medications, wound supplies, symptom check-ins, transportation, referrals, or home services.”

### “What is proprietary?”

> “Over time, Relay learns from the durable link between the original care plan, real-world barrier, chosen intervention, fulfillment result, and clinical outcome. That closed-loop dataset is more valuable than another collection of notes.”

---

## Final demo principle

Do not try to prove every feature.

Prove that the encounter produced a plan, the real world broke that plan, and Relay discovered and repaired the break before it reached the patient.

