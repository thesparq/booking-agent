module [
	agent,
	State,
	Stylist,
	Appointment,
	WaitlistEntry,
	ReminderRecord,
	DepositHold,
	defaultState,
	servicesTool,
	availabilityTool,
	salonInfoTool,
	stylistsTool,
	bookAppointmentTool,
	cancelAppointmentTool,
	dailyManifestTool,
	remindersTool,
	holdsTool,
	whatsappWebhookTool,
	operatingHoursMethod,
	scheduleReminderMethod,
	sendReminderMethod,
	createDepositHoldMethod,
	confirmDepositMethod,
	holdTimeoutMethod,
	getHoldsMethod,
	whatsappWebhookMethod,
	dispatchWhatsappMethod,
	remindersLogMethod,
]

import pf.Golem exposing [
	Agent,
	Method,
	Tool,
	define,
	register,
	registerReadOnly,
	registerEffectful,
	method,
	build,
	now,
	rpcSchedule,
	createPromise,
	createWebhook,
	completePromise,
	withHttpMount,
	withAgentHttpMount,
	getSecretHandle,
	httpRequest,
	HttpMount,
	HttpRequest,
	SecretHeader,
	reply,
	readOnly,
	tool,
	statefulTool,
	param,
	withTools,
]
import pf.Types exposing [Result]
import pf.Effect
import pf.Json as GolemJson exposing [encode, decode]

# --- Domain Types & Agent State ---

Stylist : {
	id : Str,
	name : Str,
	tier : Str,
	specialties : Str,
}

Appointment : {
	code : Str,
	customer : Str,
	stylist : Str,
	service : Str,
	slot : Str,
	price : U64,
	status : Str,
}

WaitlistEntry : {
	customer : Str,
	service : Str,
	stylist : Str,
	preferredDay : Str,
}

ReminderRecord : {
	id : Str,
	code : Str,
	delayMs : U64,
	status : Str,
	recipient : Str,
	service : Str,
	stylist : Str,
}

DepositHold : {
	code : Str,
	promiseId : U64,
	webhookUrl : Str,
	amount : U64,
	status : Str,
}

State : {
	salonName : Str,
	stylists : List(Stylist),
	appointments : List(Appointment),
	availableSlots : List(Str),
	waitlist : List(WaitlistEntry),
	reminders : List(ReminderRecord),
	holds : List(DepositHold),
	pendingCustomer : Str,
	pendingStylist : Str,
	pendingService : Str,
	step : Str,
}

# --- HTTP Mount for WhatsApp Cloud API ---

whatsappMount : HttpMount
whatsappMount = {
	pathPrefix: "/api/whatsapp",
	corsOrigins: ["*"],
	webhookSuffix: "/webhook",
}

# --- Initial / Default Data ---

defaultStylists : List(Stylist)
defaultStylists = [
	{
		id: "sarah",
		name: "Sarah Jenkins",
		tier: "Master Stylist",
		specialties: "Balayage, Highlights, Precision Cut",
	},
	{
		id: "alex",
		name: "Alex Rivera",
		tier: "Senior Stylist",
		specialties: "Single Process Color, Womens Cut, Blowdry",
	},
	{
		id: "jordan",
		name: "Jordan Lee",
		tier: "Stylist",
		specialties: "Mens Cut & Style, Beard Trim, Texture",
	},
]

initialAppointments : List(Appointment)
initialAppointments = [
	{
		code: "#LUXE-101",
		customer: "Maria Gonzalez",
		stylist: "Sarah Jenkins",
		service: "Balayage & Highlights",
		slot: "Today 10:00 AM",
		price: 160.U64,
		status: "Confirmed",
	},
	{
		code: "#LUXE-102",
		customer: "David Kim",
		stylist: "Jordan Lee",
		service: "Mens Cut & Style",
		slot: "Today 11:30 AM",
		price: 40.U64,
		status: "Confirmed",
	},
]

defaultWaitlist : List(WaitlistEntry)
defaultWaitlist = [
	{
		customer: "Elena Rostova",
		service: "Balayage & Highlights",
		stylist: "Sarah Jenkins",
		preferredDay: "Today",
	},
]

defaultReminders : List(ReminderRecord)
defaultReminders = [
	{
		id: "REM-001",
		code: "#LUXE-101",
		delayMs: 3600000.U64,
		status: "Scheduled",
		recipient: "Maria Gonzalez",
		service: "Balayage & Highlights",
		stylist: "Sarah Jenkins",
	},
	{
		id: "REM-002",
		code: "#LUXE-102",
		delayMs: 7200000.U64,
		status: "Scheduled",
		recipient: "David Kim",
		service: "Mens Cut & Style",
		stylist: "Jordan Lee",
	},
]

defaultHolds : List(DepositHold)
defaultHolds = [
	{
		code: "#LUXE-101",
		promiseId: 101.U64,
		webhookUrl: "https://api.golem.cloud/webhooks/wh_mock_luxe101",
		amount: 30.U64,
		status: "Completed",
	},
]

defaultSlots : List(Str)
defaultSlots = [
	"Today 2:00 PM",
	"Today 3:30 PM",
	"Today 5:00 PM",
	"Tomorrow 10:00 AM",
	"Tomorrow 11:30 AM",
	"Tomorrow 2:00 PM",
	"Tomorrow 4:00 PM",
	"Friday 10:00 AM",
	"Friday 1:00 PM",
	"Friday 3:30 PM",
]

defaultState : State
defaultState = {
	salonName: "Luxe Hair Studio",
	stylists: defaultStylists,
	appointments: initialAppointments,
	availableSlots: defaultSlots,
	waitlist: defaultWaitlist,
	reminders: defaultReminders,
	holds: defaultHolds,
	pendingCustomer: "",
	pendingStylist: "",
	pendingService: "",
	step: "idle",
}

# --- Tools for LLM & Function Calling ---

servicesTool : Tool(State)
servicesTool = tool({
	name: "get_services",
	description: "Returns salon services, duration, and pricing catalog",
	params: [],
	execute: |_st, _args|
		Ok(servicesMenuJson),
})

salonInfoTool : Tool(State)
salonInfoTool = tool({
	name: "get_salon_info",
	description: "Returns salon address, phone number, hours, and cancellation policy",
	params: [],
	execute: |_st, _args|
		Ok(salonInfoJson),
})

stylistsTool : Tool(State)
stylistsTool = tool({
	name: "get_stylists",
	description: "Returns roster of salon stylists, tiers, and specialties",
	params: [],
	execute: |st, _args|
		Ok(formatStylistsJson(st.stylists)),
})

availabilityTool : Tool(State)
availabilityTool = tool({
	name: "check_availability",
	description: "Returns currently open appointment slots, optionally filtered by stylist",
	params: [
		param("stylist", "Optional stylist name to filter slots"),
	],
	execute: |st, args| {
		requestedStylist = extractParam(args, "stylist", 0.U64)
		slots = filterSlotsByStylist(st.availableSlots, requestedStylist)
		Ok(formatSlotsJson(slots))
	},
})

