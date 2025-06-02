//
//  PipelineRuntimeError.swift
//
//
//  Created by Ritesh Pakala Rao on 6/15/24.
//  Copyright © 2024 Stoic Collective, LLC. All rights reserved.
//

import Foundation

public enum PipelineRuntimeError: Error {
    case emptyResult(Executable)
    case typeMismatch(Executable, Any, Any)
    case genericError(Executable, Any)
    case missingContext(Executable)

    public var description: String {
        switch self {
        case .missingContext(let handler):
            return "PipelineRuntimeError: missing graphics context in \(handler.label)"

        case .genericError(let handler, let message):
            return "PipelineRuntimeError: \(message) in \(handler.label)"

        case .emptyResult(let handler):
            return "PipelineRuntimeError: empty result in \(handler.label)"

        case .typeMismatch(let handler, let gotType, let expectedType):
            return "PipelineRuntimeError: type mismatch in \(handler.label), expected \(expectedType), got \(gotType)"

        }
    }
}
