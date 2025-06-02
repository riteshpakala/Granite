//
//  Types.Image.swift
//
//
//  Created by Ritesh Pakala Rao on 6/15/24.
//  Copyright © 2024 Stoic Collective, LLC. All rights reserved.
//

import Foundation

#if os(iOS) || os(visionOS)
import UIKit
public typealias GraniteImage = UIImage

extension GraniteImage {

    convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, scale: 1.0, orientation: .up)
    }

}

#else
import AppKit
public typealias GraniteImage = NSImage

extension GraniteImage {

    var cgImage: CGImage? {
        return self.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    convenience init(cgImage : CGImage) {
        self.init(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

}
#endif