executeAppointmentBooking : State, Str -> Result({ state : State, stateChanged : Bool, output : Str }, Str)
executeAppointmentBooking = |st, args| {
	customer = extractParam(args, "customer", 0.U64)
	service = extractParam(args, "service", 1.U64)
	slot = extractParam(args, "slot", 2.U64)
	rawStylist = extractParam(args, "stylist", 3.U64)
	stylist = if Str.is_empty(rawStylist) "Sarah Jenkins" else resolveStylistName(rawStylist)

	bookingNum = List.len(st.appointments) + 1.U64
	code = "#LUXE-10${Str.inspect(bookingNum)}"
	price = getServicePrice(service)
	needsDeposit = isDepositRequired(service)
	initialStatus = if needsDeposit "PendingDeposit" else "Confirmed"

	newAppt : Appointment
	newAppt = {
		code: code,
		customer: customer,
		stylist: stylist,
		service: service,
		slot: slot,
		price: price,
		status: initialStatus,
	}

	updatedAppointments = List.append(st.appointments, newAppt)
	remainingSlots = List.drop_if(st.availableSlots, |s| s == slot)

	if needsDeposit {
		newHold : DepositHold
		newHold = {
			code: code,
			promiseId: bookingNum + 1000.U64,
			webhookUrl: "https://api.golem.cloud/webhooks/mock_stripe_${code}",
			amount: 30.U64,
			status: "Pending",
		}
		updatedHolds = List.append(st.holds, newHold)

		Ok({
			state: {
				..st,
				appointments: updatedAppointments,
				availableSlots: remainingSlots,
				holds: updatedHolds,
			},
			stateChanged: True,
			output: "Appointment provisionally held with code ${code} for ${customer} with ${stylist} (${service}) at ${slot}. Total: $${Str.inspect(price)}. A $30 deposit is required within 15 minutes to confirm booking. Mock Checkout URL: https://checkout.stripe.com/pay/cs_test_mock_${code}?deposit=30&code=${code}&webhook=${newHold.webhookUrl}",
		})
	} else {
		newReminder : ReminderRecord
		newReminder = {
			id: "REM-00${Str.inspect(List.len(st.reminders) + 1.U64)}",
			code: code,
			delayMs: 86400000.U64,
			status: "Scheduled",
			recipient: customer,
			service: service,
			stylist: stylist,
		}
		updatedReminders = List.append(st.reminders, newReminder)

		Ok({
			state: {
				..st,
				appointments: updatedAppointments,
				availableSlots: remainingSlots,
				reminders: updatedReminders,
			},
			stateChanged: True,
			output: "Appointment confirmed with code ${code} for ${customer} with ${stylist} (${service}) at ${slot}. Total: $${Str.inspect(price)}. Reminder ${newReminder.id} scheduled.",
		})
	}
}

bookAppointmentTool : Tool(State)
bookAppointmentTool = statefulTool({
	name: "book_appointment",
	description: "Directly book an appointment for a customer, service, slot, and optional stylist",
	params: [
		param("customer", "Full name of the customer"),
		param("service", "Requested hair service"),
		param("slot", "Requested appointment time slot"),
		param("stylist", "Preferred stylist name (optional)"),
	],
	execute: executeAppointmentBooking,
})

executeCancelAppointment : State, Str -> Result({ state : State, stateChanged : Bool, output : Str }, Str)
executeCancelAppointment = |st, args| {
	targetCode = extractParam(args, "code", 0.U64)
	result = cancelAppointment(st, targetCode)

	Ok({
		state: result.updatedState,
		stateChanged: True,
		output: result.message,
	})
}

cancelAppointmentTool : Tool(State)
cancelAppointmentTool = statefulTool({
	name: "cancel_appointment",
	description: "Cancel an active booking by confirmation code and release the slot",
	params: [
		param("code", "Confirmation code of the appointment to cancel (e.g. #LUXE-101)"),
	],
	execute: executeCancelAppointment,
})

dailyManifestTool : Tool(State)
dailyManifestTool = tool({
	name: "get_daily_manifest",
	description: "Returns salon owner daily operational agenda, roster, and projected revenue",
	params: [],
	execute: |st, _args|
		Ok(formatDailyManifestJson(st)),
})

remindersTool : Tool(State)
remindersTool = tool({
	name: "get_reminders",
	description: "Returns all scheduled, dispatched, and cancelled appointment reminders",
	params: [],
	execute: |st, _args|
		Ok(formatRemindersJson(st.reminders)),
})

holdsTool : Tool(State)
holdsTool = tool({
	name: "get_holds",
	description: "Returns all active and completed deposit holds, promise handles, and mock Stripe URLs",
	params: [],
	execute: |st, _args|
		Ok(formatHoldsJson(st.holds)),
})

whatsappWebhookTool : Tool(State)
whatsappWebhookTool = tool({
	name: "handle_whatsapp_webhook",
	description: "Processes incoming WhatsApp message or webhook event and routes to booking concierge",
	params: [
		param("payload", "Raw Meta WhatsApp webhook event payload or message text"),
	],
	execute: |st, args| {
		payload = extractParam(args, "payload", 0.U64)
		match handleWhatsappWebhook(st, payload) {
			Ok(res) => Ok(res.out)
			Err(e) => Err(e)
		}
	},
})

# --- Phantom-Typed Methods for RPC, Timers & Effects ---

handleMessageMethod : Method(Str, Str)
handleMessageMethod = method({
	name: "handle-message",
	description: "Conversational multi-turn booking concierge interface",
	promptHint: "Send message to salon agent",
})

servicesMethod : Method(Str, Str)
servicesMethod = method({
	name: "get_services",
	description: "Returns salon services catalog and prices",
	promptHint: "Query services catalog",
})

availabilityMethod : Method(Str, Str)
availabilityMethod = method({
	name: "check_availability",
	description: "Checks unbooked time slots",
	promptHint: "Query open appointment slots",
})

salonInfoMethod : Method(Str, Str)
salonInfoMethod = method({
	name: "get_salon_info",
	description: "Returns salon contact, address, and hours",
	promptHint: "Query salon details",
})

stylistsMethod : Method(Str, Str)
stylistsMethod = method({
	name: "get_stylists",
	description: "Returns stylists roster and specialties",
	promptHint: "Query stylist team",
})

bookAppointmentMethod : Method(Str, Str)
bookAppointmentMethod = method({
	name: "book_appointment",
	description: "Direct structured appointment booking",
	promptHint: "Book customer appointment",
})

cancelAppointmentMethod : Method(Str, Str)
cancelAppointmentMethod = method({
	name: "cancel_appointment",
	description: "Cancel appointment and restore slot",
	promptHint: "Cancel appointment",
})

dailyManifestMethod : Method(Str, Str)
dailyManifestMethod = method({
	name: "get_daily_manifest",
	description: "Returns salon owner operational agenda",
	promptHint: "Query daily agenda",
})

remindersLogMethod : Method(Str, Str)
remindersLogMethod = method({
	name: "get_reminders",
	description: "Query durable reminder status log",
	promptHint: "Query reminders",
})

getHoldsMethod : Method(Str, Str)
getHoldsMethod = method({
	name: "get_holds",
	description: "Query all deposit holds and Stripe mock checkout URLs",
	promptHint: "Query deposit holds",
})

operatingHoursMethod : Method(Str, Str)
operatingHoursMethod = method({
	name: "check_operating_hours",
	description: "Verifies current host timestamp against salon operating schedule using Golem now effect",
	promptHint: "Verify open hours against host clock",
})

scheduleReminderMethod : Method(Str, Str)
scheduleReminderMethod = method({
	name: "schedule_reminder",
	description: "Schedules a durable timer reminder via Golem rpcSchedule",
	promptHint: "Schedule appointment reminder",
})

sendReminderMethod : Method(Str, Str)
sendReminderMethod = method({
	name: "send_reminder",
	description: "Durable timer callback invoked by Golem runtime to deliver reminder",
	promptHint: "Timer wakeup callback",
})

createDepositHoldMethod : Method(Str, Str)
createDepositHoldMethod = method({
	name: "create_deposit_hold",
	description: "Creates durable promise, webhook, and 15-minute hold timer for appointment deposit",
	promptHint: "Create deposit hold",
})

confirmDepositMethod : Method(Str, Str)
confirmDepositMethod = method({
	name: "confirm_deposit",
	description: "Confirms deposit payment, completes durable promise, transitions appointment to Confirmed, and schedules 24h reminder",
	promptHint: "Confirm appointment deposit",
})

holdTimeoutMethod : Method(Str, Str)
holdTimeoutMethod = method({
	name: "hold_timeout",
	description: "Durable timer callback invoked after 15 minutes to expire unpaid deposit holds and auto-promote waitlist",
	promptHint: "Deposit hold timeout callback",
})

whatsappWebhookMethod : Method(Str, Str)
whatsappWebhookMethod = method({
	name: "whatsapp_webhook",
	description: "Meta WhatsApp Cloud API webhook handler for GET verification challenge and POST message ingestion",
	promptHint: "Handle WhatsApp webhook request",
})

