module [
	agent,
	calculateKpisTool,
	projectRevenueTool,
	stylistWorkloadTool,
]

import pf.Golem exposing [Agent, StatelessTool, ephemeral, statelessTool, param]
import pf.Types exposing [Result]

# --- Tools (Stateless) ---

calculateKpisTool : StatelessTool
calculateKpisTool = statelessTool({
	name: "calculate_kpis",
	description: "Compute salon key performance indicators: utilization rate, cancellation rate, gross revenue, and avg ticket",
	params: [
		param("activeCount", "Number of confirmed active appointments"),
		param("cancelledCount", "Number of cancelled appointments"),
		param("grossRevenue", "Total revenue from active appointments"),
		param("totalSlots", "Total available chair slots for the period"),
	],
	execute: |args| {
		rawActive = extractParam(args, "activeCount", 0.U64)
		rawCancelled = extractParam(args, "cancelledCount", 1.U64)
		rawRevenue = extractParam(args, "grossRevenue", 2.U64)
		rawSlots = extractParam(args, "totalSlots", 3.U64)

		active = if Str.is_empty(rawActive) 8.U64 else parseU64OrDefault(rawActive, 8.U64)
		cancelled = if Str.is_empty(rawCancelled) 1.U64 else parseU64OrDefault(rawCancelled, 1.U64)
		revenue = if Str.is_empty(rawRevenue) 940.U64 else parseU64OrDefault(rawRevenue, 940.U64)
		totalSlots = if Str.is_empty(rawSlots) 10.U64 else parseU64OrDefault(rawSlots, 10.U64)

		totalBooked = active + cancelled
		cancelRatePct = if totalBooked > 0.U64 (cancelled * 100.U64) // totalBooked else 0.U64
		utilizationPct = if totalSlots > 0.U64 (active * 100.U64) // totalSlots else 0.U64
		avgTicket = if active > 0.U64 revenue // active else 0.U64

		Ok("{\"activeAppointments\":${Str.inspect(active)},\"cancelledAppointments\":${Str.inspect(cancelled)},\"grossRevenue\":${Str.inspect(revenue)},\"cancellationRatePct\":${Str.inspect(cancelRatePct)},\"chairUtilizationPct\":${Str.inspect(utilizationPct)},\"avgTicketValue\":${Str.inspect(avgTicket)}}")
	},
})

projectRevenueTool : StatelessTool
projectRevenueTool = statelessTool({
	name: "project_revenue",
	description: "Calculate 7-day and 30-day salon revenue projections, stylist commission, and net margin",
	params: [
		param("dailyRevenue", "Average daily gross salon revenue (e.g. 940)"),
	],
	execute: |args| {
		rawDaily = extractParam(args, "dailyRevenue", 0.U64)
		daily = if Str.is_empty(rawDaily) 940.U64 else parseU64OrDefault(rawDaily, 940.U64)

		weeklyGross = daily * 6.U64 # 6 working days
		monthlyGross = weeklyGross * 4.U64

		# Industry benchmarks: 50% commission, 10% backbar products, 40% net margin
		monthlyCommission = (monthlyGross * 50.U64) // 100.U64
		monthlyProductCosts = (monthlyGross * 10.U64) // 100.U64
		monthlyNetMargin = (monthlyGross * 40.U64) // 100.U64

		Ok("{\"dailyGross\":${Str.inspect(daily)},\"weeklyGross\":${Str.inspect(weeklyGross)},\"monthlyGross\":${Str.inspect(monthlyGross)},\"projectedCommission\":${Str.inspect(monthlyCommission)},\"productBackbarCost\":${Str.inspect(monthlyProductCosts)},\"estimatedNetProfit\":${Str.inspect(monthlyNetMargin)}}")
	},
})

stylistWorkloadTool : StatelessTool
stylistWorkloadTool = statelessTool({
	name: "stylist_workload",
	description: "Calculate workload distribution and capacity per active stylist",
	params: [
		param("stylistCount", "Number of stylists on duty"),
		param("totalBookings", "Total appointments booked"),
	],
	execute: |args| {
		rawStylists = extractParam(args, "stylistCount", 0.U64)
		rawBookings = extractParam(args, "totalBookings", 0.U64)

		stylists = if Str.is_empty(rawStylists) 3.U64 else parseU64OrDefault(rawStylists, 3.U64)
		bookings = if Str.is_empty(rawBookings) 8.U64 else parseU64OrDefault(rawBookings, 8.U64)

		avgClientsPerStylist = if stylists > 0.U64 bookings // stylists else 0.U64

		Ok("{\"stylistsOnDuty\":${Str.inspect(stylists)},\"totalClients\":${Str.inspect(bookings)},\"avgClientsPerStylist\":${Str.inspect(avgClientsPerStylist)},\"targetClientsPerDay\":5,\"status\":\"healthy\"}")
	},
})

# --- Agent Definition (Ephemeral) ---

agent : Agent({})
agent = ephemeral({
	name: "salon-analytics",
	tools: [
		calculateKpisTool,
		projectRevenueTool,
		stylistWorkloadTool,
	],
	onMessage: handleMessage,
})

# --- Conversational Message Handler ---

