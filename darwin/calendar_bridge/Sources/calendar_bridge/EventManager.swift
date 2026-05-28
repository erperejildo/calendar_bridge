import EventKit
import Foundation

class EventManager {
    private let eventStore: EKEventStore
    
    init(eventStore: EKEventStore) {
        self.eventStore = eventStore
    }
    
    private func eventIdString(_ event: EKEvent) -> String {
        #if os(iOS)
        return event.eventIdentifier
        #elseif os(macOS)
        return event.eventIdentifier ?? ""
        #endif
    }
    
    func retrieveEvents(calendarId: String, arguments: [String: Any]) throws -> [[String: Any]] {
        guard let calendar = eventStore.calendar(withIdentifier: calendarId) else {
            throw CalendarError.calendarNotFound(calendarId)
        }
        
        let startDate = extractDate(from: arguments["startDate"])
        let endDate = extractDate(from: arguments["endDate"])
        let eventIds = arguments["eventIds"] as? [String]
        
        var events: [EKEvent] = []
        
        if let eventIds = eventIds {
            for eventId in eventIds {
                if let event = eventStore.event(withIdentifier: eventId) {
                    events.append(event)
                }
            }
        } else {
            let predicate = eventStore.predicateForEvents(
                withStart: startDate ?? Date.distantPast,
                end: endDate ?? Date.distantFuture,
                calendars: [calendar]
            )
            events = eventStore.events(matching: predicate)
        }
        
        return events.map { event in
            return eventToDict(event: event)
        }
    }
    
    func createEvent(arguments: [String: Any]) throws -> String {
        guard let calendarId = arguments["calendarId"] as? String else {
            throw CalendarError.invalidArgument("Calendar ID is required")
        }
        
        guard let calendar = eventStore.calendar(withIdentifier: calendarId) else {
            throw CalendarError.calendarNotFound(calendarId)
        }
        
        guard calendar.allowsContentModifications else {
            throw CalendarError.invalidArgument("Cannot create event in read-only calendar")
        }
        
        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        
        try populateEventFromDict(event: event, dict: arguments)
        
        do {
            try eventStore.save(event, span: .thisEvent)
            return event.eventIdentifier
        } catch {
            throw CalendarError.platformError("Failed to create event: \(error.localizedDescription)")
        }
    }
    
    func updateEvent(arguments: [String: Any]) throws -> String {
        guard let eventId = arguments["eventId"] as? String else {
            throw CalendarError.invalidArgument("Event ID is required")
        }
        
        guard let event = eventStore.event(withIdentifier: eventId) else {
            throw CalendarError.eventNotFound(eventId)
        }
        
        guard event.calendar.allowsContentModifications else {
            throw CalendarError.invalidArgument("Cannot update event in read-only calendar")
        }
        
        try populateEventFromDict(event: event, dict: arguments)
        
        do {
            try eventStore.save(event, span: .thisEvent)
            return event.eventIdentifier
        } catch {
            throw CalendarError.platformError("Failed to update event: \(error.localizedDescription)")
        }
    }
    
    func deleteEvent(calendarId: String, eventId: String) throws -> Bool {
        guard let calendar = eventStore.calendar(withIdentifier: calendarId) else {
            throw CalendarError.calendarNotFound(calendarId)
        }
        
        guard let event = eventStore.event(withIdentifier: eventId) else {
            throw CalendarError.eventNotFound(eventId)
        }
        
        guard calendar.allowsContentModifications else {
            throw CalendarError.invalidArgument("Cannot delete event from read-only calendar")
        }
        
        do {
            try eventStore.remove(event, span: .thisEvent)
            return true
        } catch {
            throw CalendarError.platformError("Failed to delete event: \(error.localizedDescription)")
        }
    }
    