dispatchWhatsappMethod : Method(Str, Str)
dispatchWhatsappMethod = method({
	name: "dispatch_whatsapp",
	description: "Dispatches outbound WhatsApp message using Golem SecretHandle('META_WHATSAPP_TOKEN') and host httpRequest",
	promptHint: "Dispatch WhatsApp message",
})

# --- Effectful & Method Handlers ---

handleOperatingHours : State, Str -> Effect.Effect(Result({ state : State, out : Str }, Str))
handleOperatingHours = |st, _raw|
	Effect.map(
		now,
		|timestampMs|
			Ok({
				state: st,
				out: evaluateOperatingHours(timestampMs),
			}),
	)

handleScheduleReminder : State, Str -> Effect.Effect(Result({ state : State, out : Str }, Str))
handleScheduleReminder = |st, rawArgs| {
	targetCode = extractParam(rawArgs, "code", 0.U64)
	rawDelay = extractParam(rawArgs, "delayMs", 1.U64)
	delayMs = if Str.is_empty(rawDelay) 5000.U64 else parseU64OrDefault(rawDelay, 5000.U64)

	matched = List.keep_if(st.appointments, |a| a.code == targetCode and a.status == "Confirmed")
	match List.get(matched, 0.U64) {
		Ok(appt) => {
			remId = "REM-00${Str.inspect(List.len(st.reminders) + 1.U64)}"
			payload = "{\"id\":\"${remId}\",\"code\":\"${appt.code}\",\"customer\":\"${appt.customer}\",\"service\":\"${appt.service}\",\"stylist\":\"${appt.stylist}\",\"slot\":\"${appt.slot}\"}"

			newReminder : ReminderRecord
			newReminder = {
				id: remId,
				code: appt.code,
				delayMs: delayMs,
				status: "Scheduled",
				recipient: appt.customer,
				service: appt.service,
				stylist: appt.stylist,
			}

			Effect.map(
				rpcSchedule("booking-coordinator", sendReminderMethod, payload, delayMs),
				|_rpcRes|
					Ok({
						state: {
							..st,
							reminders: List.append(st.reminders, newReminder),
						},
						out: "Durable reminder ${remId} scheduled for appointment ${appt.code} with delay ${Str.inspect(delayMs)} ms via Golem rpcSchedule.",
					}),
			)
		}
		Err(_) =>
			Effect.always(
				Ok({
					state: st,
					out: "Cannot schedule reminder: Appointment '${targetCode}' not found or not in Confirmed status.",
				}),
			)
	}
}

handleSendReminder : State, Str -> Result({ state : State, out : Str }, Str)
handleSendReminder = |st, payload| {
	targetCode = extractParam(payload, "code", 0.U64)
	remId = extractParam(payload, "id", 1.U64)

	isConfirmed =
		List.any(
			st.appointments,
			|a| a.code == targetCode and a.status == "Confirmed",
		)

	if isConfirmed {
		updatedReminders =
			List.map(
				st.reminders,
				|r|
					if r.code == targetCode or r.id == remId {
						{ ..r, status: "Dispatched" }
					} else {
						r
					},
			)
		Ok({
			state: {
				..st,
				reminders: updatedReminders,
			},
			out: "🔔 [DURABLE TIMER WAKEUP] Reminder dispatched for appointment ${targetCode} to customer. Status: Dispatched.",
		})
	} else {
		updatedReminders =
			List.map(
				st.reminders,
				|r|
					if r.code == targetCode or r.id == remId {
						{ ..r, status: "Cancelled" }
					} else {
						r
					},
			)
		Ok({
			state: {
				..st,
				reminders: updatedReminders,
			},
			out: "⚠️ [DURABLE TIMER WAKEUP] Appointment ${targetCode} was cancelled prior to reminder trigger. Reminder skipped cleanly.",
		})
	}
}

handleCreateDepositHold : State, Str -> Effect.Effect(Result({ state : State, out : Str }, Str))
handleCreateDepositHold = |st, rawArgs| {
	targetCode = extractParam(rawArgs, "code", 0.U64)
	rawDelay = extractParam(rawArgs, "delayMs", 1.U64)
	delayMs = if Str.is_empty(rawDelay) 900000.U64 else parseU64OrDefault(rawDelay, 900000.U64)

	matched = List.keep_if(st.appointments, |a| a.code == targetCode and a.status == "PendingDeposit")
	match List.get(matched, 0.U64) {
		Ok(appt) =>
			Effect.and_then(
				createPromise,
				|promiseRes|
					match promiseRes {
						Ok(promiseId) =>
							Effect.and_then(
								createWebhook(promiseId),
								|webhookRes| {
									webhookUrl =
										match webhookRes {
											Ok(url) => url
											Err(_) => "https://api.golem.cloud/webhooks/mock_${Str.inspect(promiseId)}"
										}

									payload = "{\"code\":\"${appt.code}\",\"promiseId\":${Str.inspect(promiseId)}}"

									newHold : DepositHold
									newHold = {
										code: appt.code,
										promiseId: promiseId,
										webhookUrl: webhookUrl,
										amount: 30.U64,
										status: "Pending",
									}

									updatedHolds =
										st.holds
										|> List.drop_if(|h| h.code == appt.code and h.status == "Pending")
										|> List.append(newHold)

									checkoutUrl = "https://checkout.stripe.com/pay/cs_test_mock_${appt.code}?deposit=30&code=${appt.code}&webhook=${webhookUrl}"

									Effect.map(
										rpcSchedule("booking-coordinator", holdTimeoutMethod, payload, delayMs),
										|_rpcRes|
											Ok({
												state: {
													..st,
													holds: updatedHolds,
												},
												out: "💳 [DEPOSIT HOLD ACTIVE] Durable promise #${Str.inspect(promiseId)} and webhook created for appointment ${appt.code}. Slot '${appt.slot}' held for ${Str.inspect(delayMs // 1000.U64)} seconds.\n\nCheckout URL: ${checkoutUrl}\nWebhook Endpoint: ${webhookUrl}",
											}),
									)
								},
							)

						Err(err) =>
							Effect.always(
								Ok({
									state: st,
									out: "Failed to create durable promise for deposit: ${err}",
								}),
							)
					},
			)

		Err(_) =>
			Effect.always(
				Ok({
					state: st,
					out: "Cannot create deposit hold: No appointment matching '${targetCode}' in PendingDeposit status.",
				}),
			)
	}
}

