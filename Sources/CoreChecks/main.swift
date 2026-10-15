import Foundation

zoneChecks()
configChecks()
geometryChecks()

if failures > 0 { print("\(failures) check(s) failed"); exit(1) }
print("all checks passed")