    func deleteEventInstance(calendarId: String, eventId: String, startDate: Date, followingInstances: Bool) async throws -> Bool {
        guard let calendar = eventStore.calendar(withIdentifier: calendarId) else {
            throw CalendarError.calendarNotFound(calendarId)
        }
        
        guard let event = eventStore.event(withIdentifier: eventId) else {
            throw CalendarError.eventNotFound(eventId)
        }
        
        guard calendar.allowsContentModifications else {
            throw CalendarError.invalidArgument("Cannot delete event from read-only calendar")
        }
        
        do {
            let span: EKSpan = followingInstances ? .futureEvents : .thisEvent
            try eventStore.remove(event, span: span)
            return true
        } catch {
            throw CalendarError.platformError("Failed to delete event instance: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func populateEventFromDict(event: EKEvent, dict: [String: Any]) throws {
        if let title = dict["title"] as? String {
            event.title = title
        }
        
        if let description = dict["description"] as? String {
            event.notes = description
        }
        
        if let location = dict["location"] as? String {
            event.location = location
        }
        
        if let url = dict["url"] as? String {
            event.url = URL(string: url)
        }
        
        if let isAllDay = dict["allDay"] as? Bool {
            event.isAllDay = isAllDay
        }
        
        if let startDate = extractDate(from: dict["start"]) {
            event.startDate = startDate
        }
        
        if let endDate = extractDate(from: dict["end"]) {
            event.endDate = endDate
        }
        
        if let attendeesData = dict["attendees"] as? [[String: Any]] {
            setAttendees(attendeesData, event)
        }
        
        if let remindersData = dict["reminders"] as? [[String: Any]] {
            let alarms = remindersData.compactMap { reminderDict -> EKAlarm? in
                guard let minutes = reminderDict["minutes"] as? Int else { return nil }
                return EKAlarm(relativeOffset: TimeInterval(-minutes * 60))
            }
            event.alarms = alarms
        }
        
        if let availabilityString = dict["availability"] as? String {
            switch availabilityString {
            case "busy":
                event.availability = .busy
            case "free":
                event.availability = .free
            case "tentative":
                event.availability = .tentative
            case "out-of-office":
                if #available(iOS 9.0, *) {
                    event.availability = .unavailable
                } else {
                    event.availability = .busy
                }
            default:
                event.availability = .busy
            }
        }
        
        // Handle recurrence rule - accept both string and dictionary formats
        if let recurrenceString = dict["recurrenceRule"] as? String {
            // String format from rrule package: "RRULE:FREQ=DAILY;COUNT=10"
            if let rules = parseRRULEString(recurrenceString) {
                event.recurrenceRules = rules
            }
        } else if let recurrenceDict = dict["recurrenceRule"] as? [String: Any] {
            // Dictionary format (legacy support)
            event.recurrenceRules = createEKRecurrenceRules(recurrenceDict)
        }
    }
    
    private func eventToDict(event: EKEvent) -> [String: Any] {
        var dict: [String: Any] = [
            "eventId": eventIdString(event),
            "calendarId": event.calendar.calendarIdentifier,
            "title": event.title ?? "",
            "allDay": event.isAllDay
        ]
        
        if let description = event.notes {
            dict["description"] = description
        }
        
        if let location = event.location {
            dict["location"] = location
        }
        
        if let url = event.url {
            dict["url"] = url.absoluteString
        }
        
        dict["start"] = Int(event.startDate.timeIntervalSince1970 * 1000)
        dict["end"] = Int(event.endDate.timeIntervalSince1970 * 1000)
        
        if let attendees = event.attendees {
            let attendeesData = attendees.map { attendee in
                #if os(iOS)
                var email = ""
                let url = attendee.url
                if url.scheme == "mailto" {
                    email = String(url.absoluteString.dropFirst(7))
                } else {
                    email = url.absoluteString
                }
                #elseif os(macOS)
                let email = attendee.url.absoluteString
                #endif
                return [
                    "email": email,
                    "name": attendee.name ?? "",
                    "role": attendeeRoleToString(attendee.participantRole),
                    "status": attendeeStatusToString(attendee.participantStatus)
                ]
            }
            dict["attendees"] = attendeesData
        }
        
        if let alarms = event.alarms {
            let remindersData = alarms.compactMap { alarm -> [String: Any]? in
                #if os(iOS)
                guard let relativeOffset = alarm.relativeOffset as? TimeInterval else { return nil }
                #elseif os(macOS)
                let relativeOffset = alarm.relativeOffset
                #endif
                return ["minutes": Int(-relativeOffset / 60)]
            }
            dict["reminders"] = remindersData
        }
        
        dict["availability"] = availabilityToString(event.availability)
        dict["status"] = statusToString(event.status)
        
        // Convert recurrence rules to RRULE string format
        if let recurrenceRules = event.recurrenceRules, !recurrenceRules.isEmpty {
            if let rruleString = convertRecurrenceRulesToString(recurrenceRules) {
                dict["recurrenceRule"] = rruleString
            }
        }
        
        var originalStartDate: Int64? = nil
        
        if let masterItem = eventStore.calendarItem(withIdentifier: event.calendarItemIdentifier) as? EKEvent {
            originalStartDate = Int64(masterItem.startDate.millisecondsSinceEpoch)
        } else {
            if event.hasRecurrenceRules {
                originalStartDate = Int64(event.startDate.millisecondsSinceEpoch)
            } else {
                originalStartDate = Int64(event.startDate.millisecondsSinceEpoch)
            }
        }
        
        if let originalStart = originalStartDate {
            dict["originalStart"] = originalStart
        }
        
        return dict
    }
    
    private func extractDate(from value: Any?) -> Date? {
        guard let timestamp = value as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: timestamp.doubleValue / 1000.0)
    }
    