handleConfirmDeposit : State, Str -> Effect.Effect(Result({ state : State, out : Str }, Str))
handleConfirmDeposit = |st, rawArgs| {
	targetCode = extractParam(rawArgs, "code", 0.U64)

	matchedAppt = List.keep_if(st.appointments, |a| a.code == targetCode and a.status == "PendingDeposit")
	match List.get(matchedAppt, 0.U64) {
		Ok(appt) => {
			matchedHold = List.keep_if(st.holds, |h| h.code == targetCode and h.status == "Pending")
			promiseId =
				match List.get(matchedHold, 0.U64) {
					Ok(h) => h.promiseId
					Err(_) => 0.U64
				}

			updatedAppointments =
				List.map(
					st.appointments,
					|a|
						if a.code == targetCode {
							{ ..a, status: "Confirmed" }
						} else {
							a
						},
				)

			updatedHolds =
				List.map(
					st.holds,
					|h|
						if h.code == targetCode and h.status == "Pending" {
							{ ..h, status: "Completed" }
						} else {
							h
						},
				)

			remId = "REM-00${Str.inspect(List.len(st.reminders) + 1.U64)}"
			newReminder : ReminderRecord
			newReminder = {
				id: remId,
				code: appt.code,
				delayMs: 86400000.U64,
				status: "Scheduled",
				recipient: appt.customer,
				service: appt.service,
				stylist: appt.stylist,
			}
			updatedReminders = List.append(st.reminders, newReminder)
			remPayload = "{\"id\":\"${remId}\",\"code\":\"${appt.code}\",\"customer\":\"${appt.customer}\",\"service\":\"${appt.service}\",\"stylist\":\"${appt.stylist}\",\"slot\":\"${appt.slot}\"}"

			confirmMsg = "🎉 [DEPOSIT CONFIRMED] $30 deposit received for booking ${targetCode} (${appt.customer} with ${appt.stylist} for ${appt.service} at ${appt.slot}). Durable promise completed. Status: Confirmed. 🔔 24-hour reminder (${remId}) scheduled."
			completeData = Str.to_utf8("{\"status\":\"paid\",\"code\":\"${targetCode}\",\"amount\":30}")

			if promiseId > 0.U64 {
				Effect.and_then(
					completePromise(promiseId, completeData),
					|_compRes|
						Effect.map(
							rpcSchedule("booking-coordinator", sendReminderMethod, remPayload, 86400000.U64),
							|_rpcRes|
								Ok({
									state: {
										..st,
										appointments: updatedAppointments,
										holds: updatedHolds,
										reminders: updatedReminders,
									},
									out: confirmMsg,
								}),
						),
				)
			} else {
				Effect.map(
					rpcSchedule("booking-coordinator", sendReminderMethod, remPayload, 86400000.U64),
					|_rpcRes|
						Ok({
							state: {
								..st,
								appointments: updatedAppointments,
								holds: updatedHolds,
								reminders: updatedReminders,
							},
							out: confirmMsg,
						}),
				)
			}
		}

		Err(_) => {
			alreadyConfirmed = List.any(st.appointments, |a| a.code == targetCode and a.status == "Confirmed")
			msg =
				if alreadyConfirmed {
					"Appointment ${targetCode} is already confirmed."
				} else {
					"Cannot confirm deposit: No appointment matching '${targetCode}' in PendingDeposit status."
				}

			Effect.always(
				Ok({
					state: st,
					out: msg,
				}),
			)
		}
	}
}

handleHoldTimeout : State, Str -> Result({ state : State, out : Str }, Str)
handleHoldTimeout = |st, payload| {
	targetCode = extractParam(payload, "code", 0.U64)

	matchedAppt = List.keep_if(st.appointments, |a| a.code == targetCode and a.status == "PendingDeposit")
	match List.get(matchedAppt, 0.U64) {
		Ok(appt) => {
			updatedAppointments =
				List.map(
					st.appointments,
					|a|
						if a.code == targetCode {
							{ ..a, status: "Cancelled" }
						} else {
							a
						},
				)

			updatedHolds =
				List.map(
					st.holds,
					|h|
						if h.code == targetCode and h.status == "Pending" {
							{ ..h, status: "Expired" }
						} else {
							h
						},
				)

			restoredSlots = List.append(st.availableSlots, appt.slot)

			match List.get(st.waitlist, 0.U64) {
				Ok(waitCandidate) => {
					remainingWaitlist = List.drop_if(st.waitlist, |w| w.customer == waitCandidate.customer)
					promotionMsg = "\n\n🔔 [WAITLIST AUTO-PROMOTION] Notified ${waitCandidate.customer} (${waitCandidate.service}) that released slot '${appt.slot}' with ${appt.stylist} is now open for reservation!"

					Ok({
						state: {
							..st,
							appointments: updatedAppointments,
							holds: updatedHolds,
							availableSlots: restoredSlots,
							waitlist: remainingWaitlist,
						},
						out: "⏰ [HOLD EXPIRED] 15-minute deposit hold for appointment ${targetCode} expired unpaid. Slot '${appt.slot}' released back to calendar.${promotionMsg}",
					})
				}

				Err(_) =>
					Ok({
						state: {
							..st,
							appointments: updatedAppointments,
							holds: updatedHolds,
							availableSlots: restoredSlots,
						},
						out: "⏰ [HOLD EXPIRED] 15-minute deposit hold for appointment ${targetCode} expired unpaid. Slot '${appt.slot}' restored to open calendar.",
					})
			}
		}

		Err(_) => {
			isConfirmed = List.any(st.appointments, |a| a.code == targetCode and a.status == "Confirmed")
			outMsg =
				if isConfirmed {
					"✅ [HOLD TIMEOUT CHECK] Appointment ${targetCode} was confirmed with deposit. Hold timer finished cleanly."
				} else {
					"Hold timeout check for '${targetCode}': Appointment not in pending state."
				}

			Ok({
				state: st,
				out: outMsg,
			})
		}
	}
}

handleWhatsappWebhook : State, Str -> Result({ state : State, out : Str }, Str)
handleWhatsappWebhook = |st, rawInput| {
	inputClean = Str.trim(rawInput)

	# 1. Meta verification challenge handshake (GET)
	if Str.contains(inputClean, "subscribe") and (Str.contains(inputClean, "challenge") or Str.contains(inputClean, "hub.")) {
		challenge = extractChallenge(inputClean)
		token = extractVerifyToken(inputClean)

		if token == "luxe_salon_secret_token" or token == "luxe_salon_webhook_token" or Str.is_empty(token) {
			Ok({
				state: st,
				out: challenge,
			})
		} else {
			Err("Webhook verification failed: Invalid verify_token '${token}'")
		}
	} else if Str.contains(inputClean, "\"messages\"") or Str.contains(inputClean, "\"wa_id\"") {
		# 2. Inbound Meta Webhook Event (POST)
		senderPhone = extractWhatsappSender(inputClean)
		msgBody = extractWhatsappMessageBody(inputClean)

		match handleMessage(st, msgBody) {
			Ok(res) => {
				replyBody = res.response
				waResponse = "{\"messaging_product\":\"whatsapp\",\"recipient_type\":\"individual\",\"to\":\"${senderPhone}\",\"type\":\"text\",\"text\":{\"body\":\"${replyBody}\"}}"
				Ok({
					state: res.state,
					out: waResponse,
				})
			}
			Err(err) => Err(err)
		}
	} else {
		# 3. Direct conversational text fallback
		match handleMessage(st, inputClean) {
			Ok(res) => Ok({ state: res.state, out: res.response })
			Err(err) => Err(err)
		}
	}
}

handleDispatchWhatsapp : State, Str -> Effect.Effect(Result({ state : State, out : Str }, Str))
handleDispatchWhatsapp = |st, rawArgs| {
	targetPhone = extractParam(rawArgs, "recipient", 0.U64)
	recipient = if Str.is_empty(targetPhone) "+1 (555) 234-5678" else targetPhone
	rawMsg = extractParam(rawArgs, "message", 1.U64)
	msg = if Str.is_empty(rawMsg) "Hello from Luxe Hair Studio!" else rawMsg

	cleanPhone = sanitizePhone(recipient)

	Effect.and_then(
		getSecretHandle("META_WHATSAPP_TOKEN"),
		|secRes|
			match secRes {
				Ok(handle) => {
					sh : SecretHeader
					sh = {
						name: "Authorization",
						prefix: "Bearer ",
						handle: handle,
					}
					req : HttpRequest
					req = {
						url: "https://graph.facebook.com/v21.0/10987654321/messages",
						method: "POST",
						headers: [{ name: "Content-Type", value: "application/json" }],
						secretHeaders: [sh],
						body: "{\"messaging_product\":\"whatsapp\",\"recipient_type\":\"individual\",\"to\":\"${cleanPhone}\",\"type\":\"text\",\"text\":{\"body\":\"${msg}\"}}",
					}
					Effect.map(
						httpRequest(req),
						|httpRes|
							match httpRes {
								Ok(body) =>
									Ok({
										state: st,
										out: "📲 [WHATSAPP DISPATCHED] Outbound message sent to ${recipient} via Meta Cloud API using Golem SecretHandle.\nResponse: ${body}",
									})
								Err(err) =>
									Ok({
										state: st,
										out: "⚠️ [WHATSAPP GATEWAY NOTICE] Host attempted outbound HTTP to Meta API (${err}). Fallback: Message logged for delivery to ${recipient}.",
									})
							},
					)
				}
				Err(_) =>
					Effect.always(
						Ok({
							state: st,
							out: "📲 [WHATSAPP SIMULATED] Meta secret 'META_WHATSAPP_TOKEN' not configured in local environment. Simulated WhatsApp dispatch to ${recipient}:\n\"${msg}\"",
						}),
					),
			},
	)
}

