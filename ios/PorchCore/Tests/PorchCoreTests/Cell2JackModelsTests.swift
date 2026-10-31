import XCTest
@testable import PorchCore

final class Cell2JackModelsTests: XCTestCase {
    func testIPadsWithAnMChipCanTryThePhone() {
        // iPad Pro (M1, M2, M4) and iPad Air (M1, M2, M3).
        for model in ["iPad13,4", "iPad13,11", "iPad13,16", "iPad14,3", "iPad14,8", "iPad14,11", "iPad15,3", "iPad15,6", "iPad16,3", "iPad16,6"] {
            XCTAssertTrue(Cell2JackModels.mayWork(model: model), model)
        }
    }

    func testIPadsWithAnASeriesChipCant() {
        // iPad Pro (2020), iPad (9th and 10th generation), iPad Air (4th generation), iPad mini (6th generation),
        // iPad (A16) and iPad mini (A17 Pro).
        for model in ["iPad8,12", "iPad12,1", "iPad13,1", "iPad13,18", "iPad13,19", "iPad14,1", "iPad15,7", "iPad15,8", "iPad16,1", "iPad16,2", "iPad6,11"] {
            XCTAssertFalse(Cell2JackModels.mayWork(model: model), model)
        }
    }

    func testAModelPorchDoesntKnowGetsATry() {
        for model in ["iPad18,1", "iPad99,9", "arm64", "x86_64", "", "iPad", "iPadX,1", "iPhone17,1"] {
            XCTAssertTrue(Cell2JackModels.mayWork(model: model), model)
        }
    }
}
