# Relay

## Care does not end at the encounter.

**Relay is a chart-aware agent that turns a clinical care plan into verified action in the patient’s real world.**

Abridge captures what happened during the encounter. Relay carries the plan forward: it identifies what must happen next, discovers what may prevent it, advances the required actions, confirms completion, and escalates unresolved barriers to the right person.

The product is broader than fall prevention. Monica’s home-readiness assessment is the first workflow and the clearest demonstration of the platform.

---

## The problem

Every clinical encounter ends with a plan:

- Take a new medication twice a day.
- Keep the wound dry and watch for worsening symptoms.
- Use the prescribed mobility device.
- Remove fall hazards before returning home.
- Schedule physical therapy and a follow-up appointment.
- Monitor blood pressure or glucose.
- Call the care team if a specific condition changes.

Once the patient leaves, the care team loses visibility. The chart records what was recommended, but usually cannot show whether the plan is understood, feasible, fulfilled, or working.

The prescription may never be picked up. The equipment may not arrive. The walker may not fit through the bathroom door. The patient may have no transportation, no caregiver, or no way to pay for an uncovered item. These failures remain invisible until someone makes a manual follow-up call—or the patient returns to acute care.

Relay closes this gap between **the documented care plan** and **the patient’s lived reality**.

---

## The product

After an encounter, Relay reads the clinical context and creates an adaptive follow-through workflow. It communicates with the patient or caregiver, gathers evidence, asks questions based on what it discovers, executes permitted actions, and escalates exceptions.

Depending on the encounter, Relay can:

- Verify that medications, DME, and clinical supplies are present and understood.
- Check whether the home can support the prescribed mobility and care plan.
- Guide structured wound, symptom, or recovery check-ins.
- Identify environmental, financial, nutritional, transportation, or caregiver barriers.
- Confirm that follow-up appointments and home services are feasible.
- Verify insurance benefits and supplier eligibility.
- Draft orders, referrals, authorizations, and care-team messages for approval.
- Track delivery, scheduling, and task completion.
- Escalate clinical, operational, or social exceptions.
- Write verified findings and completion status back to the longitudinal record.

Relay is not merely a monitoring layer. Its economic value comes from advancing the case until the care-plan obligation is either completed or placed in front of the correct human with the evidence needed to act.

---

## The closed-loop workflow

> **Detect → verify → prepare → approve → fulfill → confirm → escalate**

1. **Detect:** Translate the encounter and care plan into explicit post-encounter obligations.
2. **Verify:** Gather evidence from the patient, caregiver, home, chart, payer, and supplier network.
3. **Prepare:** Assemble the correct order, referral, documentation, authorization, or patient action.
4. **Approve:** Obtain clinician approval whenever medical judgment, prescribing authority, or a change to the care plan is required.
5. **Fulfill:** Route the approved action to the appropriate supplier, service, scheduler, or care-team queue.
6. **Confirm:** Verify that the item arrived, the appointment was booked, the instruction was understood, or the intervention occurred.
7. **Escalate:** Route any unresolved clinical, operational, financial, or social barrier—with evidence and urgency—to the right person.

Relay does not need unlimited autonomy. It needs enough autonomy to move every case forward safely.

---

## Monica: the first workflow

Monica Hilpert is a 76-year-old synthetic patient admitted to skilled nursing rehabilitation after an approximately one-week hospital stay. Her chart describes osteoporosis, obesity, severe deconditioning, low-back and bilateral hip pain, fear of standing, limited mobility, social isolation, and living alone with only minimal help from a neighbor.

The hackathon scenario adds that Monica is preparing to return home, uses a 28-inch front-wheeled walker, and has a niece available to assess the apartment before discharge. These are explicit demo inputs rather than facts extracted from the source encounter.

### The walkthrough

Monica’s niece walks the apartment with an iPad Pro. Relay combines:

- Monica’s chart and discharge context.
- A guided, full-duplex conversation.
- Camera evidence of rugs, cords, clutter, lighting, furniture, and transfer surfaces.
- LiDAR measurements of doorways, openings, rooms, and maneuvering clearance.
- Questions about behavior the camera cannot observe.

