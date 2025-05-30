//
//  IntegrationTests.swift
//  PlannerTests
//
//  Created by Pratham Shetty on 28/05/25.
//

import XCTest
import EventKit
import UserNotifications
@testable import Planner

class IntegrationTests: XCTestCase {
    var viewModel: PlannerViewModel!
    var eventStore: EKEventStore!
    
    override func setUp() {
        super.setUp()
        viewModel = PlannerViewModel()
        eventStore = EKEventStore()
    }
    
    override func tearDown() {
        let predicate = eventStore.predicateForEvents(withStart: Date().addingTimeInterval(-86400), end: Date().addingTimeInterval(86400), calendars: nil)
        let events = eventStore.events(matching: predicate)
        for event in events { try? eventStore.remove(event, span: .thisEvent) }
        eventStore.fetchReminders(matching: eventStore.predicateForReminders(in: nil)) { reminders in
            for reminder in reminders ?? [] { try? self.eventStore.remove(reminder, commit: false) }
            try? self.eventStore.commit()
        }
        viewModel = nil
        eventStore = nil
        super.tearDown()
    }
    
    func testEventKitCalendarSync() throws {
        let startDate = Date()
        let endDate = startDate.addingTimeInterval(3600)
        viewModel.addEvent(title: "Test Event", startDate: startDate, endDate: endDate)
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)
        XCTAssertEqual(events.count, 1, "One event should be added to Calendar")
        XCTAssertEqual(events.first?.title, "Test Event", "Event title should match")
    }
    
    func testEventKitRemindersSync() throws {
        viewModel.addTask(title: "Test Task", date: Date())
        let expectation = XCTestExpectation(description: "Fetch reminders")
        var reminders: [EKReminder] = []
        eventStore.fetchReminders(matching: eventStore.predicateForReminders(in: nil)) { fetchedReminders in
            reminders = fetchedReminders ?? []
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        XCTAssertFalse(reminders.isEmpty, "A reminder should be added")
        XCTAssertEqual(reminders.first?.title, "Test Task", "Reminder title should match")
    }
    
    func testNotificationScheduling() throws {
        let date = Date().addingTimeInterval(60)
        let task = Task(id: UUID(), title: "Test Notification", date: date, isCompleted: false)
        viewModel.scheduleNotification(for: task)
        
        let expectation = XCTestExpectation(description: "Check scheduled notification")
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let matchingRequest = requests.first(where: { $0.content.body == "Don't forget: Test Notification" })
            XCTAssertNotNil(matchingRequest, "A notification should be scheduled")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
}
