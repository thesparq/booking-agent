// Luxe Hair Studio — WhatsApp AI Concierge & Salon Operations Client
// Powered by roc-golem on Golem Cloud

const chatCanvas = document.getElementById('chatCanvas');
const messageInput = document.getElementById('messageInput');
const agentStatus = document.getElementById('agentStatus');
const backstagePane = document.getElementById('backstagePane');

// In-Memory Salon Backstage State (Synced with Roc Golem Multi-Agent Bundle)
let salonState = {
  stylists: [
    { id: 1, name: "Sarah Jenkins", tier: "Master Stylist", specialty: "Balayage, Color Correction, Precision Cuts" },
    { id: 2, name: "Marcus Vance", tier: "Senior Stylist", specialty: "Men's Grooming, Texturizing, Fade Mastery" },
    { id: 3, name: "Elena Rostova", tier: "Senior Stylist", specialty: "Keratin Treatments, Silk Press, Bridal Updos" },
    { id: 4, name: "Chloe Bennett", tier: "Junior Stylist", specialty: "Blowouts, Scalp Treatments, Single Process" },
  ],
  services: [
    { name: "Women's Cut & Blowdry", price: 65, duration: 60, depositRequired: false },
    { name: "Men's Cut & Style", price: 40, duration: 45, depositRequired: false },
    { name: "Single Process Color", price: 90, duration: 90, depositRequired: false },
    { name: "Balayage & Highlights", price: 160, duration: 150, depositRequired: true },
    { name: "Keratin Smoothing Treatment", price: 200, duration: 120, depositRequired: true },
  ],
  availableSlots: [
    "Today 2:00 PM",
    "Today 3:30 PM",
    "Tomorrow 10:00 AM",
    "Tomorrow 2:00 PM",
    "Friday 1:00 PM"
  ],
  appointments: [
    { code: "#LUXE-101", customer: "Sophia Taylor", stylist: "Sarah Jenkins", service: "Women's Cut & Blowdry", slot: "Today 10:00 AM", price: 65, status: "Confirmed" },
    { code: "#LUXE-102", customer: "James Wilson", stylist: "Marcus Vance", service: "Men's Cut & Style", slot: "Today 11:30 AM", price: 40, status: "Confirmed" },
  ],
  holds: [],
  reminders: [
    { id: "REM-001", code: "#LUXE-101", recipient: "Sophia Taylor", service: "Women's Cut & Blowdry", stylist: "Sarah Jenkins", delayMs: 86400000, status: "Scheduled" },
    { id: "REM-002", code: "#LUXE-102", recipient: "James Wilson", service: "Men's Cut & Style", stylist: "Marcus Vance", delayMs: 86400000, status: "Scheduled" }
  ],
  waitlist: [
    { customer: "Amanda Reed", service: "Balayage & Highlights", preferredSlot: "Today 2:00 PM", phone: "+1 (555) 432-8765" }
  ],
  notifications: [
    { id: "NOTIF-01", recipient: "+1 (555) 234-9871", message: "Booking confirmed: Sophia Taylor #LUXE-101 for Women's Cut", channel: "WhatsApp", status: "Delivered" },
    { id: "NOTIF-02", recipient: "+1 (555) 987-1234", message: "Booking confirmed: James Wilson #LUXE-102 for Men's Cut", channel: "WhatsApp", status: "Delivered" }
  ]
};