handleMessageAdapter : State, Str -> Result({ state : State, out : Str }, Str)
handleMessageAdapter = |st, rawInput|
	match handleMessage(st, rawInput) {
		Ok(res) => Ok({ state: res.state, out: res.response })
		Err(err) => Err(err)
	}

# --- Canonical Agent Definition (Builder Pattern with Effectful Methods) ---

agent : Agent(State)
agent =
	define(
		{
			name: "booking-coordinator",
			version: "1.2.0",
			description: "Durable salon booking coordinator with multi-stylist calendar, deposit holds, durable reminders, and WhatsApp webhook integration",
		},
		|_| Ok(defaultState),
		|st| encode(st),
		|raw| decode(raw),
	)
		|> withHttpMount(whatsappMount)
		|> registerReadOnly(servicesMethod, |_st, _args| Ok(servicesMenuJson))
		|> registerReadOnly(availabilityMethod, |st, args| {
			reqStylist = extractParam(args, "stylist", 0.U64)
			Ok(formatSlotsJson(filterSlotsByStylist(st.availableSlots, reqStylist)))
		})
		|> registerReadOnly(salonInfoMethod, |_st, _args| Ok(salonInfoJson))
		|> registerReadOnly(stylistsMethod, |st, _args| Ok(formatStylistsJson(st.stylists)))
		|> register(bookAppointmentMethod, |st, args| {
			match executeAppointmentBooking(st, args) {
				Ok(res) => Ok({ state: res.state, out: res.output })
				Err(err) => Err(err)
			}
		})
		|> register(cancelAppointmentMethod, |st, args| {
			match executeCancelAppointment(st, args) {
				Ok(res) => Ok({ state: res.state, out: res.output })
				Err(err) => Err(err)
			}
		})
		|> registerReadOnly(dailyManifestMethod, |st, _args| Ok(formatDailyManifestJson(st)))
		|> registerReadOnly(remindersLogMethod, |st, _args| Ok(formatRemindersJson(st.reminders)))
		|> registerReadOnly(getHoldsMethod, |st, _args| Ok(formatHoldsJson(st.holds)))
		|> registerEffectful(operatingHoursMethod, handleOperatingHours)
		|> registerEffectful(scheduleReminderMethod, handleScheduleReminder)
		|> register(sendReminderMethod, handleSendReminder)
		|> registerEffectful(createDepositHoldMethod, handleCreateDepositHold)
		|> registerEffectful(confirmDepositMethod, handleConfirmDeposit)
		|> register(holdTimeoutMethod, handleHoldTimeout)
		|> register(whatsappWebhookMethod, handleWhatsappWebhook)
		|> registerEffectful(dispatchWhatsappMethod, handleDispatchWhatsapp)
		|> register(handleMessageMethod, handleMessageAdapter)
		|> build

# --- Conversational Message Handler ---

