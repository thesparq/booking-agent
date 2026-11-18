module [
	agent,
	State,
	NotificationRecord,
	defaultState,
	queueNotificationTool,
	dispatchPendingTool,
	notificationLogTool,
	dispatcherStatusTool,
]

import pf.Golem exposing [Agent, Tool, agent, reply, readOnly, tool, statefulTool, param]
import pf.Types exposing [Result]

# --- Notification Dispatcher Domain Types ---

NotificationRecord : {
	id : Str,
	channel : Str,
	recipient : Str,
	template : Str,
	content : Str,
	status : Str,
	timestamp : Str,
}

State : {
	dispatcherName : Str,
	queue : List(NotificationRecord),
	history : List(NotificationRecord),
	sentCount : U64,
	failedCount : U64,
}

# --- Initial State ---

defaultState : State
defaultState = {
	dispatcherName: "Luxe Salon Notification Service",
	queue: [],
	history: [
		{
			id: "NOTIF-001",
			channel: "whatsapp",
			recipient: "+1 (555) 234-5678",
			template: "booking_confirmed",
			content: "Your appointment #LUXE-101 has been confirmed for Today 10:00 AM with Sarah Jenkins.",
			status: "delivered",
			timestamp: "2026-11-16T09:00:00Z",
		},
		{
			id: "NOTIF-002",
			channel: "sms",
			recipient: "+1 (555) 345-6789",
			template: "booking_confirmed",
			content: "Your appointment #LUXE-102 has been confirmed for Today 11:30 AM with Jordan Lee.",
			status: "delivered",
			timestamp: "2026-11-16T09:30:00Z",
		},
	],
	sentCount: 2.U64,
	failedCount: 0.U64,
}

# --- Tools ---

queueNotificationTool : Tool(State)
queueNotificationTool = statefulTool({
	name: "queue_notification",
	description: "Queue an outbound customer notification (WhatsApp, SMS, or email)",
	params: [
		param("channel", "Communication channel (whatsapp, sms, email)"),
		param("recipient", "Recipient phone number or address"),
		param("template", "Notification template type (booking_confirmed, reminder_24h, reminder_2h, waitlist_alert)"),
		param("content", "Rendered text body of the notification"),
	],
	execute: |st, args| {
		channel = extractParam(args, "channel", 0.U64)
		recipient = extractParam(args, "recipient", 1.U64)
		template = extractParam(args, "template", 2.U64)
		content = extractParam(args, "content", 3.U64)

		nextNum = List.len(st.queue) + List.len(st.history) + 1.U64
		id = "NOTIF-00${Str.inspect(nextNum)}"

		newRecord : NotificationRecord
		newRecord = {
			id: id,
			channel: if Str.is_empty(channel) "whatsapp" else channel,
			recipient: recipient,
			template: template,
			content: content,
			status: "queued",
			timestamp: "2026-11-16T15:00:00Z",
		}

		updatedQueue = List.append(st.queue, newRecord)

		Ok({
			state: {
				..st,
				queue: updatedQueue,
			},
			stateChanged: True,
			output: "Notification ${id} queued for ${recipient} via ${newRecord.channel}.",
		})
	},
})

dispatchPendingTool : Tool(State)
dispatchPendingTool = statefulTool({
	name: "dispatch_pending",
	description: "Flush and dispatch all queued outbound notifications to recipients",
	params: [],
	execute: |st, _args| {
		queuedCount = List.len(st.queue)
		if queuedCount == 0.U64 {
			Ok({
				state: st,
				stateChanged: False,
				output: "No pending notifications in queue to dispatch.",
			})
		} else {
			deliveredList =
				List.map(
					st.queue,
					|n| { ..n, status: "delivered" },
				)
			updatedHistory = List.concat(st.history, deliveredList)
			newSentCount = st.sentCount + queuedCount

			Ok({
				state: {
					..st,
					queue: [],
					history: updatedHistory,
					sentCount: newSentCount,
				},
				stateChanged: True,
				output: "Successfully dispatched ${Str.inspect(queuedCount)} pending notification(s). Total sent: ${Str.inspect(newSentCount)}.",
			})
		}
	},
})

notificationLogTool : Tool(State)
notificationLogTool = tool({
	name: "get_notification_log",
	description: "Returns full delivery history and active queue of notifications",
	params: [],
	execute: |st, _args|
		Ok(formatNotificationLogJson(st)),
})

dispatcherStatusTool : Tool(State)
dispatcherStatusTool = tool({
	name: "check_dispatcher_status",
	description: "Returns health, queue depth, and metrics for the notification service",
	params: [],
	execute: |st, _args|
		Ok(formatStatusJson(st)),
})

