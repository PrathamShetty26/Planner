//
//  PlannerViewModelTests.swift
//  PlannerTests
//
//  Created by Pratham Shetty on 28/05/25.
//

import XCTest
@testable import Planner

class PlannerViewModelTests: XCTestCase {
    var viewModel: PlannerViewModel!
    
    override func setUp() {
        super.setUp()
        viewModel = PlannerViewModel()
    }
    
    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }
    
    func testAddTask() {
        let initialCount = viewModel.tasks.count
        viewModel.addTask(title: "Test Task", date: Date())
        XCTAssertEqual(viewModel.tasks.count, initialCount + 1, "Task should be added")
        XCTAssertEqual(viewModel.tasks.last?.title, "Test Task", "Task title should match")
    }
    
    func testAddHabit() {
        let initialCount = viewModel.habits.count
        viewModel.addHabit(title: "Test Habit", frequency: "Daily")
        XCTAssertEqual(viewModel.habits.count, initialCount + 1, "Habit should be added")
        XCTAssertEqual(viewModel.habits.last?.title, "Test Habit", "Habit title should match")
        XCTAssertEqual(viewModel.habits.last?.frequency, "Daily", "Habit frequency should match")
    }
    
    func testAddEvent() {
        let initialCount = viewModel.events.count
        let startDate = Date()
        let endDate = startDate.addingTimeInterval(3600)
        viewModel.addEvent(title: "Test Event", startDate: startDate, endDate: endDate)
        XCTAssertEqual(viewModel.events.count, initialCount + 1, "Event should be added")
        XCTAssertEqual(viewModel.events.last?.title, "Test Event", "Event title should match")
    }
    
    func testToggleHabitCompletion() {
        viewModel.addHabit(title: "Test Habit", frequency: "Daily")
        let habit = viewModel.habits.first!
        XCTAssertFalse(habit.isCompletedToday, "Habit should initially be uncompleted")
        viewModel.toggleHabitCompletion(habit: habit)
        XCTAssertTrue(viewModel.habits.first!.isCompletedToday, "Habit should be completed after toggle")
        viewModel.toggleHabitCompletion(habit: habit)
        XCTAssertFalse(viewModel.habits.first!.isCompletedToday, "Habit should be uncompleted after second toggle")
    }
}
