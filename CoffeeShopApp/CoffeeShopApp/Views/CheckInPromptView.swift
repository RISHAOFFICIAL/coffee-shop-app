import SwiftUI

/// The check in prompt (Screen 6), shown as an in app sheet when the
/// arrival prompt fires while the app is open, and when the user taps the
/// notification. One tap saves the visit; Dismiss saves nothing and the
/// prompt never repeats for this arrival.
struct CheckInPromptView: View {
    let prompt: PendingArrival

    @EnvironmentObject private var checkInManager: CheckInManager

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            VStack(spacing: 10) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.appAccent)
                Text("Were you at \(prompt.shopName)?")
                    .font(.coffeeTitle)
                    .foregroundStyle(.appText)
                    .multilineTextAlignment(.center)
                Text("\(prompt.neighborhood), Detroit")
                    .font(.coffeeBody)
                    .foregroundStyle(.appTextSecondary)
                Text("One tap saves this visit, with today and the neighborhood filled in for you.")
                    .font(.coffeeBody)
                    .foregroundStyle(.appTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            VStack(spacing: 12) {
                Button("Check In") {
                    checkInManager.confirmCheckIn()
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Not This Shop") {
                    checkInManager.startCorrection(for: prompt.shopID)
                }
                .buttonStyle(SecondaryButtonStyle())
                Button("Dismiss") {
                    checkInManager.dismissPrompt()
                }
                .font(.coffeeButton)
                .foregroundStyle(.appTextSecondary)
                .frame(minHeight: CoffeeSpacing.minTapTarget)
            }
            Text("Dismiss saves nothing, and this prompt will not repeat for this arrival.")
                .font(.coffeeSecondary)
                .foregroundStyle(.appTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .padding(CoffeeSpacing.screenMargin)
        .background(Color.appBackground)
        .presentationDetents([.medium, .large])
    }
}

/// The confirmation after a one tap save: "Saved to Visited." The visit is
/// already on the phone at this point. Add A Memory opens the joggers
/// sheet for the same visit (Sprint 4); Done and View in Visited just
/// close the confirmation, and the memory can be added later from the
/// visit itself.
struct CheckInConfirmationView: View {
    let visit: Visit
    let onAddMemory: () -> Void
    let onViewInVisited: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.openGreen)
                Text("Saved to Visited")
                    .font(.coffeeTitle)
                    .foregroundStyle(.appText)
                Text(visit.shopName)
                    .font(.coffeeCardTitle)
                    .foregroundStyle(.appText)
                Text("\(visit.neighborhood), Detroit, \(formattedDate)")
                    .font(.coffeeBody)
                    .foregroundStyle(.appTextSecondary)
            }
            VStack(spacing: 12) {
                Button("Add A Memory", action: onAddMemory)
                    .buttonStyle(PrimaryButtonStyle())
                Button("View in Visited", action: onViewInVisited)
                    .buttonStyle(SecondaryButtonStyle())
                Button("Done", action: onDone)
                    .font(.coffeeButton)
                    .foregroundStyle(.appTextSecondary)
                    .frame(minHeight: CoffeeSpacing.minTapTarget)
            }
            Spacer()
        }
        .padding(CoffeeSpacing.screenMargin)
        .background(Color.appBackground)
        .presentationDetents([.medium])
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: visit.checkedInAt)
    }
}
