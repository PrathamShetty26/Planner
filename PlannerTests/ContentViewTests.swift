//
//  ContentViewTests.swift
//  PlannerTests
//
//  Created by Pratham Shetty on 28/05/25.
//

import XCTest
import SwiftUI
import ViewInspector
@testable import Planner

class ContentViewTests: XCTestCase {
    func testAddTaskButton() throws {
        let viewModel = PlannerViewModel()
        let view = ContentView().environmentObject(viewModel)
        let button = try view.inspect().find(button: "Add Task")
        try button.tap()
        let sheet = try view.inspect().find(AddTaskView.self)
        XCTAssertNotNil(sheet, "Tapping Add Task should present AddTaskView")
    }
    func testAddHabitButton() throws {
        let viewModel = PlannerViewModel()
        let view = ContentView().environmentObject(viewModel)
        let button = try view.inspect().find(button: "Add Habit")
        try button.tap()
        let sheet = try view.inspect().find(AddHabitView.self)
        XCTAssertNotNil(sheet, "Tapping Add Habit should present AddHabitView")
    }
    func testAddEventButton() throws {
        let viewModel = PlannerViewModel()
        let view = ContentView().environmentObject(viewModel)
        let button = try view.inspect().find(button: "Add Event")
        try button.tap()
        let sheet = try view.inspect().find(AddEventView.self)
        XCTAssertNotNil(sheet, "Tapping Add Event should present AddEventView")
    }
    func testTimelineDisplaysItems() throws {
        let viewModel = PlannerViewModel()
        viewModel.addTask(title: "Test Task", date: Date())
        viewModel.addHabit(title: "Test Habit", frequency: "Daily")
        viewModel.addEvent(title: "Test Event", startDate: Date(), endDate: Date().addingTimeInterval(3600))
        
        let view = ContentView().environmentObject(viewModel)
        
        // Find all HStack views, which represent timeline items
        let hStacks = try view.inspect().findAll(ViewType.HStack.self)
        
        XCTAssertEqual(hStacks.count, 3, "Timeline should display 3 items")
        
        let taskItem = try hStacks[0].text(1)
        XCTAssertEqual(try taskItem.string(), "Test Task", "First item should be the task")
    }
}
