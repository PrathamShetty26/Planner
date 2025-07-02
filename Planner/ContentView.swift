//
//  ContentView.swift
//  Planner
//
//  Created by Pratham Shetty on 25/05/25.
//

import SwiftUI
import EventKit
import Foundation

// MARK: - Content View
struct ContentView: View {
    @StateObject private var viewModel = PlannerViewModel()
    @State private var selectedDate = Date()
    @State private var showingAddSheet = false
    @State private var showingSettings = false
    @State private var weekOffset = 0
    @State private var showTodayButton = false
    @State private var combinedItems: [TimelineItem] = []
    @State private var isLoadingSports = false
    @State private var lastRequestID: UUID = UUID()
    @State private var showingCalendarView = false
    
    var startOfWeek: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: selectedDate)
        let weekday = calendar.component(.weekday, from: today)
        let daysToSubtract = weekday - 1 // Sunday is 1, so we subtract (weekday - 1)
        return calendar.date(byAdding: .day, value: -daysToSubtract + (weekOffset * 7), to: today) ?? today
    }
    
    private func shortDayName(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        let full = formatter.weekdaySymbols[Calendar.current.component(.weekday, from: date) - 1]
        switch full.lowercased() {
        case "thursday": return "Thur"
        case "wednesday": return "Wed"
        case "saturday": return "Sat"
        case "sunday": return "Sun"
        case "monday": return "Mon"
        case "tuesday": return "Tue"
        case "friday": return "Fri"
        default: return String(full.prefix(3))
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Date Header
                HStack(alignment: .center, spacing: 16) {
                    Text(shortDayName(from: selectedDate))
                        .font(.system(size: 65, weight: .black))
                        .foregroundColor(Color(UIColor.darkGray))
                    
                    if Calendar.current.isDateInToday(selectedDate) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 22, height: 22)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(selectedDate.formatted(.dateTime.month().day()))
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(Color(UIColor.darkGray))
                        Text(selectedDate.formatted(.dateTime.year()))
                            .font(.system(size: 20, weight: .regular))
                            .foregroundColor(Color(UIColor.darkGray))
                    }
                }
                .padding()
                
                // Week View
                VStack(spacing: 16) {
                    HStack(spacing: 0) {
                        ForEach(0..<7) { dayOffset in
                            let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: startOfWeek) ?? selectedDate
                            WeekDayButton(
                                date: date,
                                isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate),
                                isToday: Calendar.current.isDateInToday(date)
                            ) {
                                withAnimation {
                                    selectedDate = date
                                    showTodayButton = !Calendar.current.isDateInToday(date)
                                }
                            }
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onEnded { value in
                                withAnimation {
                                    if value.translation.width < 0 {
                                        weekOffset += 1
                                    } else {
                                        weekOffset -= 1
                                    }
                                    showTodayButton = !Calendar.current.isDateInToday(selectedDate)
                                }
                            }
                    )
                    
                    if showTodayButton {
                        Button(action: {
                            withAnimation {
                                selectedDate = Date()
                                weekOffset = 0
                                showTodayButton = false
                            }
                        }) {
                            Text("Today")
                                .font(.system(size: 15, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(UIColor.systemGray6))
                                .foregroundColor(.primary)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal)
                
                // Timeline Section
                VStack {
                    if isLoadingSports {
                        HStack {
                            Spacer()
                            ProgressView().scaleEffect(0.7)
                            Spacer()
                        }
                    }
                    if combinedItems.isEmpty && !isLoadingSports {
                        VStack {
                            Spacer()
                            Image(systemName: "calendar")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("No items scheduled")
                                .font(.title3)
                                .foregroundColor(.secondary)
                            Text("Tap + to add a new item")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(combinedItems) { item in
                                    TimelineItemView(viewModel: viewModel, item: item)
                                }
                                
                                // Add sports schedule section here
                                if viewModel.showSportsSchedule && combinedItems.isEmpty {
                                    Divider()
                                        .padding(.vertical, 8)
                                    
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Sports Schedule")
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        
                                        SportsScheduleView(viewModel: viewModel)
                                    }
                                    .padding(.horizontal, 4)
                                }
                            }
                            .animation(.easeInOut, value: combinedItems)
                            .padding()
                        }
                    }
                }
                
                // Bottom Navigation
                HStack {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "hexagon")
                            .font(.title2)
                    }
                    
                    Spacer()
                    
                    Button(action: { showingAddSheet = true }) {
                        Image(systemName: "plus")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.accentColor)
                            .clipShape(Circle())
                            .shadow(radius: 4)
                    }
                    
                    Spacer()
                    
                    Button(action: { showingCalendarView = true }) {
                        Image(systemName: "calendar")
                            .font(.title2)
                    }
                }
                .padding()
                .background(Color(UIColor.systemBackground))
            }
            .sheet(isPresented: $showingAddSheet) {
                AddItemView(viewModel: viewModel, isPresented: $showingAddSheet)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(isPresented: $showingSettings, viewModel: viewModel)
            }
            .sheet(isPresented: $showingCalendarView) {
                CalendarView(selectedDate: $selectedDate, isPresented: $showingCalendarView)
                    .presentationDetents([.medium])
            }
            .onAppear(perform: loadCombinedItems)
            .onChange(of: selectedDate) { _, _ in 
                loadCombinedItems() 
            }
        }
    }

    private func loadCombinedItems() {
        isLoadingSports = true
        let requestID = UUID()
        lastRequestID = requestID
        let date = selectedDate
        
        // Debug log
        print("Loading combined items for date: \(date)")
        
        Task {
            await viewModel.fetchHealthData(for: date)
        }
        
        viewModel.timelineItemsWithSports(for: date) { items in
            // Only update if this is the latest request
            if lastRequestID == requestID {
                print("Received \(items.count) combined items")
                DispatchQueue.main.async {
                    self.combinedItems = items
                    self.isLoadingSports = false
                }
            }
        }
    }
}

struct WeekDayButton: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.gray)
                    .textCase(.uppercase)
                Text(date.formatted(.dateTime.day()))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.gray)
                Circle()
                    .fill(isToday ? Color.red : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color(UIColor.systemGray4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
}
