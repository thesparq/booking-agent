# Salon Booking Agent: Production Architecture & roc-golem Dogfooding Plan

## Executive Summary

The **Salon Booking Agent** serves as a commercial solution for hair salons and the flagship dogfooding application for the **`roc-golem`** platform. By implementing advanced salon workflows (stylist scheduling, no-show reduction, waitlist auto-fill, and deposit handling), we test and validate `roc-golem`'s core primitives: **durable state persistence**, **zero-serialization read paths (`readOnly`)**, **durable timers (`rpcSchedule`)**, **durable promises & webhooks**, **opaque secret management**, and **multi-agent bundling (`bundleAll`)**.

---

## 1. Multi-Agent Component Architecture

We bundle three distinct agents into a single WebAssembly component using `bundleAll`:

1. **`booking-coordinator`** (`BookingCoordinator.roc`):
   - **Mode**: Stateful / Durable
   - **State**: Stylist roster, calendar slots, appointment ledger, waitlist queue, booking wizard steps.
   - **Tools & Methods**:
     - `get_services`: Read-only service catalog & pricing.
     - `get_salon_info`: Read-only hours, address, contact details.
     - `get_stylists`: Read-only list of stylists, specialties, and tiers.
     - `check_availability`: Dynamic open slots filtered by stylist or date.
     - `book_appointment`: Stateful booking creation with confirmation code generation.
     - `cancel_appointment`: Stateful cancellation, freeing slots and triggering waitlist processing.
     - `get_daily_manifest`: Salon owner daily agenda and projected gross revenue.
     - `handle-message`: Conversational multi-turn booking wizard.

2. **`notification-dispatcher`** (`NotificationDispatcher.roc`):
   - **Mode**: Stateful / Durable
   - **Responsibility**: Manages outbound messaging to Meta WhatsApp Business API and SMS gateways.
   - **Features**: Rate-limited queue, retry with exponential backoff, and host-mediated HTTP authorization using `SecretHandle`.

3. **`salon-analytics`** (`SalonAnalytics.roc`):
   - **Mode**: Ephemeral
   - **Responsibility**: Computes analytics on-demand without storing internal state:
     - Stylist utilization rate ($%$)
     - Cancellation rate ($%$)
     - Projected daily/weekly revenue
     - Popular service breakdowns

---

## 2. High-Impact Feature Specifications

### 2.1 Stylist Selection & Multi-Resource Calendars
- Supports booking with a specific stylist (e.g. *"Balayage with Sarah"*) or *"Any available stylist"*.
- Tracks individual stylist calendars to prevent double-booking.
- Stylist tiering (Junior, Senior, Master) with tier-specific service assignments.

### 2.2 Scheduled Reminders & No-Show Reduction (`rpcSchedule`)
- Automatically schedules 24-hour and 2-hour reminders upon appointment confirmation.
- Uses Golem's durable scheduler (`rpcSchedule`) to sleep workers with zero memory/compute billing until wakeup.
- Automatically handles cancellation edge cases (cancelling an appointment deactivates its reminder callback).

### 2.3 Deposit Links & Durable Promises (`createPromise` / `createWebhook`)
- High-ticket services ($100+) require a deposit to hold the slot.
- Generates a Stripe Checkout session with a webhook callback hooked to a Golem durable promise.
- Enforces a 15-minute hold: if unpaid, the slot automatically returns to the open calendar.

### 2.4 Waitlist Auto-Fill
- When a customer cancels, the agent scans the waitlist queue for matching requests.
- Auto-dispatches an opening notification to the first candidate with a 10-minute claim window.

### 2.5 Salon Owner Daily Manifest
- Read-only method returning daily appointments, staff schedule, and revenue estimates.
- Accessible via chat command (`"today's schedule"`) or administrative tool call.

### 2.6 Operating Hours & Date Validation (`Effect.now`)
- Uses live host time to validate requested appointments against salon operating hours.
- Rejects requests for past dates or closed days (e.g., Sundays).

---

## 3. WhatsApp Cloud API Integration Blueprint

- **Webhook Handshake (`GET`)**: Verifies `hub.verify_token` against an opaque secret handle and returns `hub.challenge`.
- **Message Ingestion (`POST`)**: Ingests customer texts and interactive button clicks from Meta's webhook.
- **Outbound HTTP Dispatch**: Dispatches replies via Golem host-mediated HTTP using `SecretHandle("META_WHATSAPP_TOKEN")`, keeping raw credentials out of guest memory and oplogs.

---

## 4. `roc-golem` Platform Dogfooding Matrix

| Platform Subsystem | Dogfooding Focus | Validation Criteria |
|---|---|---|
| **Multi-Agent Bundling (`bundleAll`)** | Bundling 3 distinct agents (`BookingCoordinator`, `NotificationDispatcher`, `SalonAnalytics`). | WIT routing correctly partitions methods without memory corruption or state bleed across agent types. |
| **Durable Timers (`rpcSchedule`)** | Scheduling 24h/2h reminders and 15m hold releases. | Workers wake up accurately from sleep across restarts with correct payload delivery. |
| **Durable Promises (`createPromise`)** | Asynchronous payment confirmation from webhooks. | External webhooks complete promises and resume waiting agent workflows. |
| **Opaque Secrets (`SecretHandle`)** | Outbound HTTP headers for Meta & Stripe. | Bearer tokens injected into WASI HTTP requests without appearing in guest memory. |
| **Read-Only Bypass (`readOnly`)** | High-volume calendar queries (`check_availability`). | Verification that read queries execute in $O(1)$ without creating oplog entries. |
| **Host Time (`Effect.now`)** | Operating hours and past-time booking gate. | Accurate UTC millisecond retrieval under Component Model WASI. |