    private func attendeeRoleToString(_ role: EKParticipantRole) -> String {
        switch role {
        case .required:
            return "required"
        case .optional:
            return "optional"
        case .chair:
            return "chair"
        case .nonParticipant:
            return "non-participant"
        case .unknown:
            return "unknown"
        @unknown default:
            return "required"
        }
    }
    
    private func attendeeStatusToString(_ status: EKParticipantStatus) -> String {
        switch status {
        case .unknown:
            return "unknown"
        case .pending:
            return "pending"
        case .accepted:
            return "accepted"
        case .declined:
            return "declined"
        case .tentative:
            return "tentative"
        case .delegated:
            return "tentative"
        case .completed:
            return "accepted"
        case .inProcess:
            return "pending"
        @unknown default:
            return "unknown"
        }
    }
    
    private func availabilityToString(_ availability: EKEventAvailability) -> String {
        switch availability {
        case .notSupported:
            return "busy"
        case .busy:
            return "busy"
        case .free:
            return "free"
        case .tentative:
            return "tentative"
        case .unavailable:
            return "out-of-office"
        @unknown default:
            return "busy"
        }
    }
    
    private func statusToString(_ status: EKEventStatus) -> String {
        #if os(iOS)
        switch status {
        case .none:
            return "confirmed"
        case .confirmed:
            return "confirmed"
        case .tentative:
            return "tentative"
        case .canceled:
            return "cancelled"
        @unknown default:
            return "confirmed"
        }
        #elseif os(macOS)
        switch status {
        case .none:
            return "confirmed"
        case .confirmed:
            return "confirmed"
        case .tentative:
            return "tentative"
        case .canceled:
            return "cancelled"
        @unknown default:
            return "confirmed"
        }
        #endif
    }
    
    // MARK: - Recurrence Rule Handling
    
