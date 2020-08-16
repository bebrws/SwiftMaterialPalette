//
//  UIImageExtension.swift
//  ImageFun
//
//  Created by Neeraj Kumar on 11/11/14.
//  Copyright (c) 2014 Neeraj Kumar. All rights reserved.
//
//  https://medium.com/hacking-ios/uiimage-pixel-play-extension-in-swift-7c6fe90396b6#.cj2dstgq9
//

import Foundation
import UIKit

private extension UIImage {
    private func createARGBBitmapContext(inImage: CGImage) -> CGContext {
        
        //Get image width, height
        let pixelsWide = inImage.width
        let pixelsHigh = inImage.height
        
        // Declare the number of bytes per row. Each pixel in the bitmap in this
        // example is represented by 4 bytes; 8 bits each of red, green, blue, and
        // alpha.
        let bitmapBytesPerRow = Int(pixelsWide) * 4
        
        // Use the generic RGB color space.
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        // Allocate memory for image data. This is the destination in memory
        // where any drawing to the bitmap context will be rendered.
        
        let bitmapData = malloc(Int(bitmapBytesPerRow * pixelsHigh))
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
        
        // Create the bitmap context. We want pre-multiplied ARGB, 8-bits
        // per component. Regardless of what the source image format is
        // (CMYK, Grayscale, and so on) it will be converted over to the format
        // specified here by CGBitmapContextCreate.
        let context = CGContext(data: bitmapData, width: pixelsWide, height: pixelsHigh, bitsPerComponent: 8, bytesPerRow: bitmapBytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo)
        
        return context!
    }
    
    func sanitizePoint(point:CGPoint) {
        let inImage:CGImage = self.cgImage!
        let pixelsWide = inImage.width
        let pixelsHigh = inImage.height
        let rect = CGRect(x:0, y:0, width:Int(pixelsWide), height:Int(pixelsHigh))
        
        precondition(rect.contains(point), "CGPoint passed is not inside the rect of image.It will give wrong pixel and may crash.")
    }
}


// Internal functions exposed.Can be public.

extension  UIImage {
    typealias RawColorType = (newRedColor:UInt8, newgreenColor:UInt8, newblueColor:UInt8,  newalphaValue:UInt8)
    
    // Defining the closure.
    typealias ModifyPixelsClosure = ( _ point:CGPoint, _ redColor:UInt8, _ greenColor:UInt8, _ blueColor:UInt8, _ alphaValue:UInt8)->(newRedColor:UInt8, newgreenColor:UInt8, newblueColor:UInt8,  newalphaValue:UInt8)
    
    
    // Provide closure which will return new color value for pixel using any condition you want inside the closure.
    
    func applyOnPixels(closure:ModifyPixelsClosure) -> UIImage? {
        let inImage:CGImage = self.cgImage!
        let pixelData = inImage.dataProvider!.data
        let data = CFDataGetBytePtr(pixelData);
        let pixelsWide = inImage.width
        let pixelsHigh = inImage.height

        let bitmapBytesPerRow = Int(pixelsWide) * 4
        
        for x in 0...(pixelsWide-1) {
            for y in 0...(pixelsHigh-1) {
                
                let pixelInfo = ((Int(self.size.width) * y) + x ) * 4;
                
                let red   = data![pixelInfo + 0];
                let green = data![pixelInfo + 1];
                let blue  = data![pixelInfo + 2];
                let alpha = data![pixelInfo + 3];
                
                let (newRedColor, newGreenColor, newBlueColor, newAlphaValue): (UInt8, UInt8, UInt8, UInt8)  =  closure(CGPoint(x: CGFloat(x), y: CGFloat(y)), red, green,  blue, alpha)
            }
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
        
        let ptr = UnsafeMutableRawPointer.init(mutating: data)
        let finalcontext = CGContext(data: ptr, width: pixelsWide, height: pixelsHigh, bitsPerComponent: 8,  bytesPerRow: bitmapBytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo)
        
        let imageRef = finalcontext!.makeImage()
        return UIImage(cgImage: imageRef!, scale: self.scale,orientation: self.imageOrientation)
    }
    
}
