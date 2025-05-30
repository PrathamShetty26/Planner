//
//  ContentView.swift
//  Planner
//
//  Created by Pratham Shetty on 25/05/25.
//

import SwiftUI
import EventKit

struct ContentView: View {
    @StateObject private var viewModel = PlannerViewModel()
    @State private var showingAddEvent = false
    @State private var showingAddTask = false
    @State private var showingAddHabit = false
    @State private var selectedDate = Date()
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Custom date picker
                    DatePickerView(selectedDate: $selectedDate)
                        .padding(.horizontal)
                        .padding(.top)
                    
                    // Timeline
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.timelineItems(for: selectedDate)) { item in
                                TimelineItemView(item: item)
                                    .transition(.opacity)
                            }
                        }
                        .padding()
                    }
                }
                
                // Floating Action Button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Menu {
                            Button(action: { showingAddEvent = true }) {
                                Label("Add Event", systemImage: "calendar")
                            }
                            Button(action: { showingAddTask = true }) {
                                Label("Add Task", systemImage: "checklist")
                            }
                            Button(action: { showingAddHabit = true }) {
                                Label("Add Habit", systemImage: "repeat")
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.title2.weight(.semibold))
                                .foregroundColor(.white)
                                .frame(width: 60, height: 60)
                                .background(Color.accentColor)
                                .clipShape(Circle())
                                .shadow(radius: 4)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Timeline")
            .sheet(isPresented: $showingAddEvent) {
                AddEventView(isPresented: $showingAddEvent)
            }
            .sheet(isPresented: $showingAddTask) {
                AddTaskView(isPresented: $showingAddTask)
            }
            .sheet(isPresented: $showingAddHabit) {
                AddHabitView(isPresented: $showingAddHabit)
            }
        }
    }
}

struct DatePickerView: View {
    @Binding var selectedDate: Date
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(-2...4, id: \.self) { offset in
                    let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
                    DateCell(date: date, isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate))
                        .onTapGesture {
                            withAnimation {
                                selectedDate = date
                            }
                        }
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

struct DateCell: View {
    let date: Date
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            Text(date.formatted(.dateTime.weekday(.abbreviated)))
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(date.formatted(.dateTime.day()))
                .font(.title3.weight(.medium))
            
            Circle()
                .fill(isSelected ? Color.accentColor : Color.clear)
                .frame(width: 4, height: 4)
        }
        .frame(width: 45, height: 72)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
    }
}

#Preview {
    ContentView()
}
