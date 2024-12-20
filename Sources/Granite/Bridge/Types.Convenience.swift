//
//  Functions._.swift
//
//
//  Created by Ritesh Pakala on 2/26/21.
//  Copyright © 2020 Stoic Collective, LLC. All rights reserved.
//

import Foundation

#if os(iOS)
import UIKit

extension GraniteImage {
    
    convenience init(cgImage : CGImage) {
        self.init(cgImage: cgImage, scale: 1.0, orientation: .up)
    }
    
}

#else
import AppKit

extension GraniteImage {
    
    var cgImage : CGImage? {
        return self.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
    
    convenience init(cgImage : CGImage) {
        self.init(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
    
}
#endif