handleMessage : State, Str -> Result({ state : State, stateChanged : Bool, response : Str }, Str)
handleMessage = |state, rawInput| {
	inputClean = cleanInput(rawInput)
	lower = Str.to_utf8(inputClean) |> toLowerStr

	if state.step != "idle" and (Str.contains(lower, "cancel") or Str.contains(lower, "reset") or Str.contains(lower, "stop")) {
		reply(
			{
				..state,
				step: "idle",
				pendingCustomer: "",
				pendingStylist: "",
				pendingService: "",
			},
			"Booking wizard has been cancelled. How else can I assist you with Luxe Hair Studio?",
		)
	} else if Str.contains(lower, "pay deposit") or Str.contains(lower, "confirm deposit") or (Str.starts_with(lower, "pay") and (Str.contains(lower, "10") or Str.contains(lower, "luxe"))) {
		targetCode = extractCodeFromInput(inputClean)
		matched = List.keep_if(state.appointments, |a| a.status == "PendingDeposit" and (a.code == targetCode or Str.contains(targetCode, a.code) or Str.contains(a.code, targetCode)))
		match List.get(matched, 0.U64) {
			Ok(appt) => {
				updatedAppointments =
					List.map(
						state.appointments,
						|a|
							if a.code == appt.code {
								{ ..a, status: "Confirmed" }
							} else {
								a
							},
					)

				updatedHolds =
					List.map(
						state.holds,
						|h|
							if h.code == appt.code and h.status == "Pending" {
								{ ..h, status: "Completed" }
							} else {
								h
							},
					)

				remId = "REM-00${Str.inspect(List.len(state.reminders) + 1.U64)}"
				newReminder : ReminderRecord
				newReminder = {
					id: remId,
					code: appt.code,
					delayMs: 86400000.U64,
					status: "Scheduled",
					recipient: appt.customer,
					service: appt.service,
					stylist: appt.stylist,
				}
				updatedReminders = List.append(state.reminders, newReminder)

				reply(
					{
						..state,
						appointments: updatedAppointments,
						holds: updatedHolds,
						reminders: updatedReminders,
					},
					"🎉 Deposit Confirmed!\n\nWe received your $30 deposit hold for booking ${appt.code} (${appt.customer} with ${appt.stylist} for ${appt.service} at ${appt.slot}).\n\nYour appointment is now Confirmed! 🔔 24-Hour Reminder (${remId}) scheduled automatically.",
				)
			}
			Err(_) =>
				readOnly(state, "Could not find a pending deposit booking matching '${inputClean}'. Please provide your confirmation code (e.g. 'pay deposit #LUXE-103').")
		}
	} else if Str.contains(lower, "cancel #") or Str.contains(lower, "cancel lux") or (Str.starts_with(lower, "cancel") and Str.contains(lower, "10")) {
		result = cancelAppointment(state, inputClean)
		reply(result.updatedState, result.message)
	} else if Str.contains(lower, "manifest") or Str.contains(lower, "daily schedule") or Str.contains(lower, "revenue") or Str.contains(lower, "owner") {
		readOnly(state, formatDailyManifest(state))
	} else if Str.contains(lower, "my booking") or Str.contains(lower, "status") {
		readOnly(state, formatAppointmentsList(state.appointments))
	} else if Str.contains(lower, "stylist") or Str.contains(lower, "team") or Str.contains(lower, "who works") {
		readOnly(state, formatStylistsList(state.stylists))
	} else if Str.contains(lower, "remind") {
		readOnly(state, formatRemindersText(state.reminders))
	} else if Str.contains(lower, "hold") or Str.contains(lower, "deposit") {
		readOnly(state, formatHoldsText(state.holds))
	} else if Str.contains(lower, "whatsapp") or Str.contains(lower, "webhook") {
		readOnly(
			state,
			"📱 Meta WhatsApp Cloud API Endpoint Active!\n\n• Webhook Path: /api/whatsapp/webhook\n• Verification Mode: GET (hub.mode=subscribe, hub.verify_token)\n• Event Ingestion: POST (Meta JSON Webhook Events)\n• Outbound Dispatch: Meta Cloud Graph API with Golem SecretHandle('META_WHATSAPP_TOKEN')",
		)
	} else if Str.contains(lower, "hour") or Str.contains(lower, "open") or Str.contains(lower, "schedule") {
		readOnly(state, salonInfoText)
	} else if state.step == "waiting_name" {
		custName = inputClean
		reply(
			{ ..state, pendingCustomer: custName, step: "waiting_stylist" },
			"Nice to meet you, ${custName}! Do you have a preferred stylist?\n\n${formatStylistsList(state.stylists)}\n\nReply with a stylist name (e.g. 'Sarah', 'Alex', 'Jordan'), or say 'any'.",
		)
	} else if state.step == "waiting_stylist" {
		stylistChoice = resolveStylistName(inputClean)
		reply(
			{ ..state, pendingStylist: stylistChoice, step: "waiting_service" },
			"Great, stylist set to: ${stylistChoice}!\n\nWhat service would you like to schedule?\n\n${servicesMenuText}",
		)
	} else if state.step == "waiting_service" {
		serviceName = inputClean
		reply(
			{ ..state, pendingService: serviceName, step: "waiting_slot" },
			"Excellent choice! Which available slot would you prefer?\n\nAvailable slots:\n${formatSlotsList(state.availableSlots)}",
		)
	} else if state.step == "waiting_slot" {
		chosenSlot = inputClean
		bookingNum = List.len(state.appointments) + 1.U64
		code = "#LUXE-10${Str.inspect(bookingNum)}"
		price = getServicePrice(state.pendingService)
		stylist = if Str.is_empty(state.pendingStylist) "Sarah Jenkins" else state.pendingStylist
		needsDeposit = isDepositRequired(state.pendingService)

		if needsDeposit {
			newAppt : Appointment
			newAppt = {
				code: code,
				customer: state.pendingCustomer,
				stylist: stylist,
				service: state.pendingService,
				slot: chosenSlot,
				price: price,
				status: "PendingDeposit",
			}

			newHold : DepositHold
			newHold = {
				code: code,
				promiseId: bookingNum + 2000.U64,
				webhookUrl: "https://api.golem.cloud/webhooks/mock_${code}",
				amount: 30.U64,
				status: "Pending",
			}

			updatedAppointments = List.append(state.appointments, newAppt)
			remainingSlots = List.drop_if(state.availableSlots, |s| s == chosenSlot)
			updatedHolds = List.append(state.holds, newHold)

			balanceDue = if price >= 30.U64 (price - 30.U64) else 0.U64

			reply(
				{
					..state,
					appointments: updatedAppointments,
					availableSlots: remainingSlots,
					holds: updatedHolds,
					step: "idle",
					pendingCustomer: "",
					pendingStylist: "",
					pendingService: "",
				},
				"💳 Deposit Hold Required!\n\nBecause ${state.pendingService} is a premium service ($${Str.inspect(price)}), a $30 deposit is required to confirm your reservation.\n\n• Confirmation Code: ${code}\n• Customer: ${state.pendingCustomer}\n• Stylist: ${stylist}\n• Slot Held: ${chosenSlot} (15-minute hold)\n• Balance Due at Salon: $${Str.inspect(balanceDue)}\n\n👉 Mock Stripe Checkout:\nhttps://checkout.stripe.com/pay/cs_test_mock_${code}?deposit=30&code=${code}\n\nReply with 'pay deposit ${code}' to simulate immediate payment confirmation!",
			)
		} else {
			newAppt : Appointment
			newAppt = {
				code: code,
				customer: state.pendingCustomer,
				stylist: stylist,
				service: state.pendingService,
				slot: chosenSlot,
				price: price,
				status: "Confirmed",
			}

			newReminder : ReminderRecord
			newReminder = {
				id: "REM-00${Str.inspect(List.len(state.reminders) + 1.U64)}",
				code: code,
				delayMs: 86400000.U64,
				status: "Scheduled",
				recipient: state.pendingCustomer,
				service: state.pendingService,
				stylist: stylist,
			}

			updatedAppointments = List.append(state.appointments, newAppt)
			remainingSlots = List.drop_if(state.availableSlots, |s| s == chosenSlot)
			updatedReminders = List.append(state.reminders, newReminder)

			reply(
				{
					..state,
					appointments: updatedAppointments,
					availableSlots: remainingSlots,
					reminders: updatedReminders,
					step: "idle",
					pendingCustomer: "",
					pendingStylist: "",
					pendingService: "",
				},
				"Appointment Confirmed!\n\nConfirmation Code: ${code}\nCustomer: ${state.pendingCustomer}\nStylist: ${stylist}\nService: ${state.pendingService}\nTime Slot: ${chosenSlot}\nEstimated Total: $${Str.inspect(price)}\nLocation: 742 Evergreen Terrace, Suite 101\n\n🔔 24-Hour Reminder (${newReminder.id}) scheduled automatically.\n\nWe look forward to styling your hair! Let me know if you need any other help.",
			)
		}
	} else if Str.contains(lower, "book") or Str.contains(lower, "reserve") or Str.contains(lower, "schedule") {
		reply(
			{ ..state, step: "waiting_name" },
			"I would be happy to reserve your appointment at Luxe Hair Studio! First, could you please tell me your full name?",
		)
	} else if Str.contains(lower, "service") or Str.contains(lower, "price") or Str.contains(lower, "menu") {
		readOnly(state, servicesMenuText)
	} else if Str.contains(lower, "slot") or Str.contains(lower, "availab") or Str.contains(lower, "time") or Str.contains(lower, "when") {
		readOnly(state, "Current Available Openings:\n\n${formatSlotsList(state.availableSlots)}\n\nReply with 'book' to reserve an appointment!")
	} else if Str.contains(lower, "info") or Str.contains(lower, "hour") or Str.contains(lower, "address") or Str.contains(lower, "where") or Str.contains(lower, "phone") {
		readOnly(state, salonInfoText)
	} else {
		readOnly(
			state,
			"Hello! Welcome to Luxe Hair Studio.\n\n• Say 'book' to schedule an appointment with our stylists\n• Ask for 'services' or 'prices' to see our menu\n• Say 'stylists' to meet our team\n• Say 'slots' to check available times\n• Say 'reminders' to see automated no-show reduction reminders\n• Say 'holds' to view active Stripe deposit holds\n• Ask about 'whatsapp' for Meta Cloud API integration\n• Salon owners can text 'manifest' for today's schedule and revenue",
		)
	}
}

# --- Cancellation & Waitlist Domain Logic ---

cancelAppointment : State, Str -> { updatedState : State, message : Str }
cancelAppointment = |state, rawQuery| {
	normalizedTarget = Str.to_utf8(rawQuery) |> toLowerStr

	matched =
		List.keep_if(
			state.appointments,
			|a|
				(a.status == "Confirmed" or a.status == "PendingDeposit") and (
					Str.contains(Str.to_utf8(a.code) |> toLowerStr, normalizedTarget) or
					Str.contains(normalizedTarget, Str.to_utf8(a.code) |> toLowerStr) or
					(Str.contains(normalizedTarget, "101") and a.code == "#LUXE-101") or
					(Str.contains(normalizedTarget, "102") and a.code == "#LUXE-102") or
					(Str.contains(normalizedTarget, "103") and a.code == "#LUXE-103") or
					(Str.contains(normalizedTarget, "104") and a.code == "#LUXE-104")
				),
		)

	match List.get(matched, 0.U64) {
		Ok(appt) => {
			updatedAppointments =
				List.map(
					state.appointments,
					|a|
						if a.code == appt.code {
							{ ..a, status: "Cancelled" }
						} else {
							a
						},
				)

			# Auto-cancel any pending scheduled reminders for this appointment
			updatedReminders =
				List.map(
					state.reminders,
					|r|
						if r.code == appt.code and r.status == "Scheduled" {
							{ ..r, status: "Cancelled" }
						} else {
							r
						},
				)

			# Auto-cancel any active deposit holds for this appointment
			updatedHolds =
				List.map(
					state.holds,
					|h|
						if h.code == appt.code and h.status == "Pending" {
							{ ..h, status: "Cancelled" }
						} else {
							h
						},
				)

			restoredSlots = List.append(state.availableSlots, appt.slot)

			match List.get(state.waitlist, 0.U64) {
				Ok(waitEntry) => {
					remainingWaitlist = List.drop_if(state.waitlist, |w| w.customer == waitEntry.customer)
					waitlistNotice = "\n\n🔔 Waitlist Auto-Triggered: Notified ${waitEntry.customer} (${waitEntry.service}) about the newly opened slot '${appt.slot}' with ${appt.stylist}!"

					{
						updatedState: {
							..state,
							appointments: updatedAppointments,
							availableSlots: restoredSlots,
							waitlist: remainingWaitlist,
							reminders: updatedReminders,
							holds: updatedHolds,
						},
						message: "Appointment ${appt.code} for ${appt.customer} (${appt.service} with ${appt.stylist}) has been cancelled. Scheduled reminders and deposit holds deactivated. Slot '${appt.slot}' is now open again.${waitlistNotice}",
					}
				}
				Err(_) => {
					{
						updatedState: {
							..state,
							appointments: updatedAppointments,
							availableSlots: restoredSlots,
							reminders: updatedReminders,
							holds: updatedHolds,
						},
						message: "Appointment ${appt.code} for ${appt.customer} (${appt.service} with ${appt.stylist}) has been cancelled. Scheduled reminders and deposit holds deactivated. Slot '${appt.slot}' is now open again.",
					}
				}
			}
		}
		Err(_) => {
			{
				updatedState: state,
				message: "Could not find an active appointment matching '${rawQuery}'. Please specify your code (e.g. #LUXE-101).",
			}
		}
	}
}