    private func parseRRULEString(_ rruleString: String) -> [EKRecurrenceRule]? {
        // Remove "RRULE:" prefix if present
        var ruleString = rruleString
        if ruleString.hasPrefix("RRULE:") {
            ruleString = String(ruleString.dropFirst(6))
        }
        
        // Parse the RRULE string into components
        var components: [String: String] = [:]
        let parts = ruleString.split(separator: ";")
        
        for part in parts {
            let keyValue = part.split(separator: "=", maxSplits: 1)
            if keyValue.count == 2 {
                components[String(keyValue[0])] = String(keyValue[1])
            }
        }
        
        // Extract frequency (required)
        guard let freqString = components["FREQ"] else {
            return nil
        }
        
        var ekFrequency: EKRecurrenceFrequency
        switch freqString.uppercased() {
        case "DAILY":
            ekFrequency = .daily
        case "WEEKLY":
            ekFrequency = .weekly
        case "MONTHLY":
            ekFrequency = .monthly
        case "YEARLY":
            ekFrequency = .yearly
        default:
            return nil
        }
        
        // Extract interval (optional, default 1)
        let interval = components["INTERVAL"].flatMap { Int($0) } ?? 1
        
        // Extract end condition
        var recurrenceEnd: EKRecurrenceEnd?
        if let countString = components["COUNT"], let count = Int(countString), count > 0 {
            recurrenceEnd = EKRecurrenceEnd(occurrenceCount: count)
        } else if let untilString = components["UNTIL"] {
            if let endDate = parseUntilDate(untilString) {
                recurrenceEnd = EKRecurrenceEnd(end: endDate)
            }
        }
        
        // Parse BYDAY
        var daysOfWeek: [EKRecurrenceDayOfWeek]?
        if let byDayString = components["BYDAY"] {
            let dayStrings = byDayString.split(separator: ",").map { String($0) }
            daysOfWeek = dayStrings.compactMap { recurrenceDayOfWeekFromString($0) }
        }
        
        // Parse BYMONTHDAY
        var daysOfMonth: [NSNumber]?
        if let byMonthDayString = components["BYMONTHDAY"] {
            let days = byMonthDayString.split(separator: ",").compactMap { Int($0) }
            daysOfMonth = days.map { NSNumber(value: $0) }
        }
        
        // Parse BYMONTH
        var monthsOfYear: [NSNumber]?
        if let byMonthString = components["BYMONTH"] {
            let months = byMonthString.split(separator: ",").compactMap { Int($0) }
            monthsOfYear = months.map { NSNumber(value: $0) }
        }
        
        // Parse BYYEARDAY
        var daysOfYear: [NSNumber]?
        if let byYearDayString = components["BYYEARDAY"] {
            let days = byYearDayString.split(separator: ",").compactMap { Int($0) }
            daysOfYear = days.map { NSNumber(value: $0) }
        }
        
        // Parse BYWEEKNO
        var weeksOfYear: [NSNumber]?
        if let byWeekNoString = components["BYWEEKNO"] {
            let weeks = byWeekNoString.split(separator: ",").compactMap { Int($0) }
            weeksOfYear = weeks.map { NSNumber(value: $0) }
        }
        
        // Parse BYSETPOS
        var setPositions: [NSNumber]?
        if let bySetPosString = components["BYSETPOS"] {
            let positions = bySetPosString.split(separator: ",").compactMap { Int($0) }
            setPositions = positions.map { NSNumber(value: $0) }
        }
        
        let rule = EKRecurrenceRule(
            recurrenceWith: ekFrequency,
            interval: interval,
            daysOfTheWeek: daysOfWeek,
            daysOfTheMonth: daysOfMonth,
            monthsOfTheYear: monthsOfYear,
            weeksOfTheYear: weeksOfYear,
            daysOfTheYear: daysOfYear,
            setPositions: setPositions,
            end: recurrenceEnd
        )
        
        return [rule]
    }
    
    private func convertRecurrenceRulesToString(_ rules: [EKRecurrenceRule]) -> String? {
        guard let rule = rules.first else { return nil }
        
        var components: [String] = []
        
        // Add frequency
        let freqString: String
        switch rule.frequency {
        case .daily:
            freqString = "DAILY"
        case .weekly:
            freqString = "WEEKLY"
        case .monthly:
            freqString = "MONTHLY"
        case .yearly:
            freqString = "YEARLY"
        @unknown default:
            freqString = "DAILY"
        }
        components.append("FREQ=\(freqString)")
        
        // Add interval if not 1
        if rule.interval > 1 {
            components.append("INTERVAL=\(rule.interval)")
        }
        
        // Add count or until
        if let recurrenceEnd = rule.recurrenceEnd {
            if recurrenceEnd.occurrenceCount > 0 {
                components.append("COUNT=\(recurrenceEnd.occurrenceCount)")
            } else if let endDate = recurrenceEnd.endDate {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime]
                let dateString = formatter.string(from: endDate)
                components.append("UNTIL=\(dateString)")
            }
        }
        
        // Add BYDAY
        if let daysOfWeek = rule.daysOfTheWeek, !daysOfWeek.isEmpty {
            let dayStrings = daysOfWeek.map { day -> String in
                let prefix = day.weekNumber != 0 ? "\(day.weekNumber)" : ""
                let dayCode: String
                switch day.dayOfTheWeek {
                case .sunday: dayCode = "SU"
                case .monday: dayCode = "MO"
                case .tuesday: dayCode = "TU"
                case .wednesday: dayCode = "WE"
                case .thursday: dayCode = "TH"
                case .friday: dayCode = "FR"
                case .saturday: dayCode = "SA"
                @unknown default: dayCode = "MO"
                }
                return "\(prefix)\(dayCode)"
            }
            components.append("BYDAY=\(dayStrings.joined(separator: ","))")
        }
        
