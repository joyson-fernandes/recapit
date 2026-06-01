import Foundation
import Combine

@MainActor
final class PopoverViewModel: ObservableObject {
    @Published var upcoming: [UpcomingMeeting] = []
    @Published var recentMeetings: [Meeting] = []
    @Published var currentRecording: Meeting? = nil
    @Published var isProcessing: Bool = false

    func updateUpcoming(_ items: [UpcomingMeeting]) { upcoming = items }
    func updateRecent(_ items: [Meeting]) { recentMeetings = items }
}