// Format current time HH:MM AM/PM
function formatTime(date = new Date()) {
  return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

// Render Initial WhatsApp Business Welcome Message
function initWhatsAppChat() {
  const welcomeText = 
`✨ *Welcome to Luxe Hair Studio!*
I am your 24/7 AI salon concierge powered by *roc-golem* on Golem Cloud.

How can I pamper you today?
• 💇‍♀️ *Services & Prices* — View our full menu
• 📅 *Available Slots* — Check stylist openings
• ✂️ *Meet Stylists* — Discover our specialists
• ✨ *Book an Appointment* — Secure your chair`;

  appendMessage('in', welcomeText, {
    showQuickButtons: true,
    buttons: [
      { text: "💇‍♀️ View Services", action: "What services and prices do you offer?" },
      { text: "📅 Available Slots", action: "What time slots are available?" },
      { text: "✂️ Meet Stylists", action: "Who are your stylists?" }
    ]
  });

  refreshBackstageData();
}

// Append WhatsApp Message Bubble
function appendMessage(direction, text, options = {}) {
  const row = document.createElement('div');
  row.className = `msg-row ${direction}`;

  const bubble = document.createElement('div');
  bubble.className = 'wa-bubble';

  // Format bold markdown (*bold* -> <strong>) and linebreaks
  const formattedText = escapeHtml(text)
    .replace(/\*([^*]+)\*/g, '<strong>$1</strong>')
    .replace(/\n/g, '<br/>');

  bubble.innerHTML = formattedText;

  // Add interactive cards if specified
  if (options.card) {
    bubble.appendChild(options.card);
  }

  // Add interactive buttons if specified
  if (options.buttons && options.buttons.length > 0) {
    const actionsBox = document.createElement('div');
    actionsBox.className = 'wa-card-actions';
    options.buttons.forEach(btn => {
      const b = document.createElement('button');
      b.className = `wa-action-btn ${btn.isPay ? 'pay-btn' : ''}`;
      b.innerHTML = btn.text;
      b.onclick = () => handleQuickSend(btn.action);
      actionsBox.appendChild(b);
    });
    bubble.appendChild(actionsBox);
  }

  // Bubble metadata (time & checkmarks)
  const meta = document.createElement('div');
  meta.className = 'bubble-meta';
  meta.innerHTML = `
    <span>${formatTime()}</span>
    ${direction === 'out' ? '<span class="wa-ticks">✓✓</span>' : ''}
  `;
  bubble.appendChild(meta);

  row.appendChild(bubble);
  chatCanvas.appendChild(row);
  chatCanvas.scrollTop = chatCanvas.scrollHeight;
}

// Quick action chip handler
function handleQuickSend(prompt) {
  if (!prompt) return;
  sendUserMessage(prompt);
}

// Submit message from input bar
function submitMessage() {
  const text = messageInput.value.trim();
  if (!text) return;
  messageInput.value = '';
  sendUserMessage(text);
}

// Main message sender pipeline
async function sendUserMessage(text) {
  // Render customer bubble immediately
  appendMessage('out', text);

  // Show WhatsApp typing indicator in header
  setAgentStatus("typing...");

  try {
    // Attempt live Golem Cloud native HTTP API call
    const response = await fetch('http://salon.localhost:9006/api/whatsapp/api/booking-coordinator/handle-message', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ input: text })
    });

    if (response.ok) {
      const data = await response.json();
      setTimeout(() => {
        setAgentStatus("online");
        const replyText = typeof data === 'string' ? data : (data.reply || data.response || JSON.stringify(data));
        processAgentResponse(replyText);
        refreshBackstageData();
      }, 350);
      return;
    }
  } catch (e) {
    // Fallback to high-fidelity in-browser engine (mirrors Roc domain logic)
  }

  setTimeout(() => {
    setAgentStatus("online");
    const simulated = simulateRocAgent(text);
    processAgentResponse(simulated.reply, simulated.options);
    refreshBackstageData();
  }, 600);
}