        // Add BYMONTHDAY
        if let daysOfMonth = rule.daysOfTheMonth, !daysOfMonth.isEmpty {
            let dayStrings = daysOfMonth.map { "\($0.intValue)" }
            components.append("BYMONTHDAY=\(dayStrings.joined(separator: ","))")
        }
        
        // Add BYMONTH
        if let monthsOfYear = rule.monthsOfTheYear, !monthsOfYear.isEmpty {
            let monthStrings = monthsOfYear.map { "\($0.intValue)" }
            components.append("BYMONTH=\(monthStrings.joined(separator: ","))")
        }
        
        // Add BYYEARDAY
        if let daysOfYear = rule.daysOfTheYear, !daysOfYear.isEmpty {
            let dayStrings = daysOfYear.map { "\($0.intValue)" }
            components.append("BYYEARDAY=\(dayStrings.joined(separator: ","))")
        }
        
        // Add BYWEEKNO
        if let weeksOfYear = rule.weeksOfTheYear, !weeksOfYear.isEmpty {
            let weekStrings = weeksOfYear.map { "\($0.intValue)" }
            components.append("BYWEEKNO=\(weekStrings.joined(separator: ","))")
        }
        
        // Add BYSETPOS
        if let setPositions = rule.setPositions, !setPositions.isEmpty {
            let posStrings = setPositions.map { "\($0.intValue)" }
            components.append("BYSETPOS=\(posStrings.joined(separator: ","))")
        }
        
