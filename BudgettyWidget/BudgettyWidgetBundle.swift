//
//  BudgettyWidgetBundle.swift
//  BudgettyWidget
//
//  WidgetKit extension entry point.
//

import WidgetKit
import SwiftUI

@main
struct BudgettyWidgetBundle: WidgetBundle {
    var body: some Widget {
        SpendingWidget()
    }
}
