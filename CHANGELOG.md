# Changelog

## 1.0.5

### Bug Fixes
- Fixed recurring-event creation validation for RRULE strings (e.g. `RRULE:FREQ=DAILY;COUNT=10`) that previously caused "Invalid recurrence rule" errors when calling `createEvent`. Thanks to @jaydaptif-solutions for reporting and testing the fix.

## 1.0.4
### Bug Fixes
- Fixed timezone handling issue by updating the `timezone` dependency to version `0.10.1`, ensuring better compatibility and functionality across different platforms.

## 1.0.3
### Bug Fixes
- bug fix

## 1.0.2

### Bug Fixes

- Fixed type casting issue in CalendarBridgeMethodChannel that caused `_Map<Object?, Object?>` is not a subtype of `Map<String, dynamic>` errors
- Improved defensive type casting in getCalendars(), getEvents(), createCalendar(), getCalendarColors(), and getEventColors() methods
- Enhanced platform channel data handling for better compatibility across different Flutter versions

## 1.0.1

### Improvements

- Updated iOS minimum version support to iOS 13+
- Streamlined CI/CD pipeline configuration
- Consolidated analyzer and test jobs for improved workflow efficiency
- Updated Flutter version requirement to 3.35.4
- Added automated release workflow for versioning and publishing
- Enhanced analyzer configuration to exclude test files
- Improved project maintenance and build processes

## 1.0.0

### Initial Release

- Calendar management (retrieve, create, delete)
- Event CRUD operations
- Permission handling for Android, iOS, and macOS
- Recurring events support with RRULE format
- Full timezone support using TZDateTime
- Attendee management
- Reminder support
- Event status and availability
- Cross-platform support (Android, iOS, macOS)
