//===--------------- SwiftDriverTests.swift - Swift Driver Tests -======---===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation
import SwiftDriver
import SwiftOptions
import TSCBasic
import XCTest

final class SwiftDriverTests: XCTestCase {

  func testInvocationRunModes() throws {

    let driver1 = try Driver.invocationRunMode(forArgs: ["swift"])
    XCTAssertEqual(driver1.mode, .normal(isRepl: false))
    XCTAssertEqual(driver1.args, ["swift"])

    let driver2 = try Driver.invocationRunMode(forArgs: ["swift", "-buzz"])
    XCTAssertEqual(driver2.mode, .normal(isRepl: false))
    XCTAssertEqual(driver2.args, ["swift", "-buzz"])

    let driver3 = try Driver.invocationRunMode(forArgs: ["swift", "/"])
    XCTAssertEqual(driver3.mode, .normal(isRepl: false))
    XCTAssertEqual(driver3.args, ["swift", "/"])

    let driver4 = try Driver.invocationRunMode(forArgs: ["swift", "./foo"])
    XCTAssertEqual(driver4.mode, .normal(isRepl: false))
    XCTAssertEqual(driver4.args, ["swift", "./foo"])

    let driver5 = try Driver.invocationRunMode(forArgs: ["swift", "repl"])
    XCTAssertEqual(driver5.mode, .normal(isRepl: true))
    XCTAssertEqual(driver5.args, ["swift"])

    let driver6 = try Driver.invocationRunMode(forArgs: ["swift", "foo", "bar"])
    XCTAssertEqual(driver6.mode, .subcommand("swift-foo"))
    XCTAssertEqual(driver6.args, ["swift-foo", "bar"])
  }

  func testSubcommandsHandling() throws {

    XCTAssertNoThrow(try Driver(args: ["swift"]))
    XCTAssertNoThrow(try Driver(args: ["swift", "-I=foo"]))
    XCTAssertNoThrow(try Driver(args: ["swift", ".foo"]))
    XCTAssertNoThrow(try Driver(args: ["swift", "/foo"]))

    XCTAssertThrowsError(try Driver(args: ["swift", "foo"]))
  }

  func testDriverKindParsing() throws {
    func assertArgs(
      _ args: String...,
      parseTo driverKind: DriverKind,
      leaving remainingArgs: [String],
      file: StaticString = #file, line: UInt = #line
    ) throws {
      var args = args
      let result = try Driver.determineDriverKind(args: &args)

      XCTAssertEqual(result, driverKind, file: file, line: line)
      XCTAssertEqual(args, remainingArgs, file: file, line: line)
    }
    func assertArgsThrow(
      _ args: String...,
      file: StaticString = #file, line: UInt = #line
    ) throws {
      var args = args
      XCTAssertThrowsError(try Driver.determineDriverKind(args: &args))
    }

    try assertArgs("swift", parseTo: .interactive, leaving: [])
    try assertArgs("/path/to/swift", parseTo: .interactive, leaving: [])
    try assertArgs("swiftc", parseTo: .batch, leaving: [])
    try assertArgs(".build/debug/swiftc", parseTo: .batch, leaving: [])
    try assertArgs("swiftc", "-frontend", parseTo: .frontend, leaving: [])
    try assertArgs("swiftc", "-modulewrap", parseTo: .moduleWrap, leaving: [])
    try assertArgs("/path/to/swiftc", "-modulewrap",
                   parseTo: .moduleWrap, leaving: [])

    try assertArgs("swiftc", "--driver-mode=swift", parseTo: .interactive, leaving: [])
    try assertArgs("swiftc", "--driver-mode=swift-autolink-extract", parseTo: .autolinkExtract, leaving: [])
    try assertArgs("swift", "--driver-mode=swift-autolink-extract", parseTo: .autolinkExtract, leaving: [])

    try assertArgs("swift", "-zelda", parseTo: .interactive, leaving: ["-zelda"])
    try assertArgs("/path/to/swiftc", "-modulewrap", "savannah",
                   parseTo: .moduleWrap, leaving: ["savannah"])
    try assertArgs("swiftc", "--driver-mode=swift", "swiftc",
                   parseTo: .interactive, leaving: ["swiftc"])

    try assertArgsThrow("driver")
    try assertArgsThrow("swiftc", "--driver-mode=blah")
    try assertArgsThrow("swiftc", "--driver-mode=")
  }

  func testCompilerMode() throws {
    do {
      let driver1 = try Driver(args: ["swift", "main.swift"])
      XCTAssertEqual(driver1.compilerMode, .immediate)

      let driver2 = try Driver(args: ["swift"])
      XCTAssertEqual(driver2.compilerMode, .repl)
    }

    do {
      let driver1 = try Driver(args: ["swiftc", "main.swift", "-whole-module-optimization"])
      XCTAssertEqual(driver1.compilerMode, .singleCompile)

      let driver2 = try Driver(args: ["swiftc", "main.swift", "-whole-module-optimization", "-no-whole-module-optimization"])
      XCTAssertEqual(driver2.compilerMode, .standardCompile)

      let driver3 = try Driver(args: ["swiftc", "main.swift", "-g"])
      XCTAssertEqual(driver3.compilerMode, .standardCompile)
    }
  }

  func testBatchModeDiagnostics() throws {
      try assertNoDriverDiagnostics(args: "swiftc", "-enable-batch-mode") { driver in
        switch driver.compilerMode {
        case .batchCompile:
          break
        default:
          XCTFail("Expected batch compile, got \(driver.compilerMode)")
        }
      }

      try assertDriverDiagnostics(args: "swiftc", "-enable-batch-mode", "-whole-module-optimization") { driver, diagnostics in
        XCTAssertEqual(driver.compilerMode, .singleCompile)
        diagnostics.expect(.warning("ignoring '-enable-batch-mode' because '-whole-module-optimization' was also specified"))
      }

      try assertDriverDiagnostics(args: "swiftc", "-enable-batch-mode", "-whole-module-optimization", "-no-whole-module-optimization", "-index-file", "-module-name", "foo") { driver, diagnostics in
        XCTAssertEqual(driver.compilerMode, .singleCompile)
        diagnostics.expect(.warning("ignoring '-enable-batch-mode' because '-index-file' was also specified"))
      }

      try assertNoDriverDiagnostics(args: "swiftc", "-enable-batch-mode", "-whole-module-optimization", "-no-whole-module-optimization") { driver in
        switch driver.compilerMode {
        case .batchCompile:
          break
        default:
          XCTFail("Expected batch compile, got \(driver.compilerMode)")
        }
      }
  }