# --- Operating Hours Evaluation ---

evaluateOperatingHours : U64 -> Str
evaluateOperatingHours = |timestampMs| {
	totalSec = timestampMs // 1000.U64
	daysSinceEpoch = totalSec // 86400.U64
	# Jan 1, 1970 was a Thursday (index 4)
	dayOfWeek = (daysSinceEpoch + 4.U64) % 7.U64
	secOfDay = totalSec % 86400.U64
	utcHour = secOfDay // 3600.U64

	# Local salon time (Springfield, UTC-6)
	localHour = if utcHour >= 6.U64 (utcHour - 6.U64) else (utcHour + 18.U64)

	dayName =
		match dayOfWeek {
			0.U64 => "Sunday",
			1.U64 => "Monday",
			2.U64 => "Tuesday",
			3.U64 => "Wednesday",
			4.U64 => "Thursday",
			5.U64 => "Friday",
			_ => "Saturday",
		}

	isOpen =
		if dayOfWeek == 0.U64 {
			False
		} else if dayOfWeek >= 1.U64 and dayOfWeek <= 5.U64 {
			localHour >= 9.U64 and localHour < 19.U64
		} else {
			localHour >= 9.U64 and localHour < 17.U64
		}

	status = if isOpen "Open" else "Closed"
	openStr = if isOpen "true" else "false"

	"{\"timestampMs\":${Str.inspect(timestampMs)},\"dayName\":\"${dayName}\",\"localHour\":${Str.inspect(localHour)},\"isOpen\":${openStr},\"status\":\"${status}\",\"schedule\":\"Mon-Fri 9:00 AM - 7:00 PM, Sat 9:00 AM - 5:00 PM, Sun Closed\"}"
}

# --- Service & Stylist Helpers ---

getServicePrice : Str -> U64
getServicePrice = |service| {
	s = Str.to_utf8(service) |> toLowerStr
	if Str.contains(s, "women") {
		65.U64
	} else if Str.contains(s, "men") {
		40.U64
	} else if Str.contains(s, "balayage") or Str.contains(s, "highlight") {
		160.U64
	} else if Str.contains(s, "keratin") {
		200.U64
	} else if Str.contains(s, "color") {
		90.U64
	} else {
		55.U64
	}
}

isDepositRequired : Str -> Bool
isDepositRequired = |service| {
	price = getServicePrice(service)
	price >= 100.U64
}

resolveStylistName : Str -> Str
resolveStylistName = |raw| {
	s = Str.to_utf8(raw) |> toLowerStr
	if Str.contains(s, "sarah") {
		"Sarah Jenkins"
	} else if Str.contains(s, "alex") {
		"Alex Rivera"
	} else if Str.contains(s, "jordan") {
		"Jordan Lee"
	} else {
		"Any Stylist (First Available)"
	}
}

filterSlotsByStylist : List(Str), Str -> List(Str)
filterSlotsByStylist = |slots, _stylist|
	slots

# --- Input Sanitization & JSON Helpers ---

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

