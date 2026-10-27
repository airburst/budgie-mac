import Foundation
import SwiftData

/// S-006 and S-007: what the transaction sheet edits.
public struct TransactionDraft {
    public enum Problem: Error, Equatable, Sendable {
        case noAmount, bothAmounts, notANumber

        public var message: String {
            switch self {
            case .noAmount: "Enter a withdrawal or a deposit."
            case .bothAmounts: "Enter a withdrawal or a deposit, not both."
            case .notANumber: "Enter the amount as a number, like 12.50."
            }
        }
    }

    public var date: Date
    public var payee = ""
    public var category: Category?
    /// Typing in one clears the other (the sheet does that).
    public var withdrawal = ""
    public var deposit = ""
    public var notes = ""
    public var cleared = false

    public init(date: Date = Day.today) {
        self.date = date
    }

    /// Prefilled from a transaction, for Edit Transaction.
    public init(_ transaction: Transaction, locale: Locale = .current) {
        date = transaction.date
        payee = transaction.payee
        category = transaction.category
        let text = abs(transaction.amount).formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(locale))
        if transaction.amount < 0 { withdrawal = text } else { deposit = text }
        notes = transaction.notes ?? ""
        cleared = transaction.cleared
    }

    /// The signed amount, or why there isn't one.
    public func amount(locale: Locale = .current) -> Result<Decimal, Problem> {
        let out = withdrawal.trimmingCharacters(in: .whitespaces)
        let into = deposit.trimmingCharacters(in: .whitespaces)
        switch (out.isEmpty, into.isEmpty) {
        case (true, true): return .failure(.noAmount)
        case (false, false): return .failure(.bothAmounts)
        case (false, true):
            guard let value = Money.parse(out, locale: locale) else { return .failure(.notANumber) }
            return .success(-abs(value))
        case (true, false):
            guard let value = Money.parse(into, locale: locale) else { return .failure(.notANumber) }
            return .success(abs(value))
        }
    }

    /// "That's more than a year from today." A note only.
    public var isFarFromToday: Bool {
        abs(date.timeIntervalSince(Day.today)) > 366 * 86_400
    }

    /// Adds a transaction to `account`, creating a Payee for a new payee name.
    @discardableResult
    public func add(to account: Account, in context: ModelContext, locale: Locale = .current) throws(Problem) -> Transaction {
        let amount = try amount(locale: locale).get()
        let transaction = Transaction(account: account, date: date, payee: cleanPayee, amount: amount, category: category)
        apply(notesAndCleared: transaction)
        context.insert(transaction)
        rememberPayee(in: context)
        return transaction
    }

    /// Writes the draft into an existing transaction.
    public func apply(to transaction: Transaction, in context: ModelContext, locale: Locale = .current) throws(Problem) {
        let amount = try amount(locale: locale).get()
        transaction.date = date
        transaction.payee = cleanPayee
        transaction.amount = amount
        transaction.category = category
        apply(notesAndCleared: transaction)
        transaction.updatedAt = .now
        rememberPayee(in: context)
    }

    private var cleanPayee: String {
        payee.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func apply(notesAndCleared transaction: Transaction) {
        let notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        transaction.notes = notes.isEmpty ? nil : notes
        transaction.cleared = cleared || transaction.reconciled
    }

    private func rememberPayee(in context: ModelContext) {
        let name = cleanPayee
        guard !name.isEmpty else { return }
        let existing = (try? context.fetch(FetchDescriptor<Payee>())) ?? []
        guard !existing.contains(where: { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }) else { return }
        context.insert(Payee(name: name))
    }
}
