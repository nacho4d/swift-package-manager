/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import Utility
import TestSupport
import PackageModel
import PackageLoading

// FIXME: We should share the infra with other loading tests.
class PackageDescription4_2LoadingTests: XCTestCase {
    let manifestLoader = ManifestLoader(resources: Resources.default)

    private func loadManifestThrowing(
        _ contents: ByteString,
        line: UInt = #line,
        body: (Manifest) -> Void
    ) throws {
        let fs = InMemoryFileSystem()
        let manifestPath = AbsolutePath.root.appending(component: Manifest.filename)
        try fs.writeFileContents(manifestPath, bytes: contents)
        let m = try manifestLoader.load(
            package: AbsolutePath.root,
            baseURL: AbsolutePath.root.asString,
            manifestVersion: .v4_2,
            fileSystem: fs)
        guard m.manifestVersion == .v4_2 else {
            return XCTFail("Invalid manfiest version")
        }
        body(m)
    }

    private func loadManifest(
        _ contents: ByteString,
        line: UInt = #line,
        body: (Manifest) -> Void
    ) {
        do {
            try loadManifestThrowing(contents, line: line, body: body)
        } catch ManifestParseError.invalidManifestFormat(let error) {
            print(error)
            XCTFail(file: #file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: #file, line: line)
        }
    }

    func testBasics() {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
                name: "Trivial",
                products: [
                    .executable(name: "tool", targets: ["tool"]),
                    .library(name: "Foo", targets: ["Foo"]),
                ],
                dependencies: [
                    .package(url: "/foo1", from: "1.0.0"),
                ],
                targets: [
                    .target(
                        name: "foo",
                        dependencies: ["dep1", .product(name: "product"), .target(name: "target")]),
                    .testTarget(
                        name: "bar",
                        dependencies: ["foo"]),
                ]
            )
            """

        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(manifest.name, "Trivial")

            // Check targets.
            let targets = Dictionary(items:
                manifest.targets.map({ ($0.name, $0 as TargetDescription ) }))
            let foo = targets["foo"]!
            XCTAssertEqual(foo.name, "foo")
            XCTAssertFalse(foo.isTest)
            XCTAssertEqual(foo.dependencies, ["dep1", .product(name: "product"), .target(name: "target")])

            let bar = targets["bar"]!
            XCTAssertEqual(bar.name, "bar")
            XCTAssertTrue(bar.isTest)
            XCTAssertEqual(bar.dependencies, ["foo"])

            // Check dependencies.
            let deps = Dictionary(items: manifest.dependencies.map{ ($0.url, $0) })
            XCTAssertEqual(deps["/foo1"], PackageDependencyDescription(url: "/foo1", requirement: .upToNextMajor(from: "1.0.0")))

            // Check products.
            let products = Dictionary(items: manifest.products.map{ ($0.name, $0) })

            let tool = products["tool"]!
            XCTAssertEqual(tool.name, "tool")
            XCTAssertEqual(tool.targets, ["tool"])
            XCTAssertEqual(tool.type, .executable)

            let fooProduct = products["Foo"]!
            XCTAssertEqual(fooProduct.name, "Foo")
            XCTAssertEqual(fooProduct.type, .library(.automatic))
            XCTAssertEqual(fooProduct.targets, ["Foo"])
        }
    }

    func testSwiftLanguageVersions() throws {
        // Ensure integer values are not accepted.
        var stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               swiftLanguageVersions: [3, 4]
            )
            """

        do {
            try loadManifestThrowing(stream.bytes) { _ in }
            XCTFail()
        } catch {
            guard case let ManifestParseError.invalidManifestFormat(output) = error else {
                return XCTFail()
            }
            XCTAssertMatch(output, .and(.contains("expected element type"), .contains("SwiftVersion")))
        }

        // Check when Swift language versions is empty.
        stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               swiftLanguageVersions: []
            )
            """
        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(manifest.swiftLanguageVersions, [])
        }

        stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               swiftLanguageVersions: [.v3, .v4, .v4_2, .version("5")]
            )
            """
        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(
                manifest.swiftLanguageVersions,
                [.v3, .v4, .v4_2, SwiftLanguageVersion(string: "5")!]
            )
        }
    }

    func testPackageDependencies() throws {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               dependencies: [
                   .package(url: "/foo1", from: "1.0.0"),
                   .package(url: "/foo2", .revision("58e9de4e7b79e67c72a46e164158e3542e570ab6")),
                   .package(path: "../foo3"),
                   .package(path: "/path/to/foo4"),
                   .package(url: "/foo5", .exact("1.2.3")),
                   .package(url: "/foo6", "1.2.3"..<"2.0.0"),
                   .package(url: "/foo7", .branch("master")),
                   .package(url: "/foo8", .upToNextMinor(from: "1.3.4")),
                   .package(url: "/foo9", .upToNextMajor(from: "1.3.4")),
               ]
            )
            """
       loadManifest(stream.bytes) { manifest in
            let deps = Dictionary(items: manifest.dependencies.map{ ($0.url, $0) })
            XCTAssertEqual(deps["/foo1"], PackageDependencyDescription(url: "/foo1", requirement: .upToNextMajor(from: "1.0.0")))
            XCTAssertEqual(deps["/foo2"], PackageDependencyDescription(url: "/foo2", requirement: .revision("58e9de4e7b79e67c72a46e164158e3542e570ab6")))

            XCTAssertEqual(deps["/foo3"]?.url, "/foo3")
            XCTAssertEqual(deps["/foo3"]?.requirement, .localPackage)

            XCTAssertEqual(deps["/path/to/foo4"]?.url, "/path/to/foo4")
            XCTAssertEqual(deps["/path/to/foo4"]?.requirement, .localPackage)

            XCTAssertEqual(deps["/foo5"], PackageDependencyDescription(url: "/foo5", requirement: .exact("1.2.3")))
            XCTAssertEqual(deps["/foo6"], PackageDependencyDescription(url: "/foo6", requirement: .range("1.2.3"..<"2.0.0")))
            XCTAssertEqual(deps["/foo7"], PackageDependencyDescription(url: "/foo7", requirement: .branch("master")))
            XCTAssertEqual(deps["/foo8"], PackageDependencyDescription(url: "/foo8", requirement: .upToNextMinor(from: "1.3.4")))
            XCTAssertEqual(deps["/foo9"], PackageDependencyDescription(url: "/foo9", requirement: .upToNextMajor(from: "1.3.4")))
        }
    }

    func testSystemLibraryTargets() throws {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
                targets: [
                    .target(
                        name: "foo",
                        dependencies: ["bar"]),
                    .systemLibrary(
                        name: "bar",
                        pkgConfig: "libbar",
                        providers: [
                            .brew(["libgit"]),
                            .apt(["a", "b"]),
                        ]),
                ]
            )
            """
       loadManifest(stream.bytes) { manifest in
            let targets = Dictionary(items:
                manifest.targets.map({ ($0.name, $0 as TargetDescription ) }))
            let foo = targets["foo"]!
            XCTAssertEqual(foo.name, "foo")
            XCTAssertFalse(foo.isTest)
            XCTAssertEqual(foo.type, .regular)
            XCTAssertEqual(foo.dependencies, ["bar"])

            let bar = targets["bar"]!
            XCTAssertEqual(bar.name, "bar")
            XCTAssertEqual(bar.type, .system)
            XCTAssertEqual(bar.pkgConfig, "libbar")
            XCTAssertEqual(bar.providers, [.brew(["libgit"]), .apt(["a", "b"])])
        }
    }

    static var allTests = [
        ("testBasics", testBasics),
        ("testSwiftLanguageVersions", testSwiftLanguageVersions),
        ("testPackageDependencies", testPackageDependencies),
        ("testSystemLibraryTargets", testSystemLibraryTargets),
    ]
}
