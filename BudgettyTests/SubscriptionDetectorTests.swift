//
//  SubscriptionDetectorTests.swift
//  BudgettyTests
//
//  Port of Android's SubscriptionDetectorTest — the on-device recurring-charge clustering.
//

import XCTest
@testable import Budgetty

final class SubscriptionDetectorTests: XCTestCase {

    private let cal = Calendar.current
    private lazy var today = date(2026, 7, 20)

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }
    private func charge(_ name: String, _ amount: String, _ y: Int, _ m: Int, _ d: Int) -> MerchantCharge {
        MerchantCharge(merchant: name, emoji: "🎬", amount: Decimal(string: amount)!, date: date(y, m, d))
    }
    private func ymd(_ d: Date) -> DateComponents { cal.dateComponents([.year, .month, .day], from: d) }

    func testMonthlyIdenticalChargesDetected() {
        let subs = SubscriptionDetector.detect([
            charge("Netflix", "13.99", 2026, 5, 14),
            charge("Netflix", "13.99", 2026, 6, 14),
            charge("Netflix", "13.99", 2026, 7, 14),
        ], today: today)
        XCTAssertEqual(subs.count, 1)
        let s = subs[0]
        XCTAssertEqual(s.cadence, .monthly)
        XCTAssertEqual(s.amount, Decimal(string: "13.99"))
        XCTAssertEqual(s.monthlyEquivalent, Decimal(string: "13.99"))
        XCTAssertEqual(s.dueDay, 14)
        XCTAssertEqual(s.chargeCount, 3)
        XCTAssertNil(s.priceHike)
        XCTAssertEqual(ymd(s.nextExpected), ymd(date(2026, 8, 14)))
    }

    func testPriceHikeFlaggedOldToNew() {
        let subs = SubscriptionDetector.detect([
            charge("Netflix", "11.99", 2026, 3, 14),
            charge("Netflix", "13.99", 2026, 4, 14),
            charge("Netflix", "13.99", 2026, 5, 14),
        ], today: today)
        let hike = subs[0].priceHike
        XCTAssertNotNil(hike)
        XCTAssertEqual(hike?.oldAmount, Decimal(string: "11.99"))
        XCTAssertEqual(hike?.newAmount, Decimal(string: "13.99"))
        XCTAssertEqual(ymd(hike!.since), ymd(date(2026, 4, 14)))
        XCTAssertEqual(subs[0].amount, Decimal(string: "13.99"))
    }

    func testYearlyCadenceOneTwelfthMonthlyEquivalent() {
        let subs = SubscriptionDetector.detect([
            charge("Allianz", "59.00", 2024, 3, 12),
            charge("Allianz", "59.00", 2025, 3, 12),
            charge("Allianz", "59.00", 2026, 3, 12),
        ], today: today)
        XCTAssertEqual(subs[0].cadence, .yearly)
        XCTAssertEqual(subs[0].monthlyEquivalent, Decimal(string: "4.92"))
    }

    func testVaryingAmountsAreNotASubscription() {
        let subs = SubscriptionDetector.detect([
            charge("Kaufland", "47.86", 2026, 5, 3),
            charge("Kaufland", "31.40", 2026, 6, 5),
            charge("Kaufland", "52.10", 2026, 7, 2),
        ], today: today)
        XCTAssertTrue(subs.isEmpty)
    }

    func testIrregularGapsRejected() {
        let subs = SubscriptionDetector.detect([
            charge("Cafe", "3.50", 2026, 5, 1),
            charge("Cafe", "3.50", 2026, 5, 6),
            charge("Cafe", "3.50", 2026, 7, 5),
        ], today: today)
        XCTAssertTrue(subs.isEmpty)
    }

    func testFewerThanThreeChargesNotEnough() {
        let subs = SubscriptionDetector.detect([
            charge("Spotify", "10.99", 2026, 6, 3),
            charge("Spotify", "10.99", 2026, 7, 3),
        ], today: today)
        XCTAssertTrue(subs.isEmpty)
    }

    func testSubscriptionsSortByMonthlyCostDescending() {
        let subs = SubscriptionDetector.detect([
            charge("Spotify", "10.99", 2026, 5, 3), charge("Spotify", "10.99", 2026, 6, 3), charge("Spotify", "10.99", 2026, 7, 3),
            charge("Gym", "24.90", 2026, 5, 1), charge("Gym", "24.90", 2026, 6, 1), charge("Gym", "24.90", 2026, 7, 1),
        ], today: today)
        XCTAssertEqual(subs.map(\.merchant), ["Gym", "Spotify"])
    }
}