Relay guides the route from the entrance to the main walking path, bathroom, bedroom, and kitchen. It reacts to visible findings and asks questions such as:

- Where does Monica steady herself on the way to the bathroom at night?
- Which side of the bed does she use?
- Can she reach the things she uses every day without a stool?
- Who will be present during her first day home?

### The killer demonstration

> **“The bathroom doorway is 27 inches. Monica’s walker is 28. The current discharge plan will not work.”**

This is more than hazard detection. Relay has found a mismatch between the clinical plan and the physical environment.

It sends that evidence upstream so the care team can reconsider the equipment, home modification, caregiver support, therapy plan, or discharge destination. Automatically ordering the same incompatible walker would not be success.

### The output

Relay produces a clinician-reviewable record containing:

- Prioritized findings with photographic evidence.
- Exact spatial measurements.
- Patient-specific clinical rationale.
- Relevant CDC STEADI or home-safety checklist items.
- Patient- and caregiver-reported context.
- Recommended interventions.
- Coverage and documentation status.
- Drafted-not-sent orders, referrals, and care-team actions.
- A clear owner and escalation path for every unresolved item.
- Structured findings ready for FHIR write-back after approval.

It does **not** fabricate a readmission-risk percentage or present model output as a clinical diagnosis.

---

## The economic thesis

Relay turns post-encounter follow-through from an unstructured labor problem into a closed-loop operating system.

Its value has two components:

### Clinical and utilization value

- Identify modifiable barriers before they become acute events.
- Improve completion of discharge and follow-up actions.
- Reduce failed transitions, avoidable escalation, and unnecessary utilization.
- Help patients remain safely in the least intensive appropriate setting.

### Operational value

- Reduce manual follow-up calls and chart review.
- Automate benefits and supplier checks.
- Reduce incomplete referrals and missing documentation.
- Route exceptions instead of asking staff to inspect every case.
- Give care coordinators a verified completion record rather than another task list.

A simple buyer-side model is:

> **Annual value = avoided utilization + staff time saved + recovered reimbursement − intervention and fulfillment cost**

For a pilot or hackathon demonstration, Relay should not claim a measured reduction in readmissions. It should demonstrate leading indicators:

- Time from detected gap to approved action.
- Percentage of post-encounter obligations completed.
- Equipment or service delivered before the required date.
- Exceptions correctly identified and escalated.
- Coordinator minutes saved per patient.
- Intervention cost compared with plausible acute-care utilization.
- Evidence written back into the record.

---

## Buyer and reimbursement alignment

The strongest long-term buyers are organizations that bear clinical and financial risk across the transition:

- Medicare Advantage plans.
- Accountable Care Organizations and delegated medical groups.
- Health systems operating under value-based contracts.
- Skilled nursing facilities and post-acute networks.
- Home-health organizations.