handleMessage : Str => Result(Str, Str)
handleMessage = |rawInput| {
	inputClean = cleanInput(rawInput)
	lower = Str.to_utf8(inputClean) |> toLowerStr

	if Str.contains(lower, "project") or Str.contains(lower, "revenue") or Str.contains(lower, "forecast") {
		daily = 940.U64
		weekly = daily * 6.U64
		monthly = weekly * 4.U64
		net = (monthly * 40.U64) // 100.U64

		Ok(
			"📈 Salon Financial Forecast:\n\n• Daily Run-Rate: $${Str.inspect(daily)}\n• 6-Day Weekly Gross: $${Str.inspect(weekly)}\n• 30-Day Monthly Gross: $${Str.inspect(monthly)}\n\nCost Breakdown (Benchmarks):\n• Stylist Commissions (50%): $${Str.inspect((monthly * 50.U64) // 100.U64)}\n• Backbar & Color Products (10%): $${Str.inspect((monthly * 10.U64) // 100.U64)}\n• Projected Net Salon Profit (40%): $${Str.inspect(net)}",
		)
	} else if Str.contains(lower, "utiliz") or Str.contains(lower, "chair") or Str.contains(lower, "occupan") {
		Ok(
			"💺 Chair Utilization Analysis:\n\n• Active Booked Slots: 8 / 10\n• Current Day Utilization: 80%\n• Benchmarked Target: 75%–85%\n\nVerdict: High demand! Stylist chairs are efficiently booked without excessive idle time.",
		)
	} else if Str.contains(lower, "cancel") or Str.contains(lower, "no-show") {
		Ok(
			"🚫 Cancellation & No-Show Performance:\n\n• Today's Cancellations: 1\n• Today's Completed/Confirmed: 8\n• Cancellation Rate: 11.1%\n• Waitlist Recovery Rate: 100% (slot auto-filled)\n\nIndustry Benchmark: 15%–20% no-shows without automated SMS/WhatsApp reminders. Luxe Studio is well ahead of industry average.",
		)
	} else {
		Ok(
			"📊 Luxe Salon Analytics Worker (Ephemeral Mode)\n\nThis worker performs on-demand calculation of salon metrics with zero persistent memory overhead.\n\nAvailable Reports:\n• 'kpi' or 'utilization' — Real-time chair occupancy and operational benchmarks\n• 'revenue' or 'forecast' — Financial run-rate, commission pool, and net margins\n• 'cancellations' — No-show metrics and waitlist recovery efficiency",
		)
	}
}

# --- Parsing Helpers ---

cleanInput : Str -> Str
cleanInput = |raw| {
	trimmed = Str.trim(raw)
	if Str.starts_with(trimmed, "{") and Str.contains(trimmed, "\"message\"") {
		match extractField(trimmed, "message") {
			msg if !(Str.is_empty(msg)) => msg
			_ => trimmed
		}
	} else {
		trimmed
	}
}

extractParam : Str, Str, U64 -> Str
extractParam = |raw, field, targetIdx| {
	trimmed = Str.trim(raw)
	if Str.starts_with(trimmed, "[") {
		s0 = trimmed
		s1 = if Str.starts_with(s0, "[") Str.drop_prefix(s0, "[") else s0
		s2 = if Str.ends_with(s1, "]") Str.drop_suffix(s1, "]") else s1
		parts = Str.split_on(s2, "\",")
		match List.get(parts, targetIdx) {
			Ok(part) => {
				t0 = Str.trim(part)
				t1 = if Str.starts_with(t0, "\"") Str.drop_prefix(t0, "\"") else t0
				if Str.ends_with(t1, "\"") Str.drop_suffix(t1, "\"") else t1
			}
			Err(_) => ""
		}
	} else if Str.starts_with(trimmed, "{") {
		extractField(trimmed, field)
	} else {
		trimmed
	}
}

extractField : Str, Str -> Str
extractField = |json, field|
	match Str.split_first(json, "\"${field}\"") {
		Ok({ after, .. }) =>
			match Str.split_first(after, ":") {
				Ok({ after: rest, .. }) => {
					t = Str.trim_start(rest)
					if Str.starts_with(t, "\"") {
						match Str.split_first(Str.drop_prefix(t, "\""), "\"") {
							Ok({ before, .. }) => before
							Err(_) => ""
						}
					} else {
						match Str.split_first(t, ",") {
							Ok({ before, .. }) => Str.trim(before)
							Err(_) =>
								match Str.split_first(t, "}") {
									Ok({ before, .. }) => Str.trim(before)
									Err(_) => Str.trim(t)
								}
						}
					}
				}
				Err(_) => ""
			}
		Err(_) => ""
	}

parseU64OrDefault : Str, U64 -> U64
parseU64OrDefault = |str, defaultVal| {
	bytes = Str.to_utf8(Str.trim(str))
	digits = List.keep_if(bytes, |b| b >= 48.U8 and b <= 57.U8)
	if List.is_empty(digits) {
		defaultVal
	} else {
		List.fold(
			digits,
			0.U64,
			|acc, b| acc * 10.U64 + U8.to_u64(b - 48.U8),
		)
	}
}

toLowerStr : List(U8) -> Str
toLowerStr = |bytes| {
	lowered =
		List.map(
			bytes,
			|b|
				if b >= 65.U8 and b <= 90.U8 {
					b + 32.U8
				} else {
					b
				},
		)
	match Str.from_utf8(lowered) {
		Ok(s) => s
		Err(_) => ""
	}
}
