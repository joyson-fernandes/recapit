import Foundation
import EventKit

struct UpcomingMeeting: Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let calendarTitle: String
    let attendeeNames: [String]
    let meetingURL: URL?
}

protocol CalendarMonitorDelegate: AnyObject {
    func calendarMonitor(_ monitor: CalendarMonitor, didUpdateUpcoming: [UpcomingMeeting])
    func calendarMonitor(_ monitor: CalendarMonitor, meetingStartingSoon: UpcomingMeeting)
    func calendarMonitor(_ monitor: CalendarMonitor, meetingNow: UpcomingMeeting)
}

final class CalendarMonitor {
    weak var delegate: CalendarMonitorDelegate?
    private let store = EKEventStore()
    private let settings: SettingsStore
    private var timer: Timer?
    private var alreadyNotifiedSoon = Set<String>()
    private var alreadyNotifiedNow = Set<String>()

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func requestAccess() async -> Bool {
        do {
            if #available(macOS 14.0, *) {
                return try await store.requestFullAccessToEvents()
            } else {
                return try await withCheckedThrowingContinuation { cont in
                    store.requestAccess(to: .event) { granted, error in
                        if let e = error { cont.resume(throwing: e) } else { cont.resume(returning: granted) }
                    }
                }
            }
        } catch {
            return false
        }
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let calendars = store.calendars(for: .event).filter { settings.watchedCalendars.isEmpty || settings.watchedCalendars.contains($0.calendarIdentifier) }
        let now = Date()
        let end = now.addingTimeInterval(24 * 60 * 60)
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: calendars)
        let events = store.events(matching: predicate)

        var upcoming: [UpcomingMeeting] = []
        for ev in events {
            let classify = MeetingClassifier.classify(
                title: ev.title,
                notes: ev.notes,
                location: ev.location,
                url: ev.url,
                attendeeCount: (ev.attendees?.count ?? 1) - 1
            )
            guard classify.isMeeting else { continue }
            let m = UpcomingMeeting(
                id: ev.eventIdentifier,
                title: ev.title ?? "Untitled",
                startDate: ev.startDate,
                endDate: ev.endDate,
                calendarTitle: ev.calendar.title,
                attendeeNames: (ev.attendees ?? []).compactMap { $0.name },
                meetingURL: classify.detectedURL
            )
            upcoming.append(m)
        }

        delegate?.calendarMonitor(self, didUpdateUpcoming: upcoming)

        for m in upcoming {
            let secondsUntil = m.startDate.timeIntervalSinceNow
            if secondsUntil <= 60 && secondsUntil > -10 && !alreadyNotifiedSoon.contains(m.id) {
                alreadyNotifiedSoon.insert(m.id)
                delegate?.calendarMonitor(self, meetingStartingSoon: m)
            }
            if secondsUntil <= 0 && secondsUntil > -30 && !alreadyNotifiedNow.contains(m.id) {
                alreadyNotifiedNow.insert(m.id)
                delegate?.calendarMonitor(self, meetingNow: m)
            }
        }
    }
}
