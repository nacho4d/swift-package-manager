/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageModel
import Utility

enum DescribeMode: String {
    /// JSON format.
    case json

    /// Human readable format.
    case text
}

func describe(_ package: Package, in mode: DescribeMode, on stream: OutputByteStream) {
    switch mode {
    case .json:
        // FIXME: Pretty print support would be nice.
        stream <<< package.toJSON().toString() <<< "\n"
    case .text:
        package.describe(on: stream)
    }
    stream.flush()
}

extension Package: JSONSerializable {

    func describe(on stream: OutputByteStream) {
        stream <<< "Name: " <<< name <<< "\n"
        stream <<< "Path: " <<< path.asString <<< "\n"
        stream <<< "Modules: " <<< "\n"
        for module in modules + testModules {
            module.describe(on: stream, indent: 4)
            stream <<< "\n"
        }
    }

    public func toJSON() -> JSON {
        return .dictionary([
            "name": .string(name),
            "path": .string(path.asString),
            "modules": .array((modules + testModules).map{ $0.toJSON() }),
        ])
    }
}

extension Module: JSONSerializable {

    func describe(on stream: OutputByteStream, indent: Int = 0) {
        stream <<< " ".repeating(n: indent) <<< "Name: " <<< name <<< "\n"
        stream <<< " ".repeating(n: indent) <<< "C99name: " <<< c99name <<< "\n"
        stream <<< " ".repeating(n: indent) <<< "Test module: " <<< isTest.description <<< "\n"
        stream <<< " ".repeating(n: indent) <<< "Type: " <<< type.rawValue <<< "\n"
        stream <<< " ".repeating(n: indent) <<< "Module type: " <<< String(describing: type(of: self)) <<< "\n"
        stream <<< " ".repeating(n: indent) <<< "Path: " <<< sources.root.asString <<< "\n"
        stream <<< " ".repeating(n: indent) <<< "Sources: " <<< sources.relativePaths.map{$0.asString}.joined(separator: ", ") <<< "\n"
    }

    public func toJSON() -> JSON {
        return .dictionary([
            "name": .string(name),
            "c99name": .string(c99name),
            "is_test": .bool(isTest),
            "type": type.toJSON(),
            "module_type": .string(String(describing: type(of: self))),
            "path": .string(sources.root.asString),
            "sources": sources.toJSON(),
        ])
    }
}

extension Sources: JSONSerializable {
    public func toJSON() -> JSON {
        return .array(relativePaths.map{.string($0.asString)})
    }
}

extension ModuleType: JSONSerializable {
    public func toJSON() -> JSON {
        return .string(rawValue)
    }
}