  // This test is dependent on the swift-help executable being available, which
  // isn't always the case right now.
  #if false
  func testHelp() throws {
    do {
      var driver = try Driver(args: ["swift", "--help"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      let helpJob = plannedJobs.first!
      XCTAssertTrue(helpJob.kind == .help)
      XCTAssertTrue(helpJob.requiresInPlaceExecution)
      XCTAssertTrue(helpJob.tool.name.hasSuffix("swift-help"))
      let expected: [Job.ArgTemplate] = [.flag("-tool=swift")]
      XCTAssertEqual(helpJob.commandLine, expected)
    }

    do {
      var driver = try Driver(args: ["swiftc", "-help-hidden"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      let helpJob = plannedJobs.first!
      XCTAssertTrue(helpJob.kind == .help)
      XCTAssertTrue(helpJob.requiresInPlaceExecution)
      XCTAssertTrue(helpJob.tool.name.hasSuffix("swift-help"))
      let expected: [Job.ArgTemplate] = [.flag("-tool=swiftc"), .flag("-show-hidden")]
      XCTAssertEqual(helpJob.commandLine, expected)
    }
  }
  #endif

  func testInputFiles() throws {
    let driver1 = try Driver(args: ["swiftc", "a.swift", "/tmp/b.swift"])
    XCTAssertEqual(driver1.inputFiles,
                   [ TypedVirtualPath(file: .relative(RelativePath("a.swift")), type: .swift),
                     TypedVirtualPath(file: .absolute(AbsolutePath("/tmp/b.swift")), type: .swift) ])
    let driver2 = try Driver(args: ["swiftc", "a.swift", "-working-directory", "/wobble", "/tmp/b.swift"])
    XCTAssertEqual(driver2.inputFiles,
                   [ TypedVirtualPath(file: .absolute(AbsolutePath("/wobble/a.swift")), type: .swift),
                     TypedVirtualPath(file: .absolute(AbsolutePath("/tmp/b.swift")), type: .swift) ])

    let driver3 = try Driver(args: ["swift", "-"])
    XCTAssertEqual(driver3.inputFiles, [ TypedVirtualPath(file: .standardInput, type: .swift )])

    let driver4 = try Driver(args: ["swift", "-", "-working-directory" , "-wobble"])
    XCTAssertEqual(driver4.inputFiles, [ TypedVirtualPath(file: .standardInput, type: .swift )])
  }

  func testRecordedInputModificationDates() throws {
    try withTemporaryDirectory { path in
      guard let cwd = localFileSystem
        .currentWorkingDirectory else { fatalError() }
      let main = path.appending(component: "main.swift")
      let util = path.appending(component: "util.swift")
      let utilRelative = util.relative(to: cwd)
      try localFileSystem.writeFileContents(main) { $0 <<< "print(hi)" }
      try localFileSystem.writeFileContents(util) { $0 <<< "let hi = \"hi\"" }

      let mainMDate = try localFileSystem.getFileInfo(main).modTime
      let utilMDate = try localFileSystem.getFileInfo(util).modTime
      let driver = try Driver(args: [
        "swiftc", main.pathString, utilRelative.pathString,
      ])
      XCTAssertEqual(driver.recordedInputModificationDates, [
        .init(file: .absolute(main), type: .swift) : mainMDate,
        .init(file: .relative(utilRelative), type: .swift) : utilMDate,
      ])
    }
  }

  func testPrimaryOutputKinds() throws {
    let driver1 = try Driver(args: ["swiftc", "foo.swift", "-emit-module"])
    XCTAssertEqual(driver1.compilerOutputType, .swiftModule)
    XCTAssertEqual(driver1.linkerOutputType, nil)

    let driver2 = try Driver(args: ["swiftc", "foo.swift", "-emit-library"])
    XCTAssertEqual(driver2.compilerOutputType, .object)
    XCTAssertEqual(driver2.linkerOutputType, .dynamicLibrary)

    let driver3 = try Driver(args: ["swiftc", "-static", "foo.swift", "-emit-library"])
    XCTAssertEqual(driver3.compilerOutputType, .object)
    XCTAssertEqual(driver3.linkerOutputType, .staticLibrary)
  }

  func testPrimaryOutputKindsDiagnostics() throws {
      try assertDriverDiagnostics(args: "swift", "-i") {
        $1.expect(.error("the flag '-i' is no longer required and has been removed; use 'swift input-filename'"))
      }
  }

  func testBaseOutputPaths() throws {
    // Test the combination of -c and -o includes the base output path.
    do {
      var driver = try Driver(args: ["swiftc", "-c", "foo.swift", "-o", "/some/output/path/bar.o"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertTrue(plannedJobs[0].commandLine.contains(.path(try VirtualPath(path: "/some/output/path/bar.o"))))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-emit-sil", "foo.swift", "-o", "/some/output/path/bar.sil"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertTrue(plannedJobs[0].commandLine.contains(.path(try VirtualPath(path: "/some/output/path/bar.sil"))))
    }

    do {
      // If no output is specified, verify we print to stdout for textual formats.
      var driver = try Driver(args: ["swiftc", "-emit-assembly", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertTrue(plannedJobs[0].commandLine.contains(.path(.standardOutput)))
    }
  }

    func testMultithreading() throws {

      XCTAssertEqual(try Driver(args: ["swiftc"]).numThreads, 0)

      XCTAssertEqual(try Driver(args: ["swiftc", "-num-threads", "4"]).numThreads, 4)

      XCTAssertEqual(try Driver(args: ["swiftc", "-num-threads", "0"]).numThreads, 0)

      XCTAssertEqual(try Driver(args: ["swiftc", "-num-threads", "-1"]).numThreads, 0)

      XCTAssertEqual(try Driver(args: ["swiftc", "-enable-batch-mode", "-num-threads", "4"]).numThreads, 0)

      XCTAssertNil(try Driver(args: ["swiftc"]).numParallelJobs)

      XCTAssertEqual(try Driver(args: ["swiftc", "-j", "4"]).numParallelJobs, 4)

      XCTAssertNil(try Driver(args: ["swiftc", "-j", "0"]).numParallelJobs)

      var env = ProcessEnv.vars
      env["SWIFTC_MAXIMUM_DETERMINISM"] = "1"
      XCTAssertEqual(try Driver(args: ["swiftc", "-j", "4"], env: env).numParallelJobs, 1)
    }

    func testMultithreadingDiagnostics() throws {

      try assertDriverDiagnostics(args: "swift", "-num-threads", "-1") {
        $1.expect(.error("invalid value '-1' in '-num-threads'"))
      }

      try assertDriverDiagnostics(args: "swiftc", "-enable-batch-mode", "-num-threads", "4") {
        $1.expect(.warning("ignoring -num-threads argument; cannot multithread batch mode"))
      }

      try assertDriverDiagnostics(args: "swiftc", "-j", "0") {
        $1.expect(.error("invalid value '0' in '-j'"))
      }

      var env = ProcessEnv.vars
      env["SWIFTC_MAXIMUM_DETERMINISM"] = "1"
      try assertDriverDiagnostics(args: "swiftc", "-j", "8", env: env) {
        $1.expect(.remark("SWIFTC_MAXIMUM_DETERMINISM overriding -j"))
      }
    }

  func testDebugSettings() throws {
    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module") { driver in
      XCTAssertNil(driver.debugInfoLevel)
      XCTAssertEqual(driver.debugInfoFormat, .dwarf)
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module", "-g") { driver in
      XCTAssertEqual(driver.debugInfoLevel, .astTypes)
      XCTAssertEqual(driver.debugInfoFormat, .dwarf)
    }

    try assertNoDriverDiagnostics(args: "swiftc", "-g", "foo.swift", "-gline-tables-only") { driver in
      XCTAssertEqual(driver.debugInfoLevel, .lineTables)
      XCTAssertEqual(driver.debugInfoFormat, .dwarf)
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module", "-g", "-debug-info-format=codeview") { driver in
      XCTAssertEqual(driver.debugInfoLevel, .astTypes)
      XCTAssertEqual(driver.debugInfoFormat, .codeView)
    }

    try assertDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module", "-debug-info-format=dwarf") {
      $1.expect(.error("option '-debug-info-format=' is missing a required argument (-g)"))
    }

    try assertDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module", "-g", "-debug-info-format=notdwarf") {
      $1.expect(.error("invalid value 'notdwarf' in '-debug-info-format='"))
    }

    try assertDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module", "-gdwarf-types", "-debug-info-format=codeview") {
      $1.expect(.error("argument 'codeview' is not allowed with '-gdwarf-types'"))
    }
  }

  func testModuleSettings() throws {
    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift") { driver in
      XCTAssertNil(driver.moduleOutput)
      XCTAssertEqual(driver.moduleName, "foo")
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-g") { driver in
      XCTAssertEqual(driver.moduleOutput, ModuleOutput.auxiliary(VirtualPath.temporary(RelativePath("foo.swiftmodule"))))
      XCTAssertEqual(driver.moduleName, "foo")
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-module-name", "wibble", "bar.swift", "-g") { driver in
      XCTAssertEqual(driver.moduleOutput, ModuleOutput.auxiliary( VirtualPath.temporary(RelativePath("wibble.swiftmodule"))))
      XCTAssertEqual(driver.moduleName, "wibble")
    }

    try assertNoDriverDiagnostics(args: "swiftc", "-emit-module", "foo.swift", "-module-name", "wibble", "bar.swift") { driver in
      XCTAssertEqual(driver.moduleOutput, ModuleOutput.topLevel(try VirtualPath(path: "wibble.swiftmodule")))
      XCTAssertEqual(driver.moduleName, "wibble")
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "bar.swift") { driver in
      XCTAssertNil(driver.moduleOutput)
      XCTAssertEqual(driver.moduleName, "main")
    }

    try assertNoDriverDiagnostics(args: "swift", "-repl") { driver in
      XCTAssertNil(driver.moduleOutput)
      XCTAssertEqual(driver.moduleName, "REPL")
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "bar.swift", "-emit-library", "-o", "libWibble.so") { driver in
      XCTAssertEqual(driver.moduleName, "Wibble")
    }

    try assertDriverDiagnostics(args: "swiftc", "foo.swift", "bar.swift", "-emit-library", "-o", "libWibble.so", "-module-name", "Swift") {
        $1.expect(.error("module name \"Swift\" is reserved for the standard library"))
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "bar.swift", "-emit-module", "-emit-library", "-o", "some/dir/libFoo.so", "-module-name", "MyModule") { driver in
      XCTAssertEqual(driver.moduleOutput, ModuleOutput.topLevel(try VirtualPath(path: "some/dir/MyModule.swiftmodule")))
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "bar.swift", "-emit-module", "-emit-library", "-o", "/", "-module-name", "MyModule") { driver in
      XCTAssertEqual(driver.moduleOutput, ModuleOutput.topLevel(try VirtualPath(path: "/MyModule.swiftmodule")))
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "bar.swift", "-emit-module", "-emit-library", "-o", "../../some/other/dir/libFoo.so", "-module-name", "MyModule") { driver in
      XCTAssertEqual(driver.moduleOutput, ModuleOutput.topLevel(try VirtualPath(path: "../../some/other/dir/MyModule.swiftmodule")))
    }
  }

  func testModuleNameFallbacks() throws {
    try assertNoDriverDiagnostics(args: "swiftc", "file.foo.swift")
    try assertNoDriverDiagnostics(args: "swiftc", ".foo.swift")
    try assertNoDriverDiagnostics(args: "swiftc", "foo-bar.swift")
  }

  func testStandardCompileJobs() throws {
    var driver1 = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test"])
    let plannedJobs = try driver1.planBuild()
    XCTAssertEqual(plannedJobs.count, 3)
    XCTAssertEqual(plannedJobs[0].outputs.count, 1)
    XCTAssertEqual(plannedJobs[0].outputs.first!.file, VirtualPath.temporary(RelativePath("foo.o")))
    XCTAssertEqual(plannedJobs[1].outputs.count, 1)
    XCTAssertEqual(plannedJobs[1].outputs.first!.file, VirtualPath.temporary(RelativePath("bar.o")))
    XCTAssertTrue(plannedJobs[2].tool.name.contains(driver1.targetTriple.isDarwin ? "ld" : "clang"))
    XCTAssertEqual(plannedJobs[2].outputs.count, 1)
    XCTAssertEqual(plannedJobs[2].outputs.first!.file, VirtualPath.relative(RelativePath("Test")))

    // Forwarding of arguments.
    var driver2 = try Driver(args: ["swiftc", "-color-diagnostics", "foo.swift", "bar.swift", "-working-directory", "/tmp", "-api-diff-data-file", "diff.txt", "-Xfrontend", "-HI", "-no-color-diagnostics", "-g"])
    let plannedJobs2 = try driver2.planBuild()
    XCTAssert(plannedJobs2[0].commandLine.contains(Job.ArgTemplate.path(.absolute(try AbsolutePath(validating: "/tmp/diff.txt")))))
    XCTAssert(plannedJobs2[0].commandLine.contains(.flag("-HI")))
    XCTAssert(!plannedJobs2[0].commandLine.contains(.flag("-Xfrontend")))
    XCTAssert(plannedJobs2[0].commandLine.contains(.flag("-no-color-diagnostics")))
    XCTAssert(!plannedJobs2[0].commandLine.contains(.flag("-color-diagnostics")))
    XCTAssert(plannedJobs2[0].commandLine.contains(.flag("-target")))
    XCTAssert(plannedJobs2[0].commandLine.contains(.flag(driver2.targetTriple.triple)))
    XCTAssert(plannedJobs2[0].commandLine.contains(.flag("-enable-anonymous-context-mangled-names")))

    var driver3 = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-emit-library", "-module-name", "Test"])
    let plannedJobs3 = try driver3.planBuild()
    XCTAssertTrue(plannedJobs3[0].commandLine.contains(.flag("-module-name")))
    XCTAssertTrue(plannedJobs3[0].commandLine.contains(.flag("Test")))
    XCTAssertTrue(plannedJobs3[0].commandLine.contains(.flag("-parse-as-library")))
  }

  func testModuleNaming() throws {
    XCTAssertEqual(try Driver(args: ["swiftc", "foo.swift"]).moduleName, "foo")
    XCTAssertEqual(try Driver(args: ["swiftc", "foo.swift", "-o", "a.out"]).moduleName, "a")

    // This is silly, but necesary for compatibility with the integrated driver.
    XCTAssertEqual(try Driver(args: ["swiftc", "foo.swift", "-o", "a.out.optimized"]).moduleName, "main")

    XCTAssertEqual(try Driver(args: ["swiftc", "foo.swift", "-o", "a.out.optimized", "-module-name", "bar"]).moduleName, "bar")
    XCTAssertEqual(try Driver(args: ["swiftc", "foo.swift", "-o", "+++.out"]).moduleName, "main")
    XCTAssertEqual(try Driver(args: ["swift"]).moduleName, "REPL")
    XCTAssertEqual(try Driver(args: ["swiftc", "foo.swift", "-emit-library", "-o", "libBaz.dylib"]).moduleName, "Baz")
  }

  func testOutputFileMapLoading() throws {
    let contents = """
    {
      "": {
        "swift-dependencies": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/master.swiftdeps"
      },
      "/tmp/foo/Sources/foo/foo.swift": {
        "dependencies": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.d",
        "object": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.swift.o",
        "swiftmodule": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo~partial.swiftmodule",
        "swift-dependencies": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.swiftdeps"
      }
    }
    """

    try withTemporaryFile { file in
      try assertNoDiagnostics { diags in
        try localFileSystem.writeFileContents(file.path) { $0 <<< contents }
        let outputFileMap = try OutputFileMap.load(fileSystem: localFileSystem, file: .absolute(file.path), diagnosticEngine: diags)

        let object = try outputFileMap.getOutput(inputFile: .init(path: "/tmp/foo/Sources/foo/foo.swift"), outputType: .object)
        XCTAssertEqual(object.name, "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.swift.o")

        let masterDeps = try outputFileMap.getOutput(inputFile: .init(path: ""), outputType: .swiftDeps)
        XCTAssertEqual(masterDeps.name, "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/master.swiftdeps")
      }
    }
  }

  func testOutputFileMapStoring() throws {
    // Create sample OutputFileMap:

    // Rather than writing VirtualPath(path:...) over and over again, make strings, then fix it
    let stringyEntries: [String: [FileType: String]] = [
      "": [.swiftDeps: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/master.swiftdeps"],
      "foo.swift" : [
        .dependencies: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.d",
        .object: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.swift.o",
        .swiftModule: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo~partial.swiftmodule",
        .swiftDeps: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.swiftdeps"
        ]
    ]
    let pathyEntries = try Dictionary(uniqueKeysWithValues:
      stringyEntries.map { try
        (
          VirtualPath(path: $0.key),
          Dictionary(uniqueKeysWithValues: $0.value.map { try ($0.key, VirtualPath(path: $0.value))})
        )})
    let sampleOutputFileMap = OutputFileMap(entries: pathyEntries)

    try withTemporaryFile { file in
      try sampleOutputFileMap.store(fileSystem: localFileSystem, file: file.path, diagnosticEngine: DiagnosticsEngine())
      let contentsForDebugging = try localFileSystem.readFileContents(file.path).cString
      _ = contentsForDebugging
      let recoveredOutputFileMap = try OutputFileMap.load(fileSystem: localFileSystem, file: .absolute(file.path), diagnosticEngine: DiagnosticsEngine())
      XCTAssertEqual(sampleOutputFileMap, recoveredOutputFileMap)
    }
  }

  func testOutputFileMapResolving() throws {
    // Create sample OutputFileMap:

    let stringyEntries: [String: [FileType: String]] = [
      "": [.swiftDeps: "foo.build/master.swiftdeps"],
      "foo.swift" : [
        .dependencies: "foo.build/foo.d",
        .object: "foo.build/foo.swift.o",
        .swiftModule: "foo.build/foo~partial.swiftmodule",
        .swiftDeps: "foo.build/foo.swiftdeps"
      ]
    ]
    let resolvedStringyEntries: [String: [FileType: String]] = [
      "": [.swiftDeps: "/foo_root/foo.build/master.swiftdeps"],
      "/foo_root/foo.swift" : [
        .dependencies: "/foo_root/foo.build/foo.d",
        .object: "/foo_root/foo.build/foo.swift.o",
        .swiftModule: "/foo_root/foo.build/foo~partial.swiftmodule",
        .swiftDeps: "/foo_root/foo.build/foo.swiftdeps"
      ]
    ]
    func outputFileMapFromStringyEntries(
      _ entries: [String: [FileType: String]]
    ) throws -> OutputFileMap {
      .init(entries: Dictionary(uniqueKeysWithValues: try entries.map { try (
        VirtualPath(path: $0.key),
        $0.value.mapValues(VirtualPath.init(path:))
      )}))
    }
    let sampleOutputFileMap =
      try outputFileMapFromStringyEntries(stringyEntries)
    let resolvedOutputFileMap = sampleOutputFileMap
      .resolveRelativePaths(relativeTo: .init("/foo_root"))
    let expectedOutputFileMap =
      try outputFileMapFromStringyEntries(resolvedStringyEntries)
    XCTAssertEqual(expectedOutputFileMap, resolvedOutputFileMap)
  }

  func testOutputFileMapRelativePathArg() throws {
    try withTemporaryDirectory { path in
      guard let cwd = localFileSystem
        .currentWorkingDirectory else { fatalError() }
      let outputFileMap = path.appending(component: "outputFileMap.json")
      try localFileSystem.writeFileContents(outputFileMap) {
        $0 <<< """
        {
          "": {
            "swift-dependencies": "build/master.swiftdeps"
          },
          "main.swift": {
            "object": "build/main.o",
            "dependencies": "build/main.o.d"
          },
          "util.swift": {
            "object": "build/util.o",
            "dependencies": "build/util.o.d"
          }
        }
        """
      }
      let outputFileMapRelative = outputFileMap.relative(to: cwd).pathString
      // FIXME: Needs a better way to check that outputFileMap correctly loaded
      XCTAssertNoThrow(try Driver(args: [
        "swiftc",
        "--output-file-map", outputFileMapRelative,
        "main.swift", "util.swift",
      ]))
    }
  }

  func testResponseFileExpansion() throws {
    try withTemporaryDirectory { path in
      let diags = DiagnosticsEngine()
      let fooPath = path.appending(component: "foo.rsp")
      let barPath = path.appending(component: "bar.rsp")
      try localFileSystem.writeFileContents(fooPath) {
        $0 <<< "hello\nbye\nbye\\ to\\ you\n@\(barPath.pathString)"
      }
      try localFileSystem.writeFileContents(barPath) {
        $0 <<< "from\nbar\n@\(fooPath.pathString)"
      }
      let args = try Driver.expandResponseFiles(["swift", "compiler", "-Xlinker", "@loader_path", "@" + fooPath.pathString, "something"], fileSystem: localFileSystem, diagnosticsEngine: diags)
      XCTAssertEqual(args, ["swift", "compiler", "-Xlinker", "@loader_path", "hello", "bye", "bye to you", "from", "bar", "something"])
      XCTAssertEqual(diags.diagnostics.count, 1)
      XCTAssert(diags.diagnostics.first!.description.contains("is recursively expanded"))
    }
  }

  /// Tests how response files tokens such as spaces, comments, escaping characters and quotes, get parsed and expanded.
  func testResponseFileTokenization() throws {
    try withTemporaryDirectory { path  in
      let diags = DiagnosticsEngine()
      let fooPath = path.appending(component: "foo.rsp")
      let barPath = path.appending(component: "bar.rsp")
      let escapingPath = path.appending(component: "escaping.rsp")

      try localFileSystem.writeFileContents(fooPath) {
        $0 <<< #"""
        Command1 --kkc
        //This is a comment
        // this is another comment
        but this is \\\\\a command
        @\#(barPath.pathString)
        @NotAFile
        -flag="quoted string with a \"quote\" inside" -another-flag
        """#
        <<< "\nthis  line\thas        lots \t  of    whitespace"
      }

      try localFileSystem.writeFileContents(barPath) {
        $0 <<< #"""
        swift
        "rocks!"
        compiler
        -Xlinker

        @loader_path
        mkdir "Quoted Dir"
        cd Unquoted\ Dir
        // Bye!
        """#
      }

      try localFileSystem.writeFileContents(escapingPath) {
        $0 <<< "swift\n--driver-mode=swiftc\n-v\r\n//comment\n\"the end\""
      }
      let args = try Driver.expandResponseFiles(["@" + fooPath.pathString], fileSystem: localFileSystem, diagnosticsEngine: diags)
      XCTAssertEqual(args, ["Command1", "--kkc", "but", "this", "is", #"\\a"#, "command", #"swift"#, "rocks!" ,"compiler", "-Xlinker", "@loader_path", "mkdir", "Quoted Dir", "cd", "Unquoted Dir", "@NotAFile", #"-flag=quoted string with a "quote" inside"#, "-another-flag", "this", "line", "has", "lots", "of", "whitespace"])
      let escapingArgs = try Driver.expandResponseFiles(["@" + escapingPath.pathString], fileSystem: localFileSystem, diagnosticsEngine: diags)
      XCTAssertEqual(escapingArgs, ["swift", "--driver-mode=swiftc", "-v","the end"])
    }
  }

  func testUsingResponseFiles() throws {
    let manyArgs = (1...500_000).map { "-DTEST_\($0)" }
    // Needs response file
    do {
      var driver = try Driver(args: ["swift"] + manyArgs + ["foo.swift"])
      let jobs = try driver.planBuild()
      XCTAssertTrue(jobs.count == 1 && jobs[0].kind == .interpret)
      let interpretJob = jobs[0]
      let resolver = try ArgsResolver()
      let resolvedArgs: [String] = try resolver.resolveArgumentList(for: interpretJob, forceResponseFiles: false)
      XCTAssertTrue(resolvedArgs.count == 2)
      XCTAssertEqual(resolvedArgs[1].first, "@")
      let responseFilePath = try AbsolutePath(validating: String(resolvedArgs[1].dropFirst()))
      let contents = try localFileSystem.readFileContents(responseFilePath).description
      XCTAssertTrue(contents.hasPrefix("-frontend\n-interpret\nfoo.swift"))
      XCTAssertTrue(contents.contains("-D\nTEST_500000"))
      XCTAssertTrue(contents.contains("-D\nTEST_1"))
    }
    // Forced response file
    do {
      var driver = try Driver(args: ["swift"] + ["foo.swift"])
      let jobs = try driver.planBuild()
      XCTAssertTrue(jobs.count == 1 && jobs[0].kind == .interpret)
      let interpretJob = jobs[0]
      let resolver = try ArgsResolver()
      let resolvedArgs: [String] = try resolver.resolveArgumentList(for: interpretJob, forceResponseFiles: true)
      XCTAssertTrue(resolvedArgs.count == 2)
      XCTAssertEqual(resolvedArgs[1].first, "@")
      let responseFilePath = try AbsolutePath(validating: String(resolvedArgs[1].dropFirst()))
      let contents = try localFileSystem.readFileContents(responseFilePath).description
      XCTAssertTrue(contents.hasPrefix("-frontend\n-interpret\nfoo.swift"))
    }

    // No response file
    do {
      var driver = try Driver(args: ["swift"] + ["foo.swift"])
      let jobs = try driver.planBuild()
      XCTAssertTrue(jobs.count == 1 && jobs[0].kind == .interpret)
      let interpretJob = jobs[0]
      let resolver = try ArgsResolver()
      let resolvedArgs: [String] = try resolver.resolveArgumentList(for: interpretJob, forceResponseFiles: false)
      XCTAssertFalse(resolvedArgs.map { $0.hasPrefix("@") }.reduce(false){ $0 || $1 })
    }
  }

  func testLinking() throws {
    var env = ProcessEnv.vars
    env["SWIFT_DRIVER_TESTS_ENABLE_EXEC_PATH_FALLBACK"] = "1"

    let commonArgs = ["swiftc", "foo.swift", "bar.swift",  "-module-name", "Test"]
    do {
      // macOS target
      var driver = try Driver(args: commonArgs + ["-emit-library", "-target", "x86_64-apple-macosx10.15"], env: env)
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(3, plannedJobs.count)
      XCTAssertFalse(plannedJobs.contains { $0.kind == .autolinkExtract })

      let linkJob = plannedJobs[2]
      XCTAssertEqual(linkJob.kind, .link)

      let cmd = linkJob.commandLine
      XCTAssertTrue(cmd.contains(.flag("-dylib")))
      XCTAssertTrue(cmd.contains(.flag("-arch")))
      XCTAssertTrue(cmd.contains(.flag("x86_64")))
      XCTAssertTrue(cmd.contains(.flag("-macosx_version_min")))
      XCTAssertTrue(cmd.contains(.flag("10.15.0")))
      XCTAssertEqual(linkJob.outputs[0].file, try VirtualPath(path: "libTest.dylib"))

      XCTAssertFalse(cmd.contains(.flag("-static")))
      XCTAssertFalse(cmd.contains(.flag("-shared")))
    }

    do {
      // iOS target
      var driver = try Driver(args: commonArgs + ["-emit-library", "-target", "arm64-apple-ios10.0"], env: env)
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(3, plannedJobs.count)
      XCTAssertFalse(plannedJobs.contains { $0.kind == .autolinkExtract })

      let linkJob = plannedJobs[2]
      XCTAssertEqual(linkJob.kind, .link)

      let cmd = linkJob.commandLine
      XCTAssertTrue(cmd.contains(.flag("-dylib")))
      XCTAssertTrue(cmd.contains(.flag("-arch")))
      XCTAssertTrue(cmd.contains(.flag("arm64")))
      XCTAssertTrue(cmd.contains(.flag("-iphoneos_version_min")))
      XCTAssertTrue(cmd.contains(.flag("10.0.0")))
      XCTAssertEqual(linkJob.outputs[0].file, try VirtualPath(path: "libTest.dylib"))

      XCTAssertFalse(cmd.contains(.flag("-static")))
      XCTAssertFalse(cmd.contains(.flag("-shared")))
    }

    do {
      // macOS catalyst target
      var driver = try Driver(args: commonArgs + ["-emit-library", "-target", "x86_64-apple-ios13.0-macabi"], env: env)
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(3, plannedJobs.count)
      XCTAssertFalse(plannedJobs.contains { $0.kind == .autolinkExtract })

      let linkJob = plannedJobs[2]
      XCTAssertEqual(linkJob.kind, .link)

      let cmd = linkJob.commandLine
      XCTAssertTrue(cmd.contains(.flag("-dylib")))
      XCTAssertTrue(cmd.contains(.flag("-arch")))
      XCTAssertTrue(cmd.contains(.flag("x86_64")))
      XCTAssertTrue(cmd.contains(.flag("-maccatalyst_version_min")))
      XCTAssertTrue(cmd.contains(.flag("13.0.0")))
      XCTAssertEqual(linkJob.outputs[0].file, try VirtualPath(path: "libTest.dylib"))

      XCTAssertFalse(cmd.contains(.flag("-static")))
      XCTAssertFalse(cmd.contains(.flag("-shared")))
    }

    do {
      // Xlinker flags
      var driver = try Driver(args: commonArgs + ["-emit-library", "-L", "/tmp", "-Xlinker", "-w", "-target", "x86_64-apple-macosx10.15"], env: env)
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(3, plannedJobs.count)
      XCTAssertFalse(plannedJobs.contains { $0.kind == .autolinkExtract })

      let linkJob = plannedJobs[2]
      XCTAssertEqual(linkJob.kind, .link)

      let cmd = linkJob.commandLine
      XCTAssertTrue(cmd.contains(.flag("-dylib")))
      XCTAssertTrue(cmd.contains(.flag("-w")))
      XCTAssertTrue(cmd.contains(.flag("-L")))
      XCTAssertTrue(cmd.contains(.path(.absolute(AbsolutePath("/tmp")))))
      XCTAssertEqual(linkJob.outputs[0].file, try VirtualPath(path: "libTest.dylib"))

      XCTAssertFalse(cmd.contains(.flag("-static")))
      XCTAssertFalse(cmd.contains(.flag("-shared")))
    }

    do {
      // static linking
      var driver = try Driver(args: commonArgs + ["-emit-library", "-static", "-L", "/tmp", "-Xlinker", "-w", "-target", "x86_64-apple-macosx10.15"], env: env)
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertFalse(plannedJobs.contains { $0.kind == .autolinkExtract })

      let linkJob = plannedJobs[2]
      XCTAssertEqual(linkJob.kind, .link)

      let cmd = linkJob.commandLine
      XCTAssertTrue(cmd.contains(.flag("-static")))
      XCTAssertTrue(cmd.contains(.flag("-o")))
      XCTAssertTrue(cmd.contains(.path(.temporary(RelativePath("foo.o")))))
      XCTAssertTrue(cmd.contains(.path(.temporary(RelativePath("bar.o")))))
      XCTAssertEqual(linkJob.outputs[0].file, try VirtualPath(path: "libTest.a"))

      // The regular Swift driver doesn't pass Xlinker flags to the static
      // linker, so be consistent with this
      XCTAssertFalse(cmd.contains(.flag("-w")))
      XCTAssertFalse(cmd.contains(.flag("-L")))
      XCTAssertFalse(cmd.contains(.path(.absolute(AbsolutePath("/tmp")))))

      XCTAssertFalse(cmd.contains(.flag("-dylib")))
      XCTAssertFalse(cmd.contains(.flag("-shared")))
    }

    do {
      // executable linking
      var driver = try Driver(args: commonArgs + ["-emit-executable", "-target", "x86_64-apple-macosx10.15"], env: env)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(3, plannedJobs.count)
      XCTAssertFalse(plannedJobs.contains { $0.kind == .autolinkExtract })

      let linkJob = plannedJobs[2]
      XCTAssertEqual(linkJob.kind, .link)

      let cmd = linkJob.commandLine
      XCTAssertTrue(cmd.contains(.flag("-o")))
      XCTAssertTrue(cmd.contains(.path(.temporary(RelativePath("foo.o")))))
      XCTAssertTrue(cmd.contains(.path(.temporary(RelativePath("bar.o")))))
      XCTAssertEqual(linkJob.outputs[0].file, try VirtualPath(path: "Test"))

      XCTAssertFalse(cmd.contains(.flag("-static")))
      XCTAssertFalse(cmd.contains(.flag("-dylib")))
      XCTAssertFalse(cmd.contains(.flag("-shared")))
    }

    // FIXME: This test will fail when run on macOS, because
    // swift-autolink-extract is not present
    #if os(Linux)
    do {
      // linux target
      var driver = try Driver(args: commonArgs + ["-emit-library", "-target", "x86_64-unknown-linux"])
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 4)

      let autolinkExtractJob = plannedJobs[2]
      XCTAssertEqual(autolinkExtractJob.kind, .autolinkExtract)

      let autolinkCmd = autolinkExtractJob.commandLine
      XCTAssertTrue(autolinkCmd.contains(.path(.temporary(RelativePath("foo.o")))))
      XCTAssertTrue(autolinkCmd.contains(.path(.temporary(RelativePath("bar.o")))))
      XCTAssertTrue(autolinkCmd.contains(.path(.temporary(RelativePath("Test.autolink")))))

      let linkJob = plannedJobs[3]
      XCTAssertEqual(linkJob.kind, .link)
      let cmd = linkJob.commandLine
      XCTAssertTrue(cmd.contains(.flag("-o")))
      XCTAssertTrue(cmd.contains(.flag("-shared")))
      XCTAssertTrue(cmd.contains(.path(.temporary(RelativePath("foo.o")))))
      XCTAssertTrue(cmd.contains(.path(.temporary(RelativePath("bar.o")))))
      XCTAssertEqual(linkJob.outputs[0].file, try VirtualPath(path: "libTest.so"))

      XCTAssertFalse(cmd.contains(.flag("-dylib")))
      XCTAssertFalse(cmd.contains(.flag("-static")))
    }
    #endif

    // FIXME: This test will fail when run on macOS, because
    // swift-autolink-extract is not present
    #if os(Linux)
    do {
      // static linux linking
      var driver = try Driver(args: commonArgs + ["-emit-library", "-static", "-target", "x86_64-unknown-linux"])
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 4)

      let autolinkExtractJob = plannedJobs[2]
      XCTAssertEqual(autolinkExtractJob.kind, .autolinkExtract)

      let autolinkCmd = autolinkExtractJob.commandLine
      XCTAssertTrue(autolinkCmd.contains(.path(.temporary(RelativePath("foo.o")))))
      XCTAssertTrue(autolinkCmd.contains(.path(.temporary(RelativePath("bar.o")))))
      XCTAssertTrue(autolinkCmd.contains(.path(.temporary(RelativePath("Test.autolink")))))

      let linkJob = plannedJobs[3]
      let cmd = linkJob.commandLine
      // we'd expect "ar crs libTest.a foo.o bar.o"
      XCTAssertTrue(cmd.contains(.flag("crs")))
      XCTAssertTrue(cmd.contains(.path(.temporary(RelativePath("foo.o")))))
      XCTAssertTrue(cmd.contains(.path(.temporary(RelativePath("bar.o")))))
      XCTAssertEqual(linkJob.outputs[0].file, try VirtualPath(path: "libTest.a"))

      XCTAssertFalse(cmd.contains(.flag("-o")))
      XCTAssertFalse(cmd.contains(.flag("-dylib")))
      XCTAssertFalse(cmd.contains(.flag("-static")))
      XCTAssertFalse(cmd.contains(.flag("-shared")))
    }
    #endif
  }

  func testSanitizerArgs() throws {
  // FIXME: This doesn't work on Linux.
  #if os(macOS)
    let commonArgs = [
      "swiftc", "foo.swift", "bar.swift",
      "-emit-executable", "-target", "x86_64-apple-macosx",
      "-module-name", "Test"
    ]
    do {
      // address sanitizer
      var driver = try Driver(args: commonArgs + ["-sanitize=address"])
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 3)

      let compileJob = plannedJobs[0]
      let compileCmd = compileJob.commandLine
      XCTAssertTrue(compileCmd.contains(.flag("-sanitize=address")))

      let linkJob = plannedJobs[2]
      let linkCmd = linkJob.commandLine
      XCTAssertTrue(linkCmd.contains {
        if case .path(let path) = $0 {
          return path.name.contains("darwin/libclang_rt.asan_osx_dynamic.dylib")
        }
        return false
      })
    }

    do {
      // thread sanitizer
      var driver = try Driver(args: commonArgs + ["-sanitize=thread"])
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 3)

      let compileJob = plannedJobs[0]
      let compileCmd = compileJob.commandLine
      XCTAssertTrue(compileCmd.contains(.flag("-sanitize=thread")))

      let linkJob = plannedJobs[2]
      let linkCmd = linkJob.commandLine
      XCTAssertTrue(linkCmd.contains {
        if case .path(let path) = $0 {
          return path.name.contains("darwin/libclang_rt.tsan_osx_dynamic.dylib")
        }
        return false
      })
    }

    do {
      // undefined behavior sanitizer
      var driver = try Driver(args: commonArgs + ["-sanitize=undefined"])
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 3)

      let compileJob = plannedJobs[0]
      let compileCmd = compileJob.commandLine
      XCTAssertTrue(compileCmd.contains(.flag("-sanitize=undefined")))

      let linkJob = plannedJobs[2]
      let linkCmd = linkJob.commandLine
      XCTAssertTrue(linkCmd.contains {
        if case .path(let path) = $0 {
          return path.name.contains("darwin/libclang_rt.ubsan_osx_dynamic.dylib")
        }
        return false
      })
    }

    // FIXME: This test will fail when run on macOS, because the driver uses
    //        the existence of the runtime support libraries to determine if
    //        a sanitizer is supported. Until we allow cross-compiling with
    //        sanitizers, we'll need to disable this test on macOS
    #if os(Linux)
    do {
      // linux multiple sanitizers
      var driver = try Driver(
        args: commonArgs + [
          "-target", "x86_64-unknown-linux",
          "-sanitize=address", "-sanitize=undefined"
        ]
      )
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 4)

      let compileJob = plannedJobs[0]
      let compileCmd = compileJob.commandLine
      XCTAssertTrue(compileCmd.contains(.flag("-sanitize=address")))
      XCTAssertTrue(compileCmd.contains(.flag("-sanitize=undefined")))

      let linkJob = plannedJobs[3]
      let linkCmd = linkJob.commandLine
      XCTAssertTrue(linkCmd.contains(.flag("-fsanitize=address,undefined")))
    }
    #endif
  #endif
  }

  func testBatchModeCompiles() throws {
    do {
      var driver1 = try Driver(args: ["swiftc", "foo1.swift", "bar1.swift", "foo2.swift", "bar2.swift", "foo3.swift", "bar3.swift", "foo4.swift", "bar4.swift", "foo5.swift", "bar5.swift", "wibble.swift", "-module-name", "Test", "-enable-batch-mode", "-driver-batch-count", "3"])
      let plannedJobs = try driver1.planBuild()
      XCTAssertEqual(plannedJobs.count, 4)
      XCTAssertEqual(plannedJobs[0].outputs.count, 4)
      XCTAssertEqual(plannedJobs[0].outputs.first!.file, VirtualPath.temporary(RelativePath("foo1.o")))
      XCTAssertEqual(plannedJobs[1].outputs.count, 4)
      XCTAssertEqual(plannedJobs[1].outputs.first!.file, VirtualPath.temporary(RelativePath("foo3.o")))
      XCTAssertEqual(plannedJobs[2].outputs.count, 3)
      XCTAssertEqual(plannedJobs[2].outputs.first!.file, VirtualPath.temporary(RelativePath("foo5.o")))
      XCTAssertTrue(plannedJobs[3].tool.name.contains(driver1.targetTriple.isDarwin ? "ld" : "clang"))
      XCTAssertEqual(plannedJobs[3].outputs.count, 1)
      XCTAssertEqual(plannedJobs[3].outputs.first!.file, VirtualPath.relative(RelativePath("Test")))
    }

    // Test 1 partition results in 1 job
    do {
      var driver = try Driver(args: ["swiftc", "-toolchain-stdlib-rpath", "-module-cache-path", "/tmp/clang-module-cache", "-swift-version", "4", "-Xfrontend", "-ignore-module-source-info", "-module-name", "batch", "-enable-batch-mode", "-j", "1", "-c", "main.swift", "lib.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      var count = 0
      for arg in plannedJobs[0].commandLine where arg == .flag("-primary-file") {
        count += 1
      }
      XCTAssertEqual(count, 2)
    }
  }

  func testSingleThreadedWholeModuleOptimizationCompiles() throws {
    var driver1 = try Driver(args: ["swiftc", "-whole-module-optimization", "foo.swift", "bar.swift", "-module-name", "Test", "-target", "x86_64-apple-macosx10.15", "-emit-module-interface", "-emit-objc-header-path", "Test-Swift.h"])
    let plannedJobs = try driver1.planBuild()
    XCTAssertEqual(plannedJobs.count, 2)
    XCTAssertEqual(plannedJobs[0].kind, .compile)
    XCTAssertEqual(plannedJobs[0].outputs.count, 3)
    XCTAssertEqual(plannedJobs[0].outputs[0].file, VirtualPath.temporary(RelativePath("Test.o")))
    XCTAssertEqual(plannedJobs[0].outputs[1].file, VirtualPath.relative(RelativePath("Test-Swift.h")))
    XCTAssertEqual(plannedJobs[0].outputs[2].file, VirtualPath.relative(RelativePath("Test.swiftinterface")))
    XCTAssert(!plannedJobs[0].commandLine.contains(.flag("-primary-file")))
    XCTAssert(plannedJobs[0].commandLine.contains(.flag("-emit-module-interface-path")))

    XCTAssertEqual(plannedJobs[1].kind, .link)
  }

  func testMultiThreadedWholeModuleOptimizationCompiles() throws {
    do {
      var driver1 = try Driver(args: [
        "swiftc", "-whole-module-optimization", "foo.swift", "bar.swift", "wibble.swift",
        "-module-name", "Test", "-num-threads", "4"
      ])
      let plannedJobs = try driver1.planBuild()
      XCTAssertEqual(plannedJobs.count, 2)
      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertEqual(plannedJobs[0].outputs.count, 3)
      XCTAssertEqual(plannedJobs[0].outputs[0].file, VirtualPath.temporary(RelativePath("foo.o")))
      XCTAssertEqual(plannedJobs[0].outputs[1].file, VirtualPath.temporary(RelativePath("bar.o")))
      XCTAssertEqual(plannedJobs[0].outputs[2].file, VirtualPath.temporary(RelativePath("wibble.o")))
      XCTAssert(!plannedJobs[0].commandLine.contains(.flag("-primary-file")))

      XCTAssertEqual(plannedJobs[1].kind, .link)
    }

    // emit-module
    do {
      var driver = try Driver(args: ["swiftc", "-module-name=ThisModule", "-wmo", "-num-threads", "4", "main.swift", "multi-threaded.swift", "-emit-module", "-o", "test.swiftmodule"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertEqual(plannedJobs[0].inputs.count, 2)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, VirtualPath.relative(RelativePath("main.swift")))
      XCTAssertEqual(plannedJobs[0].inputs[1].file, VirtualPath.relative(RelativePath("multi-threaded.swift")))
      XCTAssertEqual(plannedJobs[0].outputs.count, 2)
      XCTAssertEqual(plannedJobs[0].outputs[0].file, VirtualPath.relative(RelativePath("test.swiftmodule")))
    }
  }

  func testWholeModuleOptimizationOutputFileMap() throws {
    let contents = """
    {
      "": {
        "swiftinterface": "/tmp/salty/Test.swiftinterface"
      }
    }
    """

    try withTemporaryFile { file in
      try assertNoDiagnostics { diags in
        try localFileSystem.writeFileContents(file.path) { $0 <<< contents }
        var driver1 = try Driver(args: [
          "swiftc", "-whole-module-optimization", "foo.swift", "bar.swift", "wibble.swift", "-module-name", "Test",
          "-num-threads", "4", "-output-file-map", file.path.pathString, "-emit-module-interface"
        ])
        let plannedJobs = try driver1.planBuild()
        XCTAssertEqual(plannedJobs.count, 2)
        XCTAssertEqual(plannedJobs[0].kind, .compile)
        XCTAssertEqual(plannedJobs[0].outputs.count, 4)
        XCTAssertEqual(plannedJobs[0].outputs[0].file, VirtualPath.temporary(RelativePath("foo.o")))
        XCTAssertEqual(plannedJobs[0].outputs[1].file, VirtualPath.temporary(RelativePath("bar.o")))
        XCTAssertEqual(plannedJobs[0].outputs[2].file, VirtualPath.temporary(RelativePath("wibble.o")))
        XCTAssertEqual(plannedJobs[0].outputs[3].file, VirtualPath.absolute(AbsolutePath("/tmp/salty/Test.swiftinterface")))
        XCTAssert(!plannedJobs[0].commandLine.contains(.flag("-primary-file")))

        XCTAssertEqual(plannedJobs[1].kind, .link)
      }
    }
  }

  func testMergeModulesOnly() throws {
    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module", "-disable-bridging-pch", "-import-objc-header", "TestInputHeader.h", "-emit-dependencies", "-emit-module-doc-path", "/foo/bar/Test.swiftdoc"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertEqual(plannedJobs[0].outputs.count, 3)
      XCTAssertEqual(plannedJobs[0].outputs[0].file, .temporary(RelativePath("foo.swiftmodule")))
      XCTAssertEqual(plannedJobs[0].outputs[1].file, .temporary(RelativePath("foo.swiftdoc")))
      XCTAssertEqual(plannedJobs[0].outputs[2].file, .temporary(RelativePath("foo.d")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-import-objc-header")))

      XCTAssertEqual(plannedJobs[1].outputs.count, 3)
      XCTAssertEqual(plannedJobs[1].outputs[0].file, .temporary(RelativePath("bar.swiftmodule")))
      XCTAssertEqual(plannedJobs[1].outputs[1].file, .temporary(RelativePath("bar.swiftdoc")))
      XCTAssertEqual(plannedJobs[1].outputs[2].file, .temporary(RelativePath("bar.d")))
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("-import-objc-header")))

      XCTAssertTrue(plannedJobs[2].tool.name.contains("swift"))
      XCTAssertEqual(plannedJobs[2].outputs.count, 3)
      XCTAssertEqual(plannedJobs[2].outputs[0].file, .relative(RelativePath("Test.swiftmodule")))
      XCTAssertEqual(plannedJobs[2].outputs[1].file, .absolute(AbsolutePath("/foo/bar/Test.swiftdoc")))
      XCTAssert(plannedJobs[2].commandLine.contains(.flag("-import-objc-header")))
    }

    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-path", "/foo/bar/Test.swiftmodule" ])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertTrue(plannedJobs[2].tool.name.contains("swift"))
      XCTAssertEqual(plannedJobs[2].outputs.count, 2)
      XCTAssertEqual(plannedJobs[2].outputs[0].file, VirtualPath.absolute(AbsolutePath("/foo/bar/Test.swiftmodule")))
      XCTAssertEqual(plannedJobs[2].outputs[1].file, .absolute(AbsolutePath("/foo/bar/Test.swiftdoc")))
    }

    do {
      // Make sure the swiftdoc path is correct for a relative module
      var driver = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-path", "Test.swiftmodule" ])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertTrue(plannedJobs[2].tool.name.contains("swift"))
      XCTAssertEqual(plannedJobs[2].outputs.count, 2)
      XCTAssertEqual(plannedJobs[2].outputs[0].file, .relative(RelativePath("Test.swiftmodule")))
      XCTAssertEqual(plannedJobs[2].outputs[1].file, .relative(RelativePath("Test.swiftdoc")))
    }

    do {
      // Make sure the swiftdoc path is correct for an inferred module
      var driver = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-doc", "-emit-module"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertTrue(plannedJobs[2].tool.name.contains("swift"))
      XCTAssertEqual(plannedJobs[2].outputs.count, 2)
      XCTAssertEqual(plannedJobs[2].outputs[0].file, .relative(RelativePath("Test.swiftmodule")))
      XCTAssertEqual(plannedJobs[2].outputs[1].file, .relative(RelativePath("Test.swiftdoc")))
    }

    do {
      // -o specified
      var driver = try Driver(args: ["swiftc", "-emit-module", "-o", "/tmp/test.swiftmodule", "input.swift"])
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 2)
      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertEqual(plannedJobs[0].outputs[0].file, .temporary(RelativePath("input.swiftmodule")))
      XCTAssertEqual(plannedJobs[1].kind, .mergeModule)
      XCTAssertEqual(plannedJobs[1].inputs[0].file, .temporary(RelativePath("input.swiftmodule")))
      XCTAssertEqual(plannedJobs[1].outputs[0].file, .absolute(AbsolutePath("/tmp/test.swiftmodule")))
    }
  }

  func testRepl() throws {

    func isLLDBREPLFlag(_ arg: Job.ArgTemplate) -> Bool {
      if case .flag(let replString) = arg {
        return replString.hasPrefix("--repl=") &&
          !replString.contains("-module-name")
      }
      return false
    }

    do {
      var driver = try Driver(args: ["swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      let replJob = plannedJobs.first!
      XCTAssertTrue(replJob.tool.name.contains("lldb"))
      XCTAssertTrue(replJob.requiresInPlaceExecution)
      XCTAssert(replJob.commandLine.contains(where: { isLLDBREPLFlag($0) }))
    }

    do {
      var driver = try Driver(args: ["swift", "-repl"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      let replJob = plannedJobs.first!
      XCTAssertTrue(replJob.tool.name.contains("lldb"))
      XCTAssertTrue(replJob.requiresInPlaceExecution)
      XCTAssert(replJob.commandLine.contains(where: { isLLDBREPLFlag($0) }))
    }

    do {
      let (mode, args) = try Driver.invocationRunMode(forArgs: ["swift", "repl"])
      XCTAssertEqual(mode, .normal(isRepl: true))
      var driver = try Driver(args: args)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      let replJob = plannedJobs.first!
      XCTAssertTrue(replJob.tool.name.contains("lldb"))
      XCTAssertTrue(replJob.requiresInPlaceExecution)
      XCTAssert(replJob.commandLine.contains(where: { isLLDBREPLFlag($0) }))
    }

    do {
      XCTAssertThrowsError(try Driver(args: ["swift", "-deprecated-integrated-repl"])) {
        XCTAssertEqual($0 as? Driver.Error, Driver.Error.integratedReplRemoved)
      }
    }

    do {
      var driver = try Driver(args: ["swift", "-repl", "/foo/bar/Test.swift"])
      XCTAssertThrowsError(try driver.planBuild()) { error in
        XCTAssertEqual(error as? PlanningError, .replReceivedInput)
      }
    }
  }

  func testImmediateMode() throws {
    do {
      var driver = try Driver(args: ["swift", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      let job = plannedJobs[0]
      XCTAssertTrue(job.requiresInPlaceExecution)
      XCTAssertEqual(job.inputs.count, 1)
      XCTAssertEqual(job.inputs[0].file, .relative(RelativePath("foo.swift")))
      XCTAssertEqual(job.outputs.count, 0)
      XCTAssertTrue(job.commandLine.contains(.flag("-frontend")))
      XCTAssertTrue(job.commandLine.contains(.flag("-interpret")))
      XCTAssertTrue(job.commandLine.contains(.flag("-module-name")))
      XCTAssertTrue(job.commandLine.contains(.flag("foo")))

      if driver.targetTriple.isMacOSX {
        XCTAssertTrue(job.commandLine.contains(.flag("-sdk")))
      }

      XCTAssertFalse(job.commandLine.contains(.flag("--")))
      XCTAssertTrue(job.extraEnvironment.keys.contains("\(driver.targetTriple.isDarwin ? "DYLD" : "LD")_LIBRARY_PATH"))
    }

    do {
      var driver = try Driver(args: ["swift", "foo.swift", "-some", "args", "-for=foo"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      let job = plannedJobs[0]
      XCTAssertTrue(job.requiresInPlaceExecution)
      XCTAssertEqual(job.inputs.count, 1)
      XCTAssertEqual(job.inputs[0].file, .relative(RelativePath("foo.swift")))
      XCTAssertEqual(job.outputs.count, 0)
      XCTAssertTrue(job.commandLine.contains(.flag("-frontend")))
      XCTAssertTrue(job.commandLine.contains(.flag("-interpret")))
      XCTAssertTrue(job.commandLine.contains(.flag("-module-name")))
      XCTAssertTrue(job.commandLine.contains(.flag("foo")))
      XCTAssertTrue(job.commandLine.contains(.flag("--")))
      XCTAssertTrue(job.commandLine.contains(.flag("-some")))
      XCTAssertTrue(job.commandLine.contains(.flag("args")))
      XCTAssertTrue(job.commandLine.contains(.flag("-for=foo")))
    }

    do {
      var driver = try Driver(args: ["swift", "-L/path/to/lib", "-F/path/to/framework", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      let job = plannedJobs[0]
      XCTAssertTrue(job.requiresInPlaceExecution)
      XCTAssertEqual(job.inputs.count, 1)
      XCTAssertEqual(job.inputs[0].file, .relative(RelativePath("foo.swift")))
      XCTAssertEqual(job.outputs.count, 0)
      XCTAssertTrue(job.extraEnvironment.contains {
        $0 == "\(driver.targetTriple.isDarwin ? "DYLD" : "LD")_LIBRARY_PATH" && $1.contains("/path/to/lib")
      })
      if driver.targetTriple.isDarwin {
        XCTAssertTrue(job.extraEnvironment.contains { $0 == "DYLD_FRAMEWORK_PATH" && $1.contains("/path/to/framework") })
      }
    }
  }

  func testTargetTriple() throws {
    let driver1 = try Driver(args: ["swiftc", "-c", "foo.swift", "-module-name", "Foo"])

    let expectedDefaultContents: String
    #if os(macOS)
    expectedDefaultContents = "x86_64-apple-darwin"
    #elseif os(Linux)
    expectedDefaultContents = "-unknown-linux"
    #else
    expectedDefaultContents = "-"
    #endif

    XCTAssert(driver1.targetTriple.triple.contains(expectedDefaultContents),
              "Default triple \(driver1.targetTriple) contains \(expectedDefaultContents)")

    let driver2 = try Driver(args: ["swiftc", "-c", "-target", "x86_64-apple-watchos12", "foo.swift", "-module-name", "Foo"])
    XCTAssertEqual(driver2.targetTriple.triple, "x86_64-apple-watchos12")

    let driver3 = try Driver(args: ["swiftc", "-c", "-target", "x86_64-watchos12", "foo.swift", "-module-name", "Foo"])
    XCTAssertEqual(driver3.targetTriple.triple, "x86_64-unknown-watchos12")
  }

  func testTargetVariant() throws {
    do {
      var driver = try Driver(args: ["swiftc", "-c", "-target", "x86_64-apple-ios13.0-macabi", "-target-variant", "x86_64-apple-macosx10.14", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)

      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-target")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("x86_64-apple-ios13.0-macabi")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-target-variant")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("x86_64-apple-macosx10.14")))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-emit-library", "-target", "x86_64-apple-ios13.0-macabi", "-target-variant", "x86_64-apple-macosx10.14", "-module-name", "foo", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 2)

      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-target")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("x86_64-apple-ios13.0-macabi")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-target-variant")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("x86_64-apple-macosx10.14")))

      XCTAssertEqual(plannedJobs[1].kind, .link)
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("-maccatalyst_version_min")))
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("13.0.0")))
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("-macosx_version_min")))
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("10.14.0")))
    }

    // Test -target-variant is passed to generate pch job
    do {
      var driver = try Driver(args: ["swiftc", "-target", "x86_64-apple-ios13.0-macabi", "-target-variant", "x86_64-apple-macosx10.14", "-enable-bridging-pch", "-import-objc-header", "TestInputHeader.h", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)

      XCTAssertEqual(plannedJobs[0].kind, .generatePCH)
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-emit-pch")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-target")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("x86_64-apple-ios13.0-macabi")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-target-variant")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("x86_64-apple-macosx10.14")))

      XCTAssertEqual(plannedJobs[1].kind, .compile)
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("-target")))
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("x86_64-apple-ios13.0-macabi")))
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("-target-variant")))
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("x86_64-apple-macosx10.14")))

      XCTAssertEqual(plannedJobs[2].kind, .link)
      XCTAssert(plannedJobs[2].commandLine.contains(.flag("-maccatalyst_version_min")))
      XCTAssert(plannedJobs[2].commandLine.contains(.flag("13.0.0")))
      XCTAssert(plannedJobs[2].commandLine.contains(.flag("-macosx_version_min")))
      XCTAssert(plannedJobs[2].commandLine.contains(.flag("10.14.0")))
    }
  }

  func testDSYMGeneration() throws {
    let commonArgs = [
      "swiftc", "foo.swift", "bar.swift",
      "-emit-executable", "-module-name", "Test"
    ]

    do {
      // No dSYM generation (no -g)
      var driver = try Driver(args: commonArgs)
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertFalse(plannedJobs.contains { $0.kind == .generateDSYM })
    }

    do {
      // No dSYM generation (-gnone)
      var driver = try Driver(args: commonArgs + ["-gnone"])
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertFalse(plannedJobs.contains { $0.kind == .generateDSYM })
    }

    do {
      // dSYM generation (-g)
      var driver = try Driver(args: commonArgs + ["-g"])
      let plannedJobs = try driver.planBuild()

      let generateDSYMJob = plannedJobs.last!
      let cmd = generateDSYMJob.commandLine

      if driver.targetTriple.isDarwin {
        XCTAssertEqual(plannedJobs.count, 5)
        XCTAssertEqual(generateDSYMJob.outputs.last?.file, try VirtualPath(path: "Test.dSYM"))
      } else {
        XCTAssertEqual(plannedJobs.count, 4)
      }

      XCTAssertTrue(cmd.contains(.path(try VirtualPath(path: "Test"))))
    }
  }

  func testVerifyDebugInfo() throws {
    let commonArgs = [
      "swiftc", "foo.swift", "bar.swift",
      "-emit-executable", "-module-name", "Test", "-verify-debug-info"
    ]

    // No dSYM generation (no -g), therefore no verification
    try assertDriverDiagnostics(args: commonArgs) { driver, verifier in
      verifier.expect(.warning("ignoring '-verify-debug-info'; no debug info is being generated"))
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertFalse(plannedJobs.contains { $0.kind == .verifyDebugInfo })
    }

    // No dSYM generation (-gnone), therefore no verification
    try assertDriverDiagnostics(args: commonArgs + ["-gnone"]) { driver, verifier in
      verifier.expect(.warning("ignoring '-verify-debug-info'; no debug info is being generated"))
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertFalse(plannedJobs.contains { $0.kind == .verifyDebugInfo })
    }

    do {
      // dSYM generation and verification (-g + -verify-debug-info)
      var driver = try Driver(args: commonArgs + ["-g"])
      let plannedJobs = try driver.planBuild()

      let verifyDebugInfoJob = plannedJobs.last!
      let cmd = verifyDebugInfoJob.commandLine

      if driver.targetTriple.isDarwin {
        XCTAssertEqual(plannedJobs.count, 6)
        XCTAssertEqual(verifyDebugInfoJob.inputs.first?.file, try VirtualPath(path: "Test.dSYM"))
        XCTAssertTrue(cmd.contains(.flag("--verify")))
        XCTAssertTrue(cmd.contains(.flag("--debug-info")))
        XCTAssertTrue(cmd.contains(.flag("--eh-frame")))
        XCTAssertTrue(cmd.contains(.flag("--quiet")))
        XCTAssertTrue(cmd.contains(.path(try VirtualPath(path: "Test.dSYM"))))
      } else {
        XCTAssertEqual(plannedJobs.count, 4)
      }
    }
  }

  func testDOTFileEmission() throws {
    var driver = try Driver(args: [
      "swiftc", "-emit-executable", "test.swift", "-emit-module"
    ])
    let plannedJobs = try driver.planBuild()

    var serializer = DOTJobGraphSerializer(jobs: plannedJobs)
    var output = ""
    serializer.writeDOT(to: &output)

    let dynamicLinker = driver.targetTriple.isDarwin ? "ld" : "clang"
    XCTAssertEqual(output,
    """
    digraph Jobs {
      "compile (swift)" [style=bold];
      "test.swift" [fontsize=12];
      "test.swift" -> "compile (swift)" [color=blue];
      "test.o" [fontsize=12];
      "compile (swift)" -> "test.o" [color=green];
      "test.swiftmodule" [fontsize=12];
      "compile (swift)" -> "test.swiftmodule" [color=green];
      "test.swiftdoc" [fontsize=12];
      "compile (swift)" -> "test.swiftdoc" [color=green];
      "mergeModule (swift)" [style=bold];
      "test.swiftmodule" -> "mergeModule (swift)" [color=blue];
      "mergeModule (swift)" -> "test.swiftmodule" [color=green];
      "mergeModule (swift)" -> "test.swiftdoc" [color=green];
      "link (\(dynamicLinker))" [style=bold];
      "test.o" -> "link (\(dynamicLinker))" [color=blue];
      "test" [fontsize=12];
      "link (\(dynamicLinker))" -> "test" [color=green];
    }

    """)
  }

  func testRegressions() throws {
    var driverWithEmptySDK = try Driver(args: ["swiftc", "-sdk", "", "file.swift"])
    _ = try driverWithEmptySDK.planBuild()
  }

  func testToolchainUtilities() throws {
    let darwinToolchain = DarwinToolchain(env: ProcessEnv.vars)
    let darwinSwiftVersion = try darwinToolchain.swiftCompilerVersion()
    let unixToolchain =  GenericUnixToolchain(env: ProcessEnv.vars)
    let unixSwiftVersion = try unixToolchain.swiftCompilerVersion()
    assertString(darwinSwiftVersion, contains: "Swift version ")
    assertString(unixSwiftVersion, contains: "Swift version ")
  }

  func testToolchainClangPath() {
    // TODO: remove this conditional check once DarwinToolchain does not requires xcrun to look for clang.
    var toolchain: Toolchain
    #if os(macOS)
    toolchain = DarwinToolchain(env: ProcessEnv.vars)
    #else
    toolchain = GenericUnixToolchain(env: ProcessEnv.vars)
    #endif

    XCTAssertEqual(
      try? toolchain.getToolPath(.swiftCompiler).parentDirectory,
      try? toolchain.getToolPath(.clang).parentDirectory
    )
  }

  func testExecutableFallbackPath() throws {
    let driver1 = try Driver(args: ["swift", "main.swift"])
    if !driver1.targetTriple.isDarwin {
      XCTAssertThrowsError(try driver1.toolchain.getToolPath(.dsymutil))
    }

    var env = ProcessEnv.vars
    env["SWIFT_DRIVER_TESTS_ENABLE_EXEC_PATH_FALLBACK"] = "1"
    let driver2 = try Driver(args: ["swift", "main.swift"], env: env)
    XCTAssertNoThrow(try driver2.toolchain.getToolPath(.dsymutil))
  }

  func testVersionRequest() throws {
    for arg in ["-version", "--version"] {
      var driver = try Driver(args: ["swift"] + [arg])
      let plannedJobs = try driver.planBuild()
      XCTAssertTrue(plannedJobs.count == 1)
      let job = plannedJobs[0]
      XCTAssertEqual(job.kind, .versionRequest)
      XCTAssertEqual(job.commandLine, [.flag("--version")])
    }
  }

  func testPrintTargetInfo() throws {
    do {
      var driver = try Driver(args: ["swift", "-print-target-info", "-target", "arm64-apple-ios12.0", "-sdk", "bar", "-resource-dir", "baz"])
      let plannedJobs = try driver.planBuild()
      XCTAssertTrue(plannedJobs.count == 1)
      let job = plannedJobs[0]
      XCTAssertEqual(job.kind, .printTargetInfo)
      XCTAssertTrue(job.commandLine.contains(.flag("-print-target-info")))
      XCTAssertTrue(job.commandLine.contains(.flag("-target")))
      XCTAssertTrue(job.commandLine.contains(.flag("-sdk")))
      XCTAssertTrue(job.commandLine.contains(.flag("-resource-dir")))
    }

    do {
      var driver = try Driver(args: ["swift", "-print-target-info", "-target", "x86_64-apple-ios13.0-macabi", "-target-variant", "x86_64-apple-macosx10.14", "-sdk", "bar", "-resource-dir", "baz"])
      let plannedJobs = try driver.planBuild()
      XCTAssertTrue(plannedJobs.count == 1)
      let job = plannedJobs[0]
      XCTAssertEqual(job.kind, .printTargetInfo)
      XCTAssertTrue(job.commandLine.contains(.flag("-print-target-info")))
      XCTAssertTrue(job.commandLine.contains(.flag("-target")))
      XCTAssertTrue(job.commandLine.contains(.flag("-target-variant")))
      XCTAssertTrue(job.commandLine.contains(.flag("-sdk")))
      XCTAssertTrue(job.commandLine.contains(.flag("-resource-dir")))
    }
  }

  func testDiagnosticOptions() throws {
    do {
      var driver = try Driver(args: ["swift", "-no-warnings-as-errors", "-warnings-as-errors", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      let job = plannedJobs[0]
      XCTAssertTrue(job.commandLine.contains(.flag("-warnings-as-errors")))
    }

    do {
      var driver = try Driver(args: ["swift", "-warnings-as-errors", "-no-warnings-as-errors", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      let job = plannedJobs[0]
      XCTAssertTrue(job.commandLine.contains(.flag("-no-warnings-as-errors")))
    }

    do {
      var driver = try Driver(args: ["swift", "-warnings-as-errors", "-no-warnings-as-errors", "-suppress-warnings", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      let job = plannedJobs[0]
      XCTAssertTrue(job.commandLine.contains(.flag("-no-warnings-as-errors")))
      XCTAssertTrue(job.commandLine.contains(.flag("-suppress-warnings")))
    }

    do {
      XCTAssertThrowsError(try Driver(args: ["swift", "-no-warnings-as-errors", "-warnings-as-errors", "-suppress-warnings", "foo.swift"])) {
        XCTAssertEqual($0 as? Driver.Error, Driver.Error.conflictingOptions(.warningsAsErrors, .suppressWarnings))
      }
    }

    do {
      var driver = try Driver(args: ["swift", "-print-educational-notes", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      let job = plannedJobs[0]
      XCTAssertTrue(job.commandLine.contains(.flag("-print-educational-notes")))
    }
  }

  func testScanDependenciesOption() throws {
    do {
      var driver = try Driver(args: ["swiftc", "-scan-dependencies", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      let job = plannedJobs[0]
      XCTAssertTrue(job.commandLine.contains(.flag("-scan-dependencies")))
    }

    // Test .d output
    do {
      var driver = try Driver(args: ["swiftc", "-scan-dependencies",
                                     "-emit-dependencies", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      let job = plannedJobs[0]
      print("")
      print(job.commandLine)
      XCTAssertTrue(job.commandLine.contains(.flag("-scan-dependencies")))
      XCTAssertTrue(job.commandLine.contains(.flag("-emit-dependencies-path")))
      XCTAssertTrue(job.commandLine.contains(.path(.temporary(RelativePath("foo.d")))))
    }
  }

  func testPCHGeneration() throws {
    do {
      var driver = try Driver(args: ["swiftc", "-typecheck", "-import-objc-header", "TestInputHeader.h", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 2)

      XCTAssertEqual(plannedJobs[0].kind, .generatePCH)
      XCTAssertEqual(plannedJobs[0].inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, .relative(RelativePath("TestInputHeader.h")))
      XCTAssertEqual(plannedJobs[0].inputs[0].type, .objcHeader)
      XCTAssertEqual(plannedJobs[0].outputs.count, 1)
      XCTAssertEqual(plannedJobs[0].outputs[0].file, .temporary(RelativePath("TestInputHeader.pch")))
      XCTAssertEqual(plannedJobs[0].outputs[0].type, .pch)
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-frontend")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-emit-pch")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-o")))
      XCTAssert(plannedJobs[0].commandLine.contains(.path(.temporary(RelativePath("TestInputHeader.pch")))))

      XCTAssertEqual(plannedJobs[1].kind, .compile)
      XCTAssertEqual(plannedJobs[1].inputs.count, 1)
      XCTAssertEqual(plannedJobs[1].inputs[0].file, try VirtualPath(path: "foo.swift"))
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("-import-objc-header")))
      XCTAssert(plannedJobs[1].commandLine.contains(.path(.temporary(RelativePath("TestInputHeader.pch")))))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-typecheck", "-disable-bridging-pch", "-import-objc-header", "TestInputHeader.h", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)

      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertEqual(plannedJobs[0].inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, try VirtualPath(path: "foo.swift"))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-import-objc-header")))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-typecheck", "-index-store-path", "idx", "-import-objc-header", "TestInputHeader.h", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 2)

      XCTAssertEqual(plannedJobs[0].kind, .generatePCH)
      XCTAssertEqual(plannedJobs[0].inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, .relative(RelativePath("TestInputHeader.h")))
      XCTAssertEqual(plannedJobs[0].inputs[0].type, .objcHeader)
      XCTAssertEqual(plannedJobs[0].outputs.count, 1)
      XCTAssertEqual(plannedJobs[0].outputs[0].file, .temporary(RelativePath("TestInputHeader.pch")))
      XCTAssertEqual(plannedJobs[0].outputs[0].type, .pch)
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-frontend")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-emit-pch")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-index-store-path")))
      XCTAssert(plannedJobs[0].commandLine.contains(.path(try VirtualPath(path: "idx"))))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-o")))
      XCTAssert(plannedJobs[0].commandLine.contains(.path(.temporary(RelativePath("TestInputHeader.pch")))))

      XCTAssertEqual(plannedJobs[1].kind, .compile)
      XCTAssertEqual(plannedJobs[1].inputs.count, 1)
      XCTAssertEqual(plannedJobs[1].inputs[0].file, try VirtualPath(path: "foo.swift"))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-typecheck", "-import-objc-header", "TestInputHeader.h", "-pch-output-dir", "/pch", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 2)

      XCTAssertEqual(plannedJobs[0].kind, .generatePCH)
      XCTAssertEqual(plannedJobs[0].inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, .relative(RelativePath("TestInputHeader.h")))
      XCTAssertEqual(plannedJobs[0].inputs[0].type, .objcHeader)
      XCTAssertEqual(plannedJobs[0].outputs.count, 1)
      XCTAssertEqual(plannedJobs[0].outputs[0].file, try VirtualPath(path: "/pch/TestInputHeader.pch"))
      XCTAssertEqual(plannedJobs[0].outputs[0].type, .pch)
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-frontend")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-emit-pch")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-pch-output-dir")))
      XCTAssert(plannedJobs[0].commandLine.contains(.path(try VirtualPath(path: "/pch"))))

      XCTAssertEqual(plannedJobs[1].kind, .compile)
      XCTAssertEqual(plannedJobs[1].inputs.count, 1)
      XCTAssertEqual(plannedJobs[1].inputs[0].file, try VirtualPath(path: "foo.swift"))
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("-pch-disable-validation")))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-c", "-embed-bitcode", "-import-objc-header", "TestInputHeader.h", "-pch-output-dir", "/pch", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)

      XCTAssertEqual(plannedJobs[0].kind, .generatePCH)
      XCTAssertEqual(plannedJobs[0].inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, .relative(RelativePath("TestInputHeader.h")))
      XCTAssertEqual(plannedJobs[0].inputs[0].type, .objcHeader)
      XCTAssertEqual(plannedJobs[0].outputs.count, 1)
      XCTAssertEqual(plannedJobs[0].outputs[0].file, try VirtualPath(path: "/pch/TestInputHeader.pch"))
      XCTAssertEqual(plannedJobs[0].outputs[0].type, .pch)
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-frontend")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-emit-pch")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-pch-output-dir")))
      XCTAssert(plannedJobs[0].commandLine.contains(.path(try VirtualPath(path: "/pch"))))

      XCTAssertEqual(plannedJobs[1].kind, .compile)
      XCTAssertEqual(plannedJobs[1].inputs.count, 1)
      XCTAssertEqual(plannedJobs[1].inputs[0].file, try VirtualPath(path: "foo.swift"))
      XCTAssertEqual(plannedJobs[1].outputs.count, 1)
      XCTAssertEqual(plannedJobs[1].outputs[0].file, .temporary(RelativePath("foo.bc")))

      XCTAssertEqual(plannedJobs[2].kind, .backend)
    }

    do {
      var driver = try Driver(args: ["swiftc", "-typecheck", "-disable-bridging-pch", "-import-objc-header", "TestInputHeader.h", "-pch-output-dir", "/pch", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)

      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertEqual(plannedJobs[0].inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, try VirtualPath(path: "foo.swift"))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-import-objc-header")))
      XCTAssertFalse(plannedJobs[0].commandLine.contains(.flag("-pch-output-dir")))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-typecheck", "-disable-bridging-pch", "-import-objc-header", "TestInputHeader.h", "-pch-output-dir", "/pch", "-whole-module-optimization", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)

      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertEqual(plannedJobs[0].inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, try VirtualPath(path: "foo.swift"))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-import-objc-header")))
      XCTAssertFalse(plannedJobs[0].commandLine.contains(.flag("-pch-output-dir")))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-typecheck", "-import-objc-header", "TestInputHeader.h", "-pch-output-dir", "/pch", "-serialize-diagnostics", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 2)

      XCTAssertEqual(plannedJobs[0].kind, .generatePCH)
      XCTAssertEqual(plannedJobs[0].inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, .relative(RelativePath("TestInputHeader.h")))
      XCTAssertEqual(plannedJobs[0].inputs[0].type, .objcHeader)
      XCTAssertEqual(plannedJobs[0].outputs.count, 2)
      XCTAssertEqual(plannedJobs[0].outputs[0].file, .temporary(RelativePath("TestInputHeader.dia")))
      XCTAssertEqual(plannedJobs[0].outputs[0].type, .diagnostics)
      XCTAssertEqual(plannedJobs[0].outputs[1].file, try VirtualPath(path: "/pch/TestInputHeader.pch"))
      XCTAssertEqual(plannedJobs[0].outputs[1].type, .pch)
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-serialize-diagnostics-path")))
      XCTAssert(plannedJobs[0].commandLine.contains(.path(.temporary(RelativePath("TestInputHeader.dia")))))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-frontend")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-emit-pch")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-pch-output-dir")))
      XCTAssert(plannedJobs[0].commandLine.contains(.path(try VirtualPath(path: "/pch"))))

      XCTAssertEqual(plannedJobs[1].kind, .compile)
      XCTAssertEqual(plannedJobs[1].inputs.count, 1)
      XCTAssertEqual(plannedJobs[1].inputs[0].file, try VirtualPath(path: "foo.swift"))
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("-pch-disable-validation")))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-typecheck", "-import-objc-header", "TestInputHeader.h", "-pch-output-dir", "/pch", "-serialize-diagnostics", "foo.swift", "-emit-module", "-emit-module-path", "/module-path-dir"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)

      XCTAssertEqual(plannedJobs[0].kind, .generatePCH)
      XCTAssertEqual(plannedJobs[0].inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, .relative(RelativePath("TestInputHeader.h")))
      XCTAssertEqual(plannedJobs[0].inputs[0].type, .objcHeader)
      XCTAssertEqual(plannedJobs[0].outputs.count, 2)
      XCTAssertNotNil(plannedJobs[0].outputs[0].file.name.range(of: #"/pch/TestInputHeader-.*.dia"#, options: .regularExpression))
      XCTAssertEqual(plannedJobs[0].outputs[0].type, .diagnostics)
      XCTAssertEqual(plannedJobs[0].outputs[1].file, try VirtualPath(path: "/pch/TestInputHeader.pch"))
      XCTAssertEqual(plannedJobs[0].outputs[1].type, .pch)
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-serialize-diagnostics-path")))
      XCTAssert(plannedJobs[0].commandLine.contains {
        guard case .path(let path) = $0 else { return false }
        return path.name.range(of: #"/pch/TestInputHeader-.*.dia"#, options: .regularExpression) != nil
      })
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-frontend")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-emit-pch")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-pch-output-dir")))
      XCTAssert(plannedJobs[0].commandLine.contains(.path(try VirtualPath(path: "/pch"))))

      XCTAssertEqual(plannedJobs[1].kind, .compile)
      XCTAssertEqual(plannedJobs[1].inputs.count, 1)
      XCTAssertEqual(plannedJobs[1].inputs[0].file, try VirtualPath(path: "foo.swift"))
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("-pch-disable-validation")))

      // FIXME: validate that merge module is correct job and that it has correct inputs and flags
    }

    do {
      var driver = try Driver(args: ["swiftc", "-typecheck", "-import-objc-header", "TestInputHeader.h", "-pch-output-dir", "/pch", "-whole-module-optimization", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 2)

      XCTAssertEqual(plannedJobs[0].kind, .generatePCH)
      XCTAssertEqual(plannedJobs[0].inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, .relative(RelativePath("TestInputHeader.h")))
      XCTAssertEqual(plannedJobs[0].inputs[0].type, .objcHeader)
      XCTAssertEqual(plannedJobs[0].outputs.count, 1)
      XCTAssertEqual(plannedJobs[0].outputs[0].file, try VirtualPath(path: "/pch/TestInputHeader.pch"))
      XCTAssertEqual(plannedJobs[0].outputs[0].type, .pch)
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-frontend")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-emit-pch")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-pch-output-dir")))
      XCTAssert(plannedJobs[0].commandLine.contains(.path(try VirtualPath(path: "/pch"))))

      XCTAssertEqual(plannedJobs[1].kind, .compile)
      XCTAssertEqual(plannedJobs[1].inputs.count, 1)
      XCTAssertEqual(plannedJobs[1].inputs[0].file, try VirtualPath(path: "foo.swift"))
      XCTAssertFalse(plannedJobs[1].commandLine.contains(.flag("-pch-disable-validation")))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-typecheck", "-O", "-import-objc-header", "TestInputHeader.h", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 2)

      XCTAssertEqual(plannedJobs[0].kind, .generatePCH)
      XCTAssertEqual(plannedJobs[0].inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, .relative(RelativePath("TestInputHeader.h")))
      XCTAssertEqual(plannedJobs[0].inputs[0].type, .objcHeader)
      XCTAssertEqual(plannedJobs[0].outputs.count, 1)
      XCTAssertEqual(plannedJobs[0].outputs[0].file, .temporary(RelativePath("TestInputHeader.pch")))
      XCTAssertEqual(plannedJobs[0].outputs[0].type, .pch)
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-O")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-frontend")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-emit-pch")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-o")))
      XCTAssert(plannedJobs[0].commandLine.contains(.path(.temporary(RelativePath("TestInputHeader.pch")))))

      XCTAssertEqual(plannedJobs[1].kind, .compile)
      XCTAssertEqual(plannedJobs[1].inputs.count, 1)
      XCTAssertEqual(plannedJobs[1].inputs[0].file, try VirtualPath(path: "foo.swift"))
    }

    // Immediate mode doesn't generate a pch
    do {
      var driver = try Driver(args: ["swift", "-import-objc-header", "TestInputHeader.h", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      XCTAssertEqual(plannedJobs[0].kind, .interpret)
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-import-objc-header")))
      XCTAssert(plannedJobs[0].commandLine.contains(.path(.relative(RelativePath("TestInputHeader.h")))))
    }
  }

  func testPCMGeneration() throws {
     do {
       var driver = try Driver(args: ["swiftc", "-emit-pcm", "module.modulemap", "-module-name", "Test"])
       let plannedJobs = try driver.planBuild()
       XCTAssertEqual(plannedJobs.count, 1)

       XCTAssertEqual(plannedJobs[0].kind, .generatePCM)
       XCTAssertEqual(plannedJobs[0].inputs.count, 1)
       XCTAssertEqual(plannedJobs[0].inputs[0].file, .relative(RelativePath("module.modulemap")))
       XCTAssertEqual(plannedJobs[0].outputs.count, 1)
       XCTAssertEqual(plannedJobs[0].outputs[0].file, .relative(RelativePath("Test.pcm")))
    }
  }

  func testEmbedBitcode() throws {
    do {
      var driver = try Driver(args: ["swiftc", "-embed-bitcode", "embed-bitcode.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)

      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertEqual(plannedJobs[0].inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, .relative(RelativePath("embed-bitcode.swift")))
      XCTAssertEqual(plannedJobs[0].outputs.count, 1)
      XCTAssertEqual(plannedJobs[0].outputs[0].file, .temporary(RelativePath("embed-bitcode.bc")))

      XCTAssertEqual(plannedJobs[1].kind, .backend)
      XCTAssertEqual(plannedJobs[1].inputs.count, 1)
      XCTAssertEqual(plannedJobs[1].inputs[0].file, .temporary(RelativePath("embed-bitcode.bc")))
      XCTAssertEqual(plannedJobs[1].outputs.count, 1)
      XCTAssertEqual(plannedJobs[1].outputs[0].file, .temporary(RelativePath("embed-bitcode.o")))

      XCTAssertEqual(plannedJobs[2].kind, .link)
      XCTAssertEqual(plannedJobs[2].outputs.count, 1)
      XCTAssertEqual(plannedJobs[2].outputs[0].file, .relative(RelativePath("embed-bitcode")))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-embed-bitcode", "main.swift", "hi.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 5)

      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertEqual(plannedJobs[0].inputs.count, 2)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, .relative(RelativePath("main.swift")))
      XCTAssertEqual(plannedJobs[0].inputs[1].file, .relative(RelativePath("hi.swift")))
      XCTAssertEqual(plannedJobs[0].outputs.count, 1)
      XCTAssertEqual(plannedJobs[0].outputs[0].file, .temporary(RelativePath("main.bc")))

      XCTAssertEqual(plannedJobs[1].kind, .compile)
      XCTAssertEqual(plannedJobs[1].inputs.count, 2)
      XCTAssertEqual(plannedJobs[1].inputs[0].file, .relative(RelativePath("main.swift")))
      XCTAssertEqual(plannedJobs[1].inputs[1].file, .relative(RelativePath("hi.swift")))
      XCTAssertEqual(plannedJobs[1].outputs.count, 1)
      XCTAssertEqual(plannedJobs[1].outputs[0].file, .temporary(RelativePath("hi.bc")))

      XCTAssertEqual(plannedJobs[2].kind, .backend)
      XCTAssertEqual(plannedJobs[2].inputs.count, 1)
      XCTAssertEqual(plannedJobs[2].inputs[0].file, .temporary(RelativePath("main.bc")))
      XCTAssertEqual(plannedJobs[2].outputs.count, 1)
      XCTAssertEqual(plannedJobs[2].outputs[0].file, .temporary(RelativePath("main.o")))

      XCTAssertEqual(plannedJobs[3].kind, .backend)
      XCTAssertEqual(plannedJobs[3].inputs.count, 1)
      XCTAssertEqual(plannedJobs[3].inputs[0].file, .temporary(RelativePath("hi.bc")))
      XCTAssertEqual(plannedJobs[3].outputs.count, 1)
      XCTAssertEqual(plannedJobs[3].outputs[0].file, .temporary(RelativePath("hi.o")))

      XCTAssertEqual(plannedJobs[4].kind, .link)
    }

    do {
      var driver = try Driver(args: ["swiftc", "-embed-bitcode", "-c", "-emit-module", "embed-bitcode.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)

      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertEqual(plannedJobs[0].inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, .relative(RelativePath("embed-bitcode.swift")))
      XCTAssertEqual(plannedJobs[0].outputs.count, 3)
      XCTAssertEqual(plannedJobs[0].outputs[0].file, .temporary(RelativePath("embed-bitcode.bc")))
      XCTAssertEqual(plannedJobs[0].outputs[1].file, .temporary(RelativePath("embed-bitcode.swiftmodule")))
      XCTAssertEqual(plannedJobs[0].outputs[2].file, .temporary(RelativePath("embed-bitcode.swiftdoc")))

      XCTAssertEqual(plannedJobs[1].kind, .backend)
      XCTAssertEqual(plannedJobs[1].inputs.count, 1)
      XCTAssertEqual(plannedJobs[1].inputs[0].file, .temporary(RelativePath("embed-bitcode.bc")))
      XCTAssertEqual(plannedJobs[1].outputs.count, 1)
      XCTAssertEqual(plannedJobs[1].outputs[0].file, .relative(RelativePath("embed-bitcode.o")))

      XCTAssertEqual(plannedJobs[2].kind, .mergeModule)
      XCTAssertEqual(plannedJobs[2].inputs.count, 1)
      XCTAssertEqual(plannedJobs[2].inputs[0].file, .temporary(RelativePath("embed-bitcode.swiftmodule")))
      XCTAssertEqual(plannedJobs[2].outputs.count, 2)
      XCTAssertEqual(plannedJobs[2].outputs[0].file, .relative(RelativePath("main.swiftmodule")))
      XCTAssertEqual(plannedJobs[2].outputs[1].file, .relative(RelativePath("main.swiftdoc")))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-embed-bitcode", "-wmo", "embed-bitcode.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)

      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertEqual(plannedJobs[0].inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, .relative(RelativePath("embed-bitcode.swift")))
      XCTAssertEqual(plannedJobs[0].outputs.count, 1)
      XCTAssertEqual(plannedJobs[0].outputs[0].file, .temporary(RelativePath("main.bc")))

      XCTAssertEqual(plannedJobs[1].kind, .backend)
      XCTAssertEqual(plannedJobs[1].inputs.count, 1)
      XCTAssertEqual(plannedJobs[1].inputs[0].file, .temporary(RelativePath("main.bc")))
      XCTAssertEqual(plannedJobs[1].outputs.count, 1)
      XCTAssertEqual(plannedJobs[1].outputs[0].file, .temporary(RelativePath("main.o")))

      XCTAssertEqual(plannedJobs[2].kind, .link)
      XCTAssertEqual(plannedJobs[2].outputs.count, 1)
      XCTAssertEqual(plannedJobs[2].outputs[0].file, .relative(RelativePath("embed-bitcode")))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-embed-bitcode", "-c", "-parse-as-library", "-emit-module",  "embed-bitcode.swift", "empty.swift", "-module-name", "ABC"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 5)

      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertEqual(plannedJobs[0].outputs.count, 3)
      XCTAssertEqual(plannedJobs[0].outputs[0].file, .temporary(RelativePath("embed-bitcode.bc")))

      XCTAssertEqual(plannedJobs[1].kind, .compile)
      XCTAssertEqual(plannedJobs[1].outputs.count, 3)
      XCTAssertEqual(plannedJobs[1].outputs[0].file, .temporary(RelativePath("empty.bc")))

      XCTAssertEqual(plannedJobs[2].kind, .backend)
      XCTAssertEqual(plannedJobs[2].inputs.count, 1)
      XCTAssertEqual(plannedJobs[2].inputs[0].file, .temporary(RelativePath("embed-bitcode.bc")))
      XCTAssertEqual(plannedJobs[2].outputs.count, 1)
      XCTAssertEqual(plannedJobs[2].outputs[0].file, .relative(RelativePath("embed-bitcode.o")))

      XCTAssertEqual(plannedJobs[3].kind, .backend)
      XCTAssertEqual(plannedJobs[3].inputs.count, 1)
      XCTAssertEqual(plannedJobs[3].inputs[0].file, .temporary(RelativePath("empty.bc")))
      XCTAssertEqual(plannedJobs[3].outputs.count, 1)
      XCTAssertEqual(plannedJobs[3].outputs[0].file, .relative(RelativePath("empty.o")))

      XCTAssertEqual(plannedJobs[4].kind, .mergeModule)
      XCTAssertEqual(plannedJobs[4].inputs.count, 2)
      XCTAssertEqual(plannedJobs[4].inputs[0].file, .temporary(RelativePath("embed-bitcode.swiftmodule")))
      XCTAssertEqual(plannedJobs[4].inputs[1].file, .temporary(RelativePath("empty.swiftmodule")))
      XCTAssertEqual(plannedJobs[4].outputs.count, 2)
      XCTAssertEqual(plannedJobs[4].outputs[0].file, .relative(RelativePath("ABC.swiftmodule")))
      XCTAssertEqual(plannedJobs[4].outputs[1].file, .relative(RelativePath("ABC.swiftdoc")))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-embed-bitcode", "-c", "-parse-as-library", "-emit-module", "-whole-module-optimization", "embed-bitcode.swift", "-parse-stdlib", "-module-name", "Swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 2)

      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertEqual(plannedJobs[0].inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, .relative(RelativePath("embed-bitcode.swift")))
      XCTAssertEqual(plannedJobs[0].outputs.count, 3)
      XCTAssertEqual(plannedJobs[0].outputs[0].file, .temporary(RelativePath("Swift.bc")))

      XCTAssertEqual(plannedJobs[1].kind, .backend)
      XCTAssertEqual(plannedJobs[1].inputs.count, 1)
      XCTAssertEqual(plannedJobs[1].inputs[0].file, .temporary(RelativePath("Swift.bc")))
      XCTAssertEqual(plannedJobs[1].outputs.count, 1)
      XCTAssertEqual(plannedJobs[1].outputs[0].file, .relative(RelativePath("Swift.o")))
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode", "-emit-module", "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode", "-emit-module-path", "a.swiftmodule",  "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode", "-emit-sib", "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode", "-emit-sibgen", "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode", "-emit-sil", "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode", "-emit-silgen", "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode", "-emit-ir", "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode", "-emit-bc", "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode", "-emit-assembly", "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode-marker", "-emit-module", "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode-marker since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode-marker")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode-marker", "-emit-module-path", "a.swiftmodule",  "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode-marker since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode-marker")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode-marker", "-emit-sib", "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode-marker since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode-marker")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode-marker", "-emit-sibgen", "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode-marker since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode-marker")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode-marker", "-emit-sil", "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode-marker since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode-marker")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode-marker", "-emit-silgen", "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode-marker since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode-marker")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode-marker", "-emit-ir", "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode-marker since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode-marker")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode-marker", "-emit-bc", "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode-marker since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode-marker")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode-marker", "-emit-assembly", "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode-marker since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode-marker")))
      }
    }
  }
}

func assertString(
  _ haystack: String, contains needle: String, _ message: String = "",
  file: StaticString = #file, line: UInt = #line
) {
  XCTAssertTrue(haystack.contains(needle), """
                \(String(reflecting: needle)) not found in \
                \(String(reflecting: haystack))\
                \(message.isEmpty ? "" : ": " + message)
                """, file: file, line: line)
}
