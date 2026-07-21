//
//  MoneyTests.swift
//  BudgettyTests
//
//  Decimal money helpers — cents must stay exact (no binary-float drift), mirroring Android's
//  BigDecimal usage.
//

import Testing
import Foundation
@testable import Budgetty

struct MoneyTests {
    @Test func timesMultipliesByQuantity() {
        #expect(Decimal(string: "1.29")!.times(3) == Decimal(string: "3.87")!)
        #expect(Decimal.zero.times(5) == .zero)
        #expect(Decimal(string: "2.50")!.times(0) == .zero)
    }

    @Test func fromDoubleReturnsZeroForNil() {
        #expect(Decimal.fromDouble(nil) == .zero)
    }

    @Test func fromDoubleRoutesThroughStringToAvoidFloatNoise() {
        // The whole point of fromDouble: 0.1 + 0.2 must be exactly 0.3, not 0.30000000000000004.
        let sum = Decimal.fromDouble(0.1) + Decimal.fromDouble(0.2)
        #expect(sum == Decimal(string: "0.3")!)
        #expect(Decimal.fromDouble(2.5) == Decimal(string: "2.5")!)
    }
}
