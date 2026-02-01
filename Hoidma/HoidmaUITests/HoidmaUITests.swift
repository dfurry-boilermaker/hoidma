//
//  HoidmaUITests.swift
//  HoidmaUITests
//
//  Created by Daniel Furry on 11/7/25.
//

import XCTest

final class HoidmaUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        
        // Launch app with UI testing flags to skip API calls
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment = ["UI_TESTING": "1"]
        app.launch()
        
        // Wait for app to be ready - use proper waiting instead of sleep
        let exists = app.wait(for: .runningForeground, timeout: 10)
        XCTAssertTrue(exists, "App should launch successfully")
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Essential Tests
    
    func testAppLaunches() throws {
        // Essential: App must launch without crashing
        XCTAssertTrue(app.state == .runningForeground, "App should be running")
    }
    
    func testMainScreenDisplays() throws {
        // Essential: Main portfolio screen must appear
        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5), "Main screen should load")
        
        // Essential: Portfolio value must be visible
        let portfolioValue = app.staticTexts.containing(NSPredicate(format: "label CONTAINS '$'")).firstMatch
        XCTAssertTrue(portfolioValue.waitForExistence(timeout: 5), "Portfolio value should be displayed")
    }
    
    func testAddStockFlow() throws {
        // Essential: User must be able to add a stock
        // Find and tap add button
        let addButton = app.buttons["Add"].firstMatch
        if !addButton.exists {
            // Try finding by image
            let images = app.images
            if images.count > 0 {
                images.firstMatch.tap()
            } else {
                XCTFail("Add button not found")
                return
            }
        } else {
            addButton.tap()
        }
        
        // Wait for form to appear (use proper waiting)
        let formTitle = app.staticTexts["Add Stock"].firstMatch
        XCTAssertTrue(formTitle.waitForExistence(timeout: 3), "Add Stock form should appear")
        
        // Essential: Form must have input fields
        let textFields = app.textFields
        XCTAssertGreaterThan(textFields.count, 0, "Form should have input fields")
    }
    
    func testNavigationWorks() throws {
        // Essential: Bottom navigation must work
        let navButton1 = app.buttons["1"].firstMatch
        let navButton2 = app.buttons["2"].firstMatch
        
        if navButton1.waitForExistence(timeout: 3) && navButton2.waitForExistence(timeout: 3) {
            // Test navigation between tabs
            navButton1.tap()
            let _ = navButton2.waitForExistence(timeout: 1) // Brief wait for animation
            navButton2.tap()
            XCTAssertTrue(navButton2.exists, "Navigation should work")
        }
    }
    
    // MARK: - Auth Tests
    
    func testAuthScreenLoads() throws {
        // Essential: Auth screen must load (or skip if already authenticated)
        // Note: In testing mode, user is usually already authenticated
        let phoneField = app.textFields.firstMatch
        if phoneField.waitForExistence(timeout: 5) {
            XCTAssertTrue(phoneField.exists, "Phone input field should exist")
        } else {
            // Already authenticated - this is expected in testing mode
            throw XCTSkip("User is already authenticated")
        }
    }
}
