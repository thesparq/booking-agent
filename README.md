<img src="assets/icon.svg" width="64" height="64" alt="">

# Luxe Hair Studio — Industrial Multi-Agent Salon System

An industrial-grade, multi-agent salon booking and operations application built in **Roc** on **Golem Cloud** ([github.com/thesparq/roc-golem](https://github.com/thesparq/roc-golem)), demonstrating durable execution, WebAssembly componentization, multi-agent bundling, durable timers, durable promises, and Meta WhatsApp Cloud API webhooks.

---

## 🌟 Architecture: Bundled Multi-Agent

The WebAssembly component (`build/booking_agent.wasm`, 1.7MB) bundles three specialized agents via `bundleAll` and `erase` in [`src/main.roc`](file:///home/thesparq/.t3/projects/booking-agent/src/main.roc):

1. **`BookingCoordinator` (`booking-coordinator`) — Stateful / Durable**:
   - Multi-stylist calendar with tiered specialists (Master, Senior, Junior).
   - Conversational booking wizard with stylist filtering and smart slot deduction.
   - Deposit gate for high-value services ($100+, such as Balayage $160 and Keratin $200) holding slots for 15 minutes.
   - Durable promises (`createPromise`, `completePromise`) with external webhooks (`createWebhook`) for mock Stripe checkout callbacks.
   - Durable timer reminders (`schedule_reminder`, `send_reminder`) via `rpcSchedule`.
   - Automatic waitlist promotion on cancellation or expired deposit holds.
   - Dynamic HTTP mount (`withHttpMount`) for `/api/whatsapp/webhook`.
2. **`NotificationDispatcher` (`notification-dispatcher`) — Stateful / Durable**:
   - Outbound WhatsApp and SMS delivery queue with audit history and status metrics.
3. **`SalonAnalytics` (`salon-analytics`) — Stateless / Ephemeral**:
   - On-demand calculation of seat utilization, cancellation rates, and stylist projected revenue.

---

## 📁 Repository Structure

```
booking-agent/
├── data/
│   └── business.json           # Salon profile, services, prices, and hours
├── frontend/
│   ├── index.html              # Chat concierge UI
│   ├── style.css               # Modern dark-mode salon styling
│   └── app.js                  # Frontend client & chat handler
├── src/
│   ├── main.roc                # Multi-agent bundle entrypoint (bundleAll)
│   ├── BookingCoordinator.roc  # Stateful coordinator, calendar & webhooks
│   ├── NotificationDispatcher.roc # Outbound notification queue & audit log
│   └── SalonAnalytics.roc      # Ephemeral KPI and financial worker
├── build/
│   └── booking_agent.wasm      # Golem Component Model binary (1.7MB)
├── golem.yaml                  # Golem 1.6 component manifest
├── build.sh                    # Multi-agent WASM build script
├── PROGRESS.md                 # Full milestone progress tracker
└── README.md                   # System documentation
```

---

## 🔨 Building the Component

Ensure `roc` and `wasm-tools` are installed on your Linux system, then run:

```bash
./build.sh
```

Or invoke Golem's CLI:

```bash
golem build
```

This compiles `src/main.roc` to core WebAssembly with `roc build --target=wasm32`, links it against the precompiled `libroc_golem_host.a` from `roc-golem` v1.4.1, and componentizes it into `build/booking_agent.wasm`. Fast incremental builds skip recompilation when Roc source files are unchanged.

---

## 📱 Interactive WhatsApp Simulator & Salon Operations Demo (For Client Pitches)

To immediately demo the system to salon owners and clients without setting up a Meta developer account or WhatsApp Business verification, launch the built-in HTTP demo server:

```bash
python3 server.py 8080
```

Open **`http://localhost:8080`** in your browser.

### Features in the Pitch Demo:
1. **WhatsApp Web Interface**:
   - Official Business Account badge with verified green checkmark (`✓`).
   - Signature WhatsApp dark theme (`#111b21` / `#202c33`), doodle chat wallpaper, and end-to-end encryption banner.
   - Speech bubbles with timestamps and blue double checkmarks (`✓✓`).
   - Quick action pills for instantaneous client exploration.
   - Interactive message cards:
     - **Services & Prices** catalog cards with duration.
     - **Balayage / Keratin Deposit Gate**: Shows provisional slot hold and generates a clickable **`💳 Pay $30 Deposit via Stripe`** button.
     - **Booking Confirmation Card**: Confirmation code (`#LUXE-103`), stylist assignment, and 24h reminder confirmation.
2. **Salon Operations Backstage Drawer** (Toggle with `[🖥️ Salon Backstage]` button):
   - **Real-Time KPIs**: Projected revenue, seat utilization rate, confirmed bookings, and active deposit holds.
   - **Today's Daily Manifest**: Live timeline of salon appointments and stylist assignments.
   - **Deposit Holds Pipeline**: 15-minute countdown timer, durable promise IDs, and webhook endpoints.
   - **Durable 24h Reminders Log**: `rpcSchedule` timer status (`Scheduled`, `Dispatched`).
   - **Notification Dispatcher Outbox**: Outbound WhatsApp notifications queue and delivery history.
   - **Live Refresh & Reset**: Button to reset state or refresh live metrics during client presentations.

---

## 🚀 Testing Invocations via CLI

### 1. Multi-Stylist Discovery & Availability:
```bash
# Query team specialties
golem agent invoke 'booking-coordinator()' get_stylists

# Query slots filtered by stylist
golem agent invoke 'booking-coordinator()' check_availability '{"stylist": "sarah"}'
```

### 2. Operating Hours Host Effect (`Effect.now`):
```bash
golem agent invoke 'booking-coordinator()' check_operating_hours
```

### 3. Booking with Stripe Deposit Hold ($100+ Services):
```bash
# Book Balayage ($160) - triggers $30 deposit hold
golem agent invoke 'booking-coordinator()' book_appointment '["Alice Smith", "Balayage & Highlights", "Today 2:00 PM", "sarah"]'

# View active deposit holds & mock Stripe checkout links
golem agent invoke 'booking-coordinator()' get_holds

# Simulate customer paying deposit
golem agent invoke 'booking-coordinator()' confirm_deposit '{"code": "#LUXE-103"}'
```

### 4. Durable Reminders (`rpcSchedule`):
```bash
# Schedule a reminder to fire after 5 seconds (5000 ms)
golem agent invoke 'booking-coordinator()' schedule_reminder '{"code": "#LUXE-101", "delayMs": 5000}'

# Query scheduled and dispatched reminders
golem agent invoke 'booking-coordinator()' get_reminders
```

### 5. Meta WhatsApp Cloud API Webhook:
```bash
# Meta GET Verification Challenge Handshake
golem agent invoke 'booking-coordinator()' whatsapp_webhook '"hub.mode=subscribe&hub.challenge=1158201444&hub.verify_token=luxe_salon_secret_token"'

# Inbound Customer Message (POST)
golem agent invoke 'booking-coordinator()' whatsapp_webhook '{"entry":[{"changes":[{"value":{"messages":[{"from":"15559876543","text":{"body":"I want to book an appointment with Sarah"}}]}}]}]}'

# Outbound Dispatch via SecretHandle
golem agent invoke 'booking-coordinator()' dispatch_whatsapp '{"recipient": "+1 (555) 987-6543", "message": "Your booking #LUXE-101 is confirmed!"}'
```

### 6. Daily Operations Manifest:
```bash
golem agent invoke 'booking-coordinator()' get_daily_manifest
```

---

## 🔒 Security: Opaque Secret Handles

Outbound WhatsApp requests utilize Golem Cloud's `SecretHandle`:
- Secret key: `getSecretHandle("META_WHATSAPP_TOKEN")`
- Injected via `SecretHeader`: `Authorization: Bearer <TOKEN>`
- The raw credential never enters WebAssembly guest memory or oplog traces.