For Monica’s workflow, a skilled nursing facility is a credible initial buyer. The CMS Skilled Nursing Facility Value-Based Purchasing program withholds 2% of Medicare fee-for-service Part A payments and redistributes a portion based on performance. Current and upcoming measures include 30-day all-cause readmissions and successful discharge to the community, which economically connect safer transitions to provider performance. See the [FY 2026 SNF payment-system final rule](https://www.cms.gov/newsroom/fact-sheets/fy-2026-skilled-nursing-facility-snf-prospective-payment-system-final-rule-cms-1827-f) and [SNF VBP measures](https://www.cms.gov/medicare/quality/nursing-home-improvement/value-based-purchasing/measures).

Hospitals also face direct incentives under the Hospital Readmissions Reduction Program, although the program applies to a defined set of conditions and procedures rather than every discharge. See the [CMS Hospital Readmissions Reduction Program](https://www.cms.gov/medicare/payment/prospective-payment-systems/acute-inpatient-pps/hospital-readmissions-reduction-program-hrrp).

The broadest economic argument therefore belongs with risk-bearing organizations, while Monica provides a concrete post-acute wedge.

---

## Coverage-aware fulfillment

“Automatically order everything covered” is attractive but incomplete. The credible product promise is:

> **Relay verifies benefits and prepares covered equipment and services for one-click clinical approval and fulfillment.**

Original Medicare Part B may cover medically necessary DME—including walkers, wheelchairs, hospital beds, canes, and certain commode chairs—when a qualified provider orders it for home use and applicable supplier and documentation requirements are met. Patients generally remain responsible for the deductible and coinsurance. See [Medicare durable medical equipment coverage](https://www.medicare.gov/coverage/durable-medical-equipment-dme-coverage).

However, many intuitive home-safety interventions are not covered under Original Medicare:

- Grab bars are generally treated as self-help devices rather than covered DME.
- Raised toilet seats are noncovered.
- Home modifications are generally noncovered.
- A commode chair may be covered under defined circumstances, but not merely when used as a raised toilet seat.

See the [CMS DME reference list](https://www.cms.gov/files/document/r13808ncd.pdf) and [CMS commode policy article](https://www.cms.gov/medicare-coverage-database/view/article.aspx?articleid=52461&ver=21).

Relay therefore needs multiple fulfillment rails:

| Finding | Relay action |
|---|---|
| Covered item already ordered | Route to an eligible supplier and track delivery |
| Potentially covered, documentation missing | Draft the order and medical-necessity evidence for approval |
| Plan-specific supplemental benefit | Verify eligibility and initiate authorization |
| Uncovered, low-cost intervention | Present patient cost, build a shopping list, or use a sponsored benefit |
| Structural home modification | Route to OT, care management, community resources, or a plan benefit |
| Clinical or physical mismatch | Escalate upstream to reconsider the care plan |

The system should never represent “recommended” as “covered,” silently purchase a clinical item, or change a prescribed plan without the required human authority.

---

## Upstream context and downstream execution

### Upstream inputs

- Abridge ambient transcript, note, and after-visit plan.
- Diagnoses, medications, orders, functional status, and FHIR context.
- Discharge instructions and care-team responsibilities.
- Payer benefits, medical policy, authorization rules, and supplier network.
- Patient preferences, address, language, consent, and caregiver availability.
- Camera frames, LiDAR measurements, device readings, and patient responses.

### Downstream actions

- DME and supply orders prepared for clinician signature.
- Pharmacy and supplier fulfillment.
- Home-health, nursing, OT, PT, social-work, or care-management referrals.
- Transportation and follow-up scheduling.
- Prior-authorization and medical-necessity packages.
- Patient-paid or sponsored safety-product fulfillment.
- Care-team inbox messages and exception queues.
- FHIR write-back and longitudinal completion status.

### The upstream feedback loop

Relay must also send real-world evidence back into clinical planning. If the home, caregiver, affordability, or patient condition makes the original plan infeasible, the correct outcome may be to change that plan before discharge—not simply push harder on downstream fulfillment.

---

## Escalation pathways

| Level | Example | Relay behavior | Destination |
|---|---|---|---|
| Routine execution | Existing covered walker order is complete | Route and confirm fulfillment | Approved supplier |
| Documentation exception | Medical necessity or signature is missing | Draft missing material and request approval | Prescribing clinician |
| Operational exception | Supplier cannot deliver before discharge | Surface alternative suppliers and timing | Discharge coordinator |
| Clinical exception | Equipment does not fit or symptoms are worsening | Pause execution and escalate with evidence | OT, RN, or physician |
| Social exception | Patient cannot afford an item or has no caregiver | Identify benefits and community options | Social work or care manager |
| Urgent safety event | Possible infection, respiratory distress, or fall with injury | Follow a predefined urgent-response protocol | Nurse triage or emergency services |

Every escalation should contain:

- What was expected.
- What Relay observed.
- Why it matters for this patient.
- What has already been attempted.
- The recommended next action.
- The person or team responsible.
- The response deadline.

---

## Evaluation using Lightspeed’s high-impact agentic-AI framework

### Value

| Criterion | Assessment |
|---|---|
| **Repeatable** | Strong. Every encounter generates follow-up obligations, and the same categories of failure recur across patients. |
| **ROI** | Strongest for organizations bearing utilization risk. Relay also saves expensive care-coordination labor. |
| **Logic-based** | Strong. Coverage, documentation, routing, scheduling, completion, and escalation contain explicit rules even when evidence is unstructured. |

### Suitability

| Criterion | Assessment |
|---|---|
| **Data structure** | Excellent AI fit: clinical text, conversations, images, measurements, policies, and structured FHIR data. |
| **Data availability** | Good but fragmented across Abridge, the EHR, payer systems, suppliers, patients, and caregivers. |
| **Data durability** | Potentially excellent. The proprietary dataset is the link between plan, barrier, intervention, fulfillment, and outcome—not merely another collection of notes. |

### Feasibility

| Criterion | Assessment |
|---|---|
| **Technology** | Feasible today for the Monica workflow using chart grounding, multimodal perception, voice, spatial measurement, and structured actions. |
| **Trust and safety** | Manageable through evidence, provenance, scoped autonomy, deterministic rules, approval gates, and explicit escalation. |
| **Integration** | The hardest dimension and the eventual moat. Benefits, ordering, scheduling, fulfillment, and write-back matter more than adding another model. |

The strongest evidence that this is a high-impact agent idea is that the agent is not just generating content. It is coordinating a repeatable, multi-system workflow with measurable completion and economic consequences.

---

## Product boundaries and guardrails

Relay should:

- Separate chart facts, patient-reported information, sensor evidence, model inference, and demo assumptions.
- Show evidence and source provenance for every material finding.
- Use clinical standards such as CDC STEADI where applicable.
- Keep orders, referrals, and care-plan changes in draft until the correct authority approves them.
- Never invent insurance coverage, urgency, or a numerical risk score.
- Route urgent symptoms through predefined clinical protocols rather than open-ended model judgment.
- Record what was completed, declined, unavailable, or escalated.
- Minimize the patient and caregiver burden required to close the loop.

Relay does not replace a clinician, occupational therapist, or care manager. It extends their reach and reserves human attention for decisions and exceptions.

---

## Why this can become a platform

Monica demonstrates home readiness, but the underlying agent loop generalizes:

| Encounter | Post-encounter obligation | Relay workflow |
|---|---|---|
| SNF or hospital discharge | Safe home setup and DME | Home walkthrough, benefits verification, fulfillment, escalation |
| Surgery | Wound care, supplies, symptom monitoring | Guided check-ins, visual evidence, red-flag escalation |
| New medication | Obtain and correctly use medication | Pharmacy verification, education, adherence and side-effect check |
| Chronic disease visit | Monitor vitals and complete follow-up | Device/supply confirmation, readings, appointment coordination |
| Prenatal or postpartum care | Monitor symptoms and access support | Structured check-ins, supply and transportation coordination, escalation |
| Specialty referral | Complete testing and consultation | Scheduling, authorization, preparation, and closed-loop result confirmation |

The common primitive is not fall prevention. It is **care-plan execution under real-world constraints**.

---

## Final elevator pitch

Every clinical encounter ends with a plan, but the care team usually loses visibility once the patient leaves. The chart says what should happen; it rarely shows whether the patient understood it, could afford it, received the necessary equipment, or had a home and support system capable of carrying it out.

**Relay is a chart-aware agent that carries the care plan into the patient’s real world.** It translates the encounter into follow-up obligations, gathers evidence from the patient, caregiver, home, payer, and supplier network, and advances each action until it is completed or escalated to the right human.

For Monica, a 76-year-old leaving skilled nursing rehabilitation, Relay becomes a home-readiness agent. Her caregiver walks the apartment with an iPad. Relay combines her chart, a guided conversation, camera evidence, and LiDAR measurements to identify hazards and test whether the discharge plan is physically possible.

It does not merely say, “That doorway looks narrow.”

It says:

> **“The bathroom doorway is 27 inches. Monica’s walker is 28. The current discharge plan will not work.”**

Relay then determines what is covered, prepares the required order or referral for approval, routes it to the appropriate supplier or care team, confirms fulfillment, and escalates anything that cannot be resolved before discharge.

Monica’s walkthrough is the first workflow, not the product boundary. The larger opportunity is to make every care plan observable and executable after the patient leaves—so healthcare can respond to what is actually happening, not simply what was written in the chart.

> **Abridge captures the encounter. Relay carries the care forward.**