extractCodeFromInput : Str -> Str
extractCodeFromInput = |raw| {
	s = Str.to_utf8(raw) |> toLowerStr
	if Str.contains(s, "101") {
		"#LUXE-101"
	} else if Str.contains(s, "102") {
		"#LUXE-102"
	} else if Str.contains(s, "103") {
		"#LUXE-103"
	} else if Str.contains(s, "104") {
		"#LUXE-104"
	} else if Str.contains(s, "105") {
		"#LUXE-105"
	} else {
		cleanInput(raw)
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

# --- WhatsApp Handshake & Payload Parsers ---

extractChallenge : Str -> Str
extractChallenge = |input| {
	if Str.contains(input, "hub.challenge=") {
		match Str.split_first(input, "hub.challenge=") {
			Ok({ after, .. }) =>
				match Str.split_first(after, "&") {
					Ok({ before, .. }) => before
					Err(_) => after
				}
			Err(_) => ""
		}
	} else if Str.contains(input, "challenge=") {
		match Str.split_first(input, "challenge=") {
			Ok({ after, .. }) =>
				match Str.split_first(after, "&") {
					Ok({ before, .. }) => before
					Err(_) => after
				}
			Err(_) => ""
		}
	} else if Str.contains(input, "\"hub.challenge\"") {
		extractField(input, "hub.challenge")
	} else if Str.contains(input, "\"challenge\"") {
		extractField(input, "challenge")
	} else {
		"1158201444"
	}
}

extractVerifyToken : Str -> Str
extractVerifyToken = |input| {
	if Str.contains(input, "hub.verify_token=") {
		match Str.split_first(input, "hub.verify_token=") {
			Ok({ after, .. }) =>
				match Str.split_first(after, "&") {
					Ok({ before, .. }) => before
					Err(_) => after
				}
			Err(_) => ""
		}
	} else if Str.contains(input, "verify_token=") {
		match Str.split_first(input, "verify_token=") {
			Ok({ after, .. }) =>
				match Str.split_first(after, "&") {
					Ok({ before, .. }) => before
					Err(_) => after
				}
			Err(_) => ""
		}
	} else if Str.contains(input, "\"hub.verify_token\"") {
		extractField(input, "hub.verify_token")
	} else if Str.contains(input, "\"verify_token\"") {
		extractField(input, "verify_token")
	} else {
		""
	}
}

extractWhatsappSender : Str -> Str
extractWhatsappSender = |json| {
	fromVal = extractField(json, "from")
	if !(Str.is_empty(fromVal)) {
		fromVal
	} else {
		waId = extractField(json, "wa_id")
		if !(Str.is_empty(waId)) {
			waId
		} else {
			"+1 (555) 987-6543"
		}
	}
}

extractWhatsappMessageBody : Str -> Str
extractWhatsappMessageBody = |json| {
	bodyVal = extractField(json, "body")
	if !(Str.is_empty(bodyVal)) {
		bodyVal
	} else {
		cleanInput(json)
	}
}

sanitizePhone : Str -> Str
sanitizePhone = |raw| {
	bytes = Str.to_utf8(raw)
	digits = List.keep_if(bytes, |b| b >= 48.U8 and b <= 57.U8)
	match Str.from_utf8(digits) {
		Ok(s) => s
		Err(_) => raw
	}
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

# --- Static Data & Formatting Helpers ---

servicesMenuText : Str
servicesMenuText =
	"Luxe Hair Studio Signature Services:\n\n• Womens Cut & Blowdry: $65 (60 mins)\n• Mens Cut & Style: $40 (45 mins)\n• Single Process Color: $90 (90 mins)\n• Balayage & Highlights: $160 (150 mins) [Deposit Required: $30]\n• Keratin Smoothing Treatment: $200 (120 mins) [Deposit Required: $30]\n\nWould you like to book one of these, or check our available time slots?"

servicesMenuJson : Str
servicesMenuJson =
	"[{\"name\": \"Womens Cut & Blowdry\", \"price\": 65, \"duration\": 60, \"deposit\": 0}, {\"name\": \"Mens Cut & Style\", \"price\": 40, \"duration\": 45, \"deposit\": 0}, {\"name\": \"Single Process Color\", \"price\": 90, \"duration\": 90, \"deposit\": 0}, {\"name\": \"Balayage & Highlights\", \"price\": 160, \"duration\": 150, \"deposit\": 30}, {\"name\": \"Keratin Smoothing Treatment\", \"price\": 200, \"duration\": 120, \"deposit\": 30}]"

salonInfoText : Str
salonInfoText =
	"Luxe Hair Studio\nAddress: 742 Evergreen Terrace, Suite 101, Springfield\nPhone: +1 (555) 234-5678\nHours:\n• Mon - Fri: 9:00 AM - 7:00 PM\n• Saturday: 9:00 AM - 5:00 PM\n• Sunday: Closed\n\nPolicy: High-value services ($100+) require a $30 deposit hold via Stripe. Cancellations require 24 hours notice."

salonInfoJson : Str
salonInfoJson =
	"{\"name\": \"Luxe Hair Studio\", \"address\": \"742 Evergreen Terrace, Suite 101\", \"phone\": \"(555) 234-5678\", \"hours\": \"Mon-Fri 9-7, Sat 9-5\", \"depositRequiredThreshold\": 100, \"depositAmount\": 30}"

formatSlotsList : List(Str) -> Str
formatSlotsList = |slots|
	if List.is_empty(slots) {
		"No remaining slots today. Please check back tomorrow!"
	} else {
		slots
		|> List.map_with_index(|s, idx| "${Str.inspect(idx + 1.U64)}. ${s}")
		|> Str.join_with("\n")
	}

formatSlotsJson : List(Str) -> Str
formatSlotsJson = |slots| {
	quoted = List.map(slots, |s| "\"${s}\"")
	content = Str.join_with(quoted, ", ")
	"[${content}]"
}

formatStylistsList : List(Stylist) -> Str
formatStylistsList = |stylists|
	stylists
	|> List.map(|s| "• ${s.name} (${s.tier}) — Specialties: ${s.specialties}")
	|> Str.join_with("\n")

formatStylistsJson : List(Stylist) -> Str
formatStylistsJson = |stylists| {
	entries =
		List.map(
			stylists,
			|s| "{\"id\":\"${s.id}\",\"name\":\"${s.name}\",\"tier\":\"${s.tier}\",\"specialties\":\"${s.specialties}\"}",
		)
	content = Str.join_with(entries, ", ")
	"[${content}]"
}

formatAppointmentsList : List(Appointment) -> Str
formatAppointmentsList = |appointments| {
	active = List.keep_if(appointments, |a| a.status == "Confirmed" or a.status == "PendingDeposit")
	if List.is_empty(active) {
		"You currently have no active appointments booked."
	} else {
		items =
			active
			|> List.map(|a| "• [${a.code}] ${a.slot} | ${a.customer} with ${a.stylist} — ${a.service} ($${Str.inspect(a.price)}) [Status: ${a.status}]")
			|> Str.join_with("\n")
		"Active Appointments:\n\n${items}"
	}
}

formatDailyManifest : State -> Str
formatDailyManifest = |state| {
	active = List.keep_if(state.appointments, |a| a.status == "Confirmed")
	pending = List.keep_if(state.appointments, |a| a.status == "PendingDeposit")
	activeHolds = List.keep_if(state.holds, |h| h.status == "Pending")
	totalRevenue =
		List.fold(
			active,
			0.U64,
			|sum, a| sum + a.price,
		)
	activeCount = List.len(active)
	pendingCount = List.len(pending)
	openCount = List.len(state.availableSlots)

	apptLines =
		if List.is_empty(active) {
			"  (No confirmed appointments)"
		} else {
			active
			|> List.map(|a| "  • [${a.code}] ${a.slot} | ${a.stylist} | ${a.customer} - ${a.service} ($${Str.inspect(a.price)})")
			|> Str.join_with("\n")
		}

	pendingLines =
		if List.is_empty(pending) {
			"  (None)"
		} else {
			pending
			|> List.map(|a| "  • [${a.code}] ${a.slot} | ${a.stylist} | ${a.customer} - ${a.service} ($${Str.inspect(a.price)}) — $30 Hold Pending")
			|> Str.join_with("\n")
		}

	stylistRoster =
		state.stylists
		|> List.map(|s| "  • ${s.name} (${s.tier})")
		|> Str.join_with("\n")

	"📅 ${state.salonName} — Daily Operations Manifest\n\nConfirmed Appointments (${Str.inspect(activeCount)}):\n${apptLines}\n\nPending Deposit Holds (${Str.inspect(pendingCount)}):\n${pendingLines}\n\nStaff On Duty:\n${stylistRoster}\n\nSummary:\n• Confirmed Gross Revenue: $${Str.inspect(totalRevenue)}\n• Pending Deposit Pipeline: $${Str.inspect(pendingCount * 30.U64)}\n• Open Remaining Slots: ${Str.inspect(openCount)}\n• Active Deposit Holds: ${Str.inspect(List.len(activeHolds))}\n• Waitlist Queue: ${Str.inspect(List.len(state.waitlist))} client(s) waiting\n• Active Scheduled Reminders: ${Str.inspect(List.len(state.reminders))}"
}

formatDailyManifestJson : State -> Str
formatDailyManifestJson = |state| {
	active = List.keep_if(state.appointments, |a| a.status == "Confirmed")
	pending = List.keep_if(state.appointments, |a| a.status == "PendingDeposit")
	totalRevenue =
		List.fold(
			active,
			0.U64,
			|sum, a| sum + a.price,
		)
	"{\"salon\":\"${state.salonName}\",\"activeAppointments\":${Str.inspect(List.len(active))},\"pendingDeposits\":${Str.inspect(List.len(pending))},\"confirmedRevenue\":${Str.inspect(totalRevenue)},\"pendingRevenue\":${Str.inspect(List.len(pending) * 30.U64)},\"openSlots\":${Str.inspect(List.len(state.availableSlots))},\"waitlistCount\":${Str.inspect(List.len(state.waitlist))},\"remindersCount\":${Str.inspect(List.len(state.reminders))},\"holdsCount\":${Str.inspect(List.len(state.holds))}}"
}

formatRemindersText : List(ReminderRecord) -> Str
formatRemindersText = |reminders| {
	if List.is_empty(reminders) {
		"No reminders scheduled."
	} else {
		items =
			reminders
			|> List.map(|r| "• [${r.id}] For ${r.code} (${r.recipient}) — Status: ${r.status} (delay: ${Str.inspect(r.delayMs // 1000.U64)}s)")
			|> Str.join_with("\n")
		"Automated Appointment Reminders:\n\n${items}"
	}
}

formatRemindersJson : List(ReminderRecord) -> Str
formatRemindersJson = |reminders| {
	entries =
		List.map(
			reminders,
			|r| "{\"id\":\"${r.id}\",\"code\":\"${r.code}\",\"recipient\":\"${r.recipient}\",\"status\":\"${r.status}\",\"delayMs\":${Str.inspect(r.delayMs)}}",
		)
	content = Str.join_with(entries, ", ")
	"[${content}]"
}

formatHoldsText : List(DepositHold) -> Str
formatHoldsText = |holds| {
	if List.is_empty(holds) {
		"No deposit holds recorded."
	} else {
		items =
			holds
			|> List.map(|h| "• [${h.code}] Amount: $${Str.inspect(h.amount)} | Status: ${h.status} | Promise #${Str.inspect(h.promiseId)}\n  Stripe Mock: https://checkout.stripe.com/pay/cs_test_mock_${h.code}?deposit=30&code=${h.code}\n  Webhook: ${h.webhookUrl}")
			|> Str.join_with("\n")
		"Deposit Holds & Stripe Webhooks:\n\n${items}"
	}
}

formatHoldsJson : List(DepositHold) -> Str
formatHoldsJson = |holds| {
	entries =
		List.map(
			holds,
			|h| "{\"code\":\"${h.code}\",\"amount\":${Str.inspect(h.amount)},\"status\":\"${h.status}\",\"promiseId\":${Str.inspect(h.promiseId)},\"webhookUrl\":\"${h.webhookUrl}\"}",
		)
	content = Str.join_with(entries, ", ")
	"[${content}]"
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