// Process and format Agent Response into WhatsApp Cards
function processAgentResponse(replyText, options = {}) {
  // Check if response contains deposit hold / mock checkout link
  if (replyText.includes("Mock Checkout URL:") || replyText.includes("A $30 deposit is required")) {
    const codeMatch = replyText.match(/#LUXE-10\d/);
    const code = codeMatch ? codeMatch[0] : "#LUXE-103";
    
    const card = document.createElement('div');
    card.className = 'wa-card';
    card.innerHTML = `
      <div class="wa-card-header">
        <span>💳 Provisional Hold Created</span>
        <span class="wa-badge-pending">Pending $30 Deposit</span>
      </div>
      <div class="wa-card-body">
        <div class="wa-card-meta-row">
          <span>Booking Reference:</span>
          <strong>${code}</strong>
        </div>
        <div class="wa-card-meta-row">
          <span>Deposit Required:</span>
          <strong style="color:var(--wa-gold-accent)">$30.00</strong>
        </div>
        <div class="wa-card-meta-row">
          <span>Hold Expiration:</span>
          <span style="color:#ffd279;">15 minutes (Durable Promise)</span>
        </div>
        <div style="margin-top:8px; font-size:11.5px; color:var(--wa-text-secondary);">
          Slots for high-value services are provisionally held. Tap below to simulate completing Stripe Checkout:
        </div>
      </div>
    `;

    appendMessage('in', replyText, {
      card: card,
      buttons: [
        { text: `💳 Complete $30 Deposit (${code})`, action: `pay deposit ${code}`, isPay: true }
      ]
    });
    return;
  }

  // Check if booking is confirmed
  if (replyText.includes("Appointment confirmed with code") || replyText.includes("Deposit confirmed!")) {
    const codeMatch = replyText.match(/#LUXE-10\d/);
    const code = codeMatch ? codeMatch[0] : "#LUXE-101";

    const card = document.createElement('div');
    card.className = 'wa-card';
    card.innerHTML = `
      <div class="wa-card-header" style="color:var(--wa-green-accent);">
        <span>✅ Booking Confirmed</span>
        <span class="wa-badge-confirmed">Confirmed</span>
      </div>
      <div class="wa-card-body">
        <div class="wa-card-meta-row">
          <span>Confirmation Code:</span>
          <strong style="color:var(--wa-green-accent);">${code}</strong>
        </div>
        <div class="wa-card-meta-row">
          <span>Calendar Event:</span>
          <span>Added to Salon Schedule</span>
        </div>
        <div class="wa-card-meta-row">
          <span>Durable Reminder:</span>
          <span>Scheduled 24h prior via rpcSchedule</span>
        </div>
      </div>
    `;

    appendMessage('in', replyText, { card });
    return;
  }

  // Default text response
  appendMessage('in', replyText, options);
}

// In-Browser High-Fidelity Simulator (Exact Match to Roc BookingCoordinator & Multi-Agent Bundle)
function simulateRocAgent(input) {
  const lower = input.toLowerCase().trim();

  // 1. Services & Pricing
  if (lower.includes("service") || lower.includes("price") || lower.includes("cost") || lower.includes("menu")) {
    const text = 
`💇‍♀️ *Luxe Hair Studio — Services & Pricing*

1. *Women's Cut & Blowdry* — $65 (60 mins)
2. *Men's Cut & Style* — $40 (45 mins)
3. *Single Process Color* — $90 (90 mins)
4. *Balayage & Highlights* — $160 (150 mins) • _$30 deposit required_
5. *Keratin Smoothing Treatment* — $200 (120 mins) • _$30 deposit required_

Would you like to book a cut, color, or treatment?`;

    return {
      reply: text,
      options: {
        buttons: [
          { text: "✨ Book Balayage ($160)", action: "I want to book Balayage with Sarah" },
          { text: "✂️ Book Women's Cut ($65)", action: "I want to book Women's Cut with Sarah" },
          { text: "💈 Book Men's Cut ($40)", action: "I want to book Men's Cut with Marcus" }
        ]
      }
    };
  }

  // 2. Available Slots
  if (lower.includes("slot") || lower.includes("available") || lower.includes("opening") || lower.includes("when")) {
    const slotsText = salonState.availableSlots.map((s, idx) => `• ${s}`).join("\n");
    return {
      reply: `📅 *Current Open Time Slots:*\n\n${slotsText}\n\nAll appointments include a complimentary beverage and consultation. Reply with your desired service, slot, and preferred stylist to book!`,
      options: {
        buttons: [
          { text: "Today 2:00 PM", action: "Book appointment Today 2:00 PM" },
          { text: "Tomorrow 10:00 AM", action: "Book appointment Tomorrow 10:00 AM" }
        ]
      }
    };
  }

  // 3. Stylists Discovery
  if (lower.includes("stylist") || lower.includes("who") || lower.includes("team") || lower.includes("staff")) {
    const teamText = salonState.stylists.map(s => `• *${s.name}* (${s.tier})\n  _${s.specialty}_`).join("\n\n");
    return {
      reply: `✂️ *Meet Our Artisans at Luxe Hair Studio:*\n\n${teamText}\n\nYou can request any stylist when scheduling!`
    };
  }

  // 4. Hours & Salon Info
  if (lower.includes("hour") || lower.includes("address") || lower.includes("location") || lower.includes("where") || lower.includes("info")) {
    return {
      reply: 
`📍 *Luxe Hair Studio*
742 Evergreen Terrace, Suite 101, Springfield

📞 *WhatsApp / Phone:* +1 (555) 234-5678
🕒 *Operating Hours:*
• Monday – Friday: 9:00 AM – 7:00 PM
• Saturday: 9:00 AM – 5:00 PM
• Sunday: Closed

🚗 *Parking:* Free dedicated customer parking in the rear lot.
☕ *Amenities:* Complimentary espresso, sparkling water, and salon Wi-Fi.`
    };
  }

  // 5. Booking Flow & Balayage Deposit Gate ($100+)
  if (lower.includes("book") || lower.includes("reserve") || lower.includes("balayage") || lower.includes("keratin") || lower.includes("cut")) {
    const isHighValue = lower.includes("balayage") || lower.includes("keratin") || lower.includes("160") || lower.includes("200");
    const serviceName = isHighValue ? (lower.includes("keratin") ? "Keratin Smoothing Treatment" : "Balayage & Highlights") : "Women's Cut & Blowdry";
    const price = isHighValue ? (lower.includes("keratin") ? 200 : 160) : 65;
    const stylistName = lower.includes("marcus") ? "Marcus Vance" : (lower.includes("elena") ? "Elena Rostova" : "Sarah Jenkins");
    const slot = salonState.availableSlots.length > 0 ? salonState.availableSlots[0] : "Tomorrow 2:00 PM";
    
    // Consume slot
    salonState.availableSlots = salonState.availableSlots.filter(s => s !== slot);

    const bookingNum = salonState.appointments.length + 1;
    const code = `#LUXE-10${bookingNum}`;

    if (isHighValue) {
      // Create provisional hold with durable promise
      const newAppt = { code, customer: "Client (Demo User)", stylist: stylistName, service: serviceName, slot, price, status: "PendingDeposit" };
      salonState.appointments.push(newAppt);

      const newHold = {
        code,
        promiseId: 1000 + bookingNum,
        webhookUrl: `https://api.golem.cloud/webhooks/mock_stripe_${code}`,
        amount: 30,
        status: "Pending",
        expiresInSec: 900
      };
      salonState.holds.push(newHold);

      return {
        reply: `Appointment provisionally held with code *${code}* for *Client* with *${stylistName}* (*${serviceName}*) at *${slot}*. Total: $${price}. A $30 deposit is required within 15 minutes to confirm booking. Mock Checkout URL: https://checkout.stripe.com/pay/cs_test_mock_${code}?deposit=30&code=${code}&webhook=${newHold.webhookUrl}`
      };
    } else {
      // Standard confirmation
      const newAppt = { code, customer: "Client (Demo User)", stylist: stylistName, service: serviceName, slot, price, status: "Confirmed" };
      salonState.appointments.push(newAppt);

      const newRem = {
        id: `REM-00${salonState.reminders.length + 1}`,
        code,
        recipient: "Client (Demo User)",
        service: serviceName,
        stylist: stylistName,
        delayMs: 86400000,
        status: "Scheduled"
      };
      salonState.reminders.push(newRem);

      salonState.notifications.push({
        id: `NOTIF-0${salonState.notifications.length + 1}`,
        recipient: "+1 (555) 987-6543",
        message: `Appointment confirmed: ${code} for ${serviceName} with ${stylistName}`,
        channel: "WhatsApp",
        status: "Delivered"
      });

      return {
        reply: `Appointment confirmed with code *${code}* for *Client* with *${stylistName}* (*${serviceName}*) at *${slot}*. Total: $${price}. Reminder ${newRem.id} scheduled via Golem *rpcSchedule*.`
      };
    }
  }

  // 6. Pay Deposit Simulation
  if (lower.includes("pay deposit") || lower.includes("confirm deposit") || (lower.startsWith("pay") && lower.includes("10"))) {
    const codeMatch = input.match(/#LUXE-10\d/i);
    const targetCode = codeMatch ? codeMatch[0].toUpperCase() : (salonState.holds.length > 0 ? salonState.holds[0].code : "#LUXE-103");

    // Update appointment status to Confirmed
    let matched = false;
    salonState.appointments.forEach(a => {
      if (a.code === targetCode || a.status === "PendingDeposit") {
        a.status = "Confirmed";
        matched = true;
      }
    });

    // Update hold status to Completed
    salonState.holds.forEach(h => {
      if (h.code === targetCode || h.status === "Pending") {
        h.status = "Completed";
      }
    });

    if (matched) {
      const remId = `REM-00${salonState.reminders.length + 1}`;
      salonState.reminders.push({
        id: remId,
        code: targetCode,
        recipient: "Client (Demo User)",
        service: "Balayage & Highlights",
        stylist: "Sarah Jenkins",
        delayMs: 86400000,
        status: "Scheduled"
      });

      salonState.notifications.push({
        id: `NOTIF-0${salonState.notifications.length + 1}`,
        recipient: "+1 (555) 987-6543",
        message: `Deposit received ($30.00). Booking ${targetCode} is now fully confirmed!`,
        channel: "WhatsApp",
        status: "Delivered"
      });

      return {
        reply: `🎉 *Deposit confirmed!* Stripe promise completed for *${targetCode}*. Your Balayage appointment is locked into Sarah Jenkins' schedule. 24h reminder *${remId}* has been set.`
      };
    }
  }

  // 7. Cancellation Flow & Waitlist Promotion
  if (lower.includes("cancel") || lower.includes("cancel appointment")) {
    const codeMatch = input.match(/#LUXE-10\d/i);
    const targetCode = codeMatch ? codeMatch[0].toUpperCase() : "#LUXE-101";

    let cancelledAppt = null;
    salonState.appointments = salonState.appointments.filter(a => {
      if (a.code === targetCode) {
        cancelledAppt = a;
        return false;
      }
      return true;
    });

    if (cancelledAppt) {
      // Release slot back or auto-promote waitlist
      if (salonState.waitlist.length > 0) {
        const nextPerson = salonState.waitlist.shift();
        const promoCode = `#LUXE-10${salonState.appointments.length + 1}`;
        salonState.appointments.push({
          code: promoCode,
          customer: nextPerson.customer,
          stylist: cancelledAppt.stylist,
          service: nextPerson.service,
          slot: cancelledAppt.slot,
          price: 160,
          status: "Confirmed"
        });

        salonState.notifications.push({
          id: `NOTIF-0${salonState.notifications.length + 1}`,
          recipient: nextPerson.phone,
          message: `Good news ${nextPerson.customer}! A slot opened at ${cancelledAppt.slot}. You have been auto-promoted (${promoCode})!`,
          channel: "WhatsApp",
          status: "Delivered"
        });

        return {
          reply: `Booking *${targetCode}* has been cancelled. Slot *${cancelledAppt.slot}* was released and *${nextPerson.customer}* from the waitlist was automatically promoted into the chair!`
        };
      } else {
        salonState.availableSlots.push(cancelledAppt.slot);
        return {
          reply: `Appointment *${targetCode}* has been successfully cancelled and slot *${cancelledAppt.slot}* returned to the available schedule.`
        };
      }
    } else {
      return {
        reply: `No active booking matching code *${targetCode}* was found. Please check your confirmation reference.`
      };
    }
  }

  // Default response
  return {
    reply: `Thank you for your message! You can ask me to view *"services"*, check *"available slots"*, meet our *"stylists"*, or say *"book Balayage with Sarah"* to experience the booking flow.`
  };
}

// Refresh Salon Staff Backstage View
function refreshBackstageData() {
  // Update KPIs
  let totalRevenue = 0;
  let confirmedCount = 0;
  let pendingCount = 0;

  salonState.appointments.forEach(a => {
    if (a.status === "Confirmed") {
      totalRevenue += a.price;
      confirmedCount += 1;
    } else if (a.status === "PendingDeposit") {
      pendingCount += 1;
    }
  });

  const kpiRev = document.getElementById('kpiRevenue');
  const kpiConf = document.getElementById('kpiConfirmed');
  const kpiHolds = document.getElementById('kpiPendingHolds');
  const kpiUtil = document.getElementById('kpiUtilization');

  if (kpiRev) kpiRev.textContent = `$${totalRevenue}`;
  if (kpiConf) kpiConf.textContent = confirmedCount;
  if (kpiHolds) kpiHolds.textContent = pendingCount;
  if (kpiUtil) {
    const totalSlots = confirmedCount + salonState.availableSlots.length;
    const util = totalSlots > 0 ? Math.round((confirmedCount / totalSlots) * 100) : 0;
    kpiUtil.textContent = `${util}%`;
  }

  // Render Manifest
  const manifestContainer = document.getElementById('manifestAppointmentsList');
  if (manifestContainer) {
    manifestContainer.innerHTML = salonState.appointments.map(a => `
      <div class="mini-log-item ${a.status === 'PendingDeposit' ? 'pending' : ''}">
        <div class="mini-log-row">
          <span class="mini-log-title">${a.code} — ${a.customer}</span>
          <span class="mini-log-title" style="color:var(--wa-gold-accent)">$${a.price}</span>
        </div>
        <div class="mini-log-row mini-log-sub">
          <span>${a.stylist} (${a.service})</span>
          <span style="font-weight:600; color:${a.status === 'Confirmed' ? '#00a884' : 'var(--wa-gold-accent)'}">${a.status}</span>
        </div>
        <div class="mini-log-sub" style="font-size:10px;">🕒 ${a.slot}</div>
      </div>
    `).join("") || `<div style="font-size:12px; color:#8696a0;">No appointments today.</div>`;
  }

  // Render Deposit Holds
  const holdsContainer = document.getElementById('depositHoldsList');
  if (holdsContainer) {
    holdsContainer.innerHTML = salonState.holds.map(h => `
      <div class="mini-log-item ${h.status === 'Pending' ? 'pending' : ''}">
        <div class="mini-log-row">
          <span class="mini-log-title">${h.code} — Promise #${h.promiseId}</span>
          <span style="color:var(--wa-gold-accent); font-weight:700;">$${h.amount}</span>
        </div>
        <div class="mini-log-sub" style="font-family:monospace; font-size:10px; word-break:break-all;">
          ${h.webhookUrl}
        </div>
        <div class="mini-log-row mini-log-sub" style="margin-top:2px;">
          <span>Status: <strong>${h.status}</strong></span>
          <span style="color:#ffd279;">15 min timer</span>
        </div>
      </div>
    `).join("") || `<div style="font-size:12px; color:#8696a0;">No active deposit holds.</div>`;
  }

  // Render Reminders
  const remindersContainer = document.getElementById('remindersList');
  if (remindersContainer) {
    remindersContainer.innerHTML = salonState.reminders.map(r => `
      <div class="mini-log-item">
        <div class="mini-log-row">
          <span class="mini-log-title">${r.id} (${r.code})</span>
          <span style="color:var(--wa-green-accent);">${r.status}</span>
        </div>
        <div class="mini-log-sub">${r.recipient} with ${r.stylist}</div>
        <div class="mini-log-sub" style="font-size:10px;">Target delay: ${r.delayMs / 1000}s</div>
      </div>
    `).join("") || `<div style="font-size:12px; color:#8696a0;">No reminders logged.</div>`;
  }

  // Render Notifications
  const notifContainer = document.getElementById('notificationsList');
  if (notifContainer) {
    notifContainer.innerHTML = salonState.notifications.map(n => `
      <div class="mini-log-item">
        <div class="mini-log-row">
          <span class="mini-log-title">${n.channel}: ${n.recipient}</span>
          <span style="color:#53bdeb;">${n.status}</span>
        </div>
        <div class="mini-log-sub">${n.message}</div>
      </div>
    `).join("") || `<div style="font-size:12px; color:#8696a0;">Outbox is clear.</div>`;
  }
}

// Toggle Salon Backstage Drawer
function toggleBackstage() {
  if (backstagePane) {
    backstagePane.classList.toggle('collapsed');
  }
}

// Set status indicator in WhatsApp header
function setAgentStatus(statusText) {
  if (!agentStatus) return;
  agentStatus.textContent = statusText;
  if (statusText === 'typing...') {
    agentStatus.className = 'wa-status typing';
  } else {
    agentStatus.className = 'wa-status';
  }
}

// Reset chat history for client pitches
function resetChatHistory() {
  if (confirm("Reset WhatsApp chat history for demo presentation?")) {
    chatCanvas.innerHTML = `
      <div class="wa-date-divider">Today</div>
      <div class="wa-security-banner">
        <span>🔒</span>
        <span>Messages and calls are end-to-end encrypted. No one outside of this chat, not even WhatsApp, can read or listen to them.</span>
      </div>
    `;
    initWhatsAppChat();
  }
}

// Helper: Escape HTML
function escapeHtml(str) {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

// Listen for enter key in message box
messageInput.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') {
    e.preventDefault();
    submitMessage();
  }
});

// Launch on page load
window.addEventListener('DOMContentLoaded', () => {
  initWhatsAppChat();
});