        // Return with RRULE: prefix for consistency with rrule package
        return "RRULE:" + components.joined(separator: ";")
    }
    
    private func parseUntilDate(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }
    
    private func createEKRecurrenceRules(_ recurrenceDict: [String: Any]) -> [EKRecurrenceRule]? {
        guard let frequency = recurrenceDict["freq"] as? String else { return nil }
        
        let interval = recurrenceDict["interval"] as? Int ?? 1
        let count = recurrenceDict["count"] as? Int
        let until = recurrenceDict["until"] as? String
        
        var ekFrequency: EKRecurrenceFrequency
        switch frequency.uppercased() {
        case "DAILY":
            ekFrequency = .daily
        case "WEEKLY":
            ekFrequency = .weekly
        case "MONTHLY":
            ekFrequency = .monthly
        case "YEARLY":
            ekFrequency = .yearly
        default:
            ekFrequency = .daily
        }
        
        var recurrenceEnd: EKRecurrenceEnd?
        if let count = count, count > 0 {
            recurrenceEnd = EKRecurrenceEnd(occurrenceCount: count)
        } else if let until = until {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
            if let endDate = dateFormatter.date(from: until) {
                recurrenceEnd = EKRecurrenceEnd(end: endDate)
            }
        }
        
        var daysOfWeek: [EKRecurrenceDayOfWeek]?
        if let byDayStrings = recurrenceDict["byday"] as? [String] {
            daysOfWeek = byDayStrings.compactMap { recurrenceDayOfWeekFromString($0) }
        }
        
        var daysOfMonth: [NSNumber]?
        if let byMonthDays = recurrenceDict["bymonthday"] as? [Int] {
            daysOfMonth = byMonthDays.map { NSNumber(value: $0) }
        }
        
        var monthsOfYear: [NSNumber]?
        if let byMonths = recurrenceDict["bymonth"] as? [Int] {
            monthsOfYear = byMonths.map { NSNumber(value: $0) }
        }
        
        var daysOfYear: [NSNumber]?
        if let byYearDays = recurrenceDict["byyearday"] as? [Int] {
            daysOfYear = byYearDays.map { NSNumber(value: $0) }
        }
        
        var weeksOfYear: [NSNumber]?
        if let byWeeks = recurrenceDict["byweekno"] as? [Int] {
            weeksOfYear = byWeeks.map { NSNumber(value: $0) }
        }
        
        var setPositions: [NSNumber]?
        if let bySetPos = recurrenceDict["bysetpos"] as? [Int] {
            setPositions = bySetPos.map { NSNumber(value: $0) }
        }
        
        let rule = EKRecurrenceRule(
            recurrenceWith: ekFrequency,
            interval: interval,
            daysOfTheWeek: daysOfWeek,
            daysOfTheMonth: daysOfMonth,
            monthsOfTheYear: monthsOfYear,
            weeksOfTheYear: weeksOfYear,
            daysOfTheYear: daysOfYear,
            setPositions: setPositions,
            end: recurrenceEnd
        )
        
        return [rule]
    }
    
    private func recurrenceDayOfWeekFromString(_ dayString: String) -> EKRecurrenceDayOfWeek? {
        let pattern = "^(?:(\\+|-)?([0-9]{1,2}))?([A-Z]{2})$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: dayString, range: NSRange(dayString.startIndex..., in: dayString)) else {
            return nil
        }
        
        var weekNumber: Int = 0
        var dayOfWeek: EKWeekday
        
        if match.range(at: 2).location != NSNotFound {
            let weekNumberString = String(dayString[Range(match.range(at: 2), in: dayString)!])
            weekNumber = Int(weekNumberString) ?? 0
            
            if match.range(at: 1).location != NSNotFound {
                let signString = String(dayString[Range(match.range(at: 1), in: dayString)!])
                if signString == "-" {
                    weekNumber = -weekNumber
                }
            }
        }
        
        let dayString = String(dayString[Range(match.range(at: 3), in: dayString)!])
        switch dayString {
        case "SU": dayOfWeek = .sunday
        case "MO": dayOfWeek = .monday
        case "TU": dayOfWeek = .tuesday
        case "WE": dayOfWeek = .wednesday
        case "TH": dayOfWeek = .thursday
        case "FR": dayOfWeek = .friday
        case "SA": dayOfWeek = .saturday
        default: return nil
        }
        
        if weekNumber != 0 {
            return EKRecurrenceDayOfWeek(dayOfTheWeek: dayOfWeek, weekNumber: weekNumber)
        } else {
            return EKRecurrenceDayOfWeek(dayOfWeek)
        }
    }
    
    // MARK: - Attendee Handling
    
    private func setAttendees(_ attendeesData: [[String: Any]], _ event: EKEvent) {
        var attendees = [EKParticipant]()
        
        for attendeeDict in attendeesData {
            guard let email = attendeeDict["email"] as? String else { continue }
            let name = attendeeDict["name"] as? String ?? ""
            let role = attendeeDict["role"] as? Int ?? EKParticipantRole.required.rawValue
            
            if let existingAttendees = event.attendees {
                if let existingAttendee = existingAttendees.first(where: { participant in
                    return extractEmailFromParticipant(participant) == email
                }) {
                    attendees.append(existingAttendee)
                    continue
                }
            }
            
            if let participant = createParticipant(name: name, emailAddress: email, role: role) {
                attendees.append(participant)
            }
        }
        
        event.setValue(attendees, forKey: "attendees")
    }
    
    private func createParticipant(name: String, emailAddress: String, role: Int) -> EKParticipant? {
        guard let ekAttendeeClass = NSClassFromString("EKAttendee") as? NSObject.Type else {
            return nil
        }
        
        let participant = ekAttendeeClass.init()
        participant.setValue(UUID().uuidString, forKey: "UUID")
        participant.setValue(name, forKey: "displayName")
        participant.setValue(emailAddress, forKey: "emailAddress")
        participant.setValue(role, forKey: "participantRole")
        
        return participant as? EKParticipant
    }
    
    private func extractEmailFromParticipant(_ participant: EKParticipant) -> String {
        #if os(iOS)
        let url = participant.url
        if url.scheme == "mailto" {
            return String(url.absoluteString.dropFirst(7))
        } else {
            return url.absoluteString
        }
        #elseif os(macOS)
        if let emailAddress = participant.value(forKey: "emailAddress") as? String {
            return emailAddress
        }
        return participant.url.absoluteString
        #endif
    }
}

// MARK: - Extensions

extension Date {
    var millisecondsSinceEpoch: Double {
        return self.timeIntervalSince1970 * 1000.0
    }
}