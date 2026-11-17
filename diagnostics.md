### Toolchain
```
Xcode 26.3
Build version 17C529
swift-driver version: 1.127.15 Apple Swift version 6.2.4 (swiftlang-6.2.4.1.4 clang-1700.6.4.2)
Target: arm64-apple-macosx15.0
iOS 18.5 (18.5 - 22F77) - com.apple.CoreSimulator.SimRuntime.iOS-18-5
iOS 18.6 (18.6 - 22G86) - com.apple.CoreSimulator.SimRuntime.iOS-18-6
iOS 26.0 (26.0.1 - 23A8464) - com.apple.CoreSimulator.SimRuntime.iOS-26-0
iOS 26.1 (26.1 - 23B86) - com.apple.CoreSimulator.SimRuntime.iOS-26-1
iOS 26.2 (26.2 - 23C54) - com.apple.CoreSimulator.SimRuntime.iOS-26-2
```
### Host suites — FAILED, last 120 lines
```
Command line invocation:
    /Applications/Xcode_26.3.app/Contents/Developer/usr/bin/xcodebuild test -scheme BasicList -destination "platform=iOS Simulator,name=iPhone 16 Pro" "-only-testing:BasicListTests/BasicListViewTests" "-only-testing:BasicListTests/BasicListConfigTests" "-only-testing:BasicListTests/BasicListSectionTests" "-only-testing:BasicListTests/BasicListSwipeActionTests" "-only-testing:BasicListTests/VocabularyTests" "-only-testing:BasicListTests/BasicListLoadGateTests"

Resolve Package Graph
package 'basiclist' is using Swift tools version 6.3.0 but the installed version is 6.2.4

Resolved source packages:
  BasicList: (null)

2026-11-17 22:00:04.727 xcodebuild[2010:9802] Writing error result bundle to /var/folders/2s/vty41l455yv698g4xkgfv7z00000gn/T/ResultBundle_2026-17-11_22-00-0004.xcresult
xcodebuild: error: Could not resolve package dependencies:
  package 'basiclist' is using Swift tools version 6.3.0 but the installed version is 6.2.4

```
