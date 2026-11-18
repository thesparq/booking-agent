app [agent] { pf: platform "https://github.com/thesparq/roc-golem/releases/download/v1.4.2/sCMpPilBt65rdAVsPINB5xqG7FtlRnTGj6Vj61B6ulE.tar.zst" }
import pf.Golem exposing [Agent, bundleAll, erase]
import BookingCoordinator
import NotificationDispatcher
import SalonAnalytics

State : {}

agent : Agent(State)
agent = bundleAll([
	erase(BookingCoordinator.agent),
	erase(NotificationDispatcher.agent),
	erase(SalonAnalytics.agent),
])
