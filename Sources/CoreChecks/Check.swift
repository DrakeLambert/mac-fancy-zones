import CoreGraphics
import Foundation

var failures = 0

func check(_ cond: @autoclosure () -> Bool, _ msg: String, line: Int = #line) {
    if !cond() { failures += 1; print("FAIL (line \(line)): \(msg)") }
}

func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }

func nearRect(_ a: CGRect, _ b: CGRect) -> Bool {
    near(a.minX, b.minX) && near(a.minY, b.minY) && near(a.width, b.width) && near(a.height, b.height)
}