# --- Agent Definition ---

agent : Agent(State)
agent = Golem.agent({
	name: "notification-dispatcher",
	initial: defaultState,
	tools: [
		queueNotificationTool,
		dispatchPendingTool,
		notificationLogTool,
		dispatcherStatusTool,
	],
	onMessage: handleMessage,
})

# --- Conversational Message Handler ---

handleMessage : State, Str => Result({ state : State, stateChanged : Bool, response : Str }, Str)
handleMessage = |state, rawInput| {
	inputClean = cleanInput(rawInput)
	lower = Str.to_utf8(inputClean) |> toLowerStr

	if Str.contains(lower, "status") or Str.contains(lower, "health") {
		readOnly(state, formatStatusText(state))
	} else if Str.contains(lower, "queue") or Str.contains(lower, "pending") {
		readOnly(state, formatQueueText(state.queue))
	} else if Str.contains(lower, "log") or Str.contains(lower, "history") or Str.contains(lower, "sent") {
		readOnly(state, formatHistoryText(state.history))
	} else if Str.contains(lower, "dispatch") or Str.contains(lower, "flush") or Str.contains(lower, "send") {
		queuedCount = List.len(state.queue)
		if queuedCount == 0.U64 {
			readOnly(state, "Queue is currently empty. No pending messages to dispatch.")
		} else {
			deliveredList =
				List.map(
					state.queue,
					|n| { ..n, status: "delivered" },
				)
			updatedHistory = List.concat(state.history, deliveredList)
			newSentCount = state.sentCount + queuedCount

			reply(
				{
					..state,
					queue: [],
					history: updatedHistory,
					sentCount: newSentCount,
				},
				"Dispatched ${Str.inspect(queuedCount)} pending notification(s) across WhatsApp & SMS. Lifetime deliveries: ${Str.inspect(newSentCount)}.",
			)
		}
	} else if Str.contains(lower, "clear") {
		reply(
			{ ..state, queue: [] },
			"Notification queue has been cleared.",
		)
	} else {
		readOnly(
			state,
			"🔔 Luxe Salon Notification Dispatcher Service\n\nCommands:\n• 'status' — Check queue size and delivery totals\n• 'queue' — View pending notifications waiting for dispatch\n• 'dispatch' — Flush queue and send all pending notifications\n• 'log' — View audit history of sent notifications",
		)
	}
}

# --- Formatting & JSON Helpers ---

formatStatusText : State -> Str
formatStatusText = |state|
	"📡 Notification Dispatcher Status: Operational\n\n• Active Queue: ${Str.inspect(List.len(state.queue))} pending\n• Lifetime Sent: ${Str.inspect(state.sentCount)}\n• Failed: ${Str.inspect(state.failedCount)}\n• Active Channels: WhatsApp Business Cloud, SMS Gateway"

formatStatusJson : State -> Str
formatStatusJson = |state|
	"{\"status\":\"operational\",\"queueDepth\":${Str.inspect(List.len(state.queue))},\"lifetimeSent\":${Str.inspect(state.sentCount)},\"failed\":${Str.inspect(state.failedCount)},\"channels\":[\"whatsapp\",\"sms\",\"email\"]}"

formatQueueText : List(NotificationRecord) -> Str
formatQueueText = |queue|
	if List.is_empty(queue) {
		"Queue is currently empty."
	} else {
		items =
			queue
			|> List.map(|n| "• [${n.id}] [${n.channel}] To: ${n.recipient} | Template: ${n.template}\n  Preview: \"${n.content}\"")
			|> Str.join_with("\n\n")
		"Pending Notification Queue (${Str.inspect(List.len(queue))}):\n\n${items}"
	}

formatHistoryText : List(NotificationRecord) -> Str
formatHistoryText = |history|
	if List.is_empty(history) {
		"No notification history recorded."
	} else {
		items =
			history
			|> List.map(|n| "• [${n.id}] [${n.channel}] To: ${n.recipient} (${n.status})\n  \"${n.content}\"")
			|> Str.join_with("\n")
		"Recent Delivery History:\n\n${items}"
	}

formatNotificationLogJson : State -> Str
formatNotificationLogJson = |state| {
	entries =
		List.concat(state.history, state.queue)
		|> List.map(|n| "{\"id\":\"${n.id}\",\"channel\":\"${n.channel}\",\"recipient\":\"${n.recipient}\",\"status\":\"${n.status}\"}")
	content = Str.join_with(entries, ", ")
	"[${content}]"
}

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
