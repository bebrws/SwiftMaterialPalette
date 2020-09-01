//
//  ColorCutQuantizer.swift
//  MaterialPalette
//
//  Created by Jonathan Zong on 10/30/15.
//  Copyright (c) 2015 Jonathan Zong. All rights reserved.
//

import Foundation
import UIKit

extension UIColor {
    
    func distanceTo(color: UIColor) -> Double
    {
        
        var otherred: CGFloat = 0.0, othergreen: CGFloat = 0.0, otherblue: CGFloat = 0.0, otheralpha: CGFloat = 0.0
        self.getRed(&otherred, green: &othergreen, blue: &otherblue, alpha: &otheralpha)
        var red: CGFloat = 0.0, green: CGFloat = 0.0, blue: CGFloat = 0.0, alpha: CGFloat = 0.0
        self.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        let rmean = (red + otherred ) / 2;
        let r = red - otherred;
        let g = green - othergreen;
        let b = blue - otherblue;
        let inner1 = Int((512+rmean)*r*r)
        let inner2 = Int(4*g*g)
        let inner3 = Int((767-rmean)*b*b)
        return sqrt(Double((inner1 >> 8) + inner3 + (inner3 >> 8)));
    }
}

class ColorCutQuantizer {
    enum Dimension {
        case COMPONENT_RED
        case COMPONENT_GREEN
        case COMPONENT_BLUE
    }
    
    private static let QUANTIZE_WORD_WIDTH = 5
    private static let QUANTIZE_WORD_MASK = (1 << QUANTIZE_WORD_WIDTH) - 1
    
    var colors: [Int] = []
    var histogram = [Int: Int]()
    var quantizedColors: [Palette.Swatch] = []
    
//    let mFilters: [Palette.Filter]
    
    let tempHsl: [Float] = [0.0, 0.0, 0.0]
    
    /**
    * Constructor.
    *
    * @param pixels histogram representing an image's pixel data
    * @param maxColors The maximum number of colors that should be in the result palette.
    * @param filters Set of filters to use in the quantization stage
    */
    init(bitmap: UIImage, maxColors: Int, distanceWeigthing: Bool, minBrightness: Double, minSaturation: Double) {
        bitmap.applyOnPixels(closure: {
            (point:CGPoint, redColor:UInt8, greenColor:UInt8, blueColor:UInt8, alphaValue:UInt8) -> (UInt8, UInt8, UInt8, UInt8) in
            let quantizedColor = ColorCutQuantizer.quantizeFromRgb888(red: redColor, green: greenColor, blue: blueColor)
            // And update the histogram
            self.histogram[quantizedColor] = (self.histogram[quantizedColor] ?? 0) + 1
            return (UInt8(ColorUtils.getRed(color: quantizedColor)), UInt8(ColorUtils.getGreen(color: quantizedColor)), UInt8(ColorUtils.getBlue(color: quantizedColor)), UInt8(ColorUtils.getAlphaComponent(color: quantizedColor)))
        })
        
        // Now let's count the number of distinct colors
        let distinctColorCount = histogram.count
        
        self.colors = Array(histogram.keys)
        
        var hues: [CGFloat] = []
        // Filter colors here before
        
        var filteredColors: [UIColor] = []
        
        var maxHistoCount = 0
        
        var filteredHistogram: [UIColor: Int] = [:]
        
        self.colors = colors.filter {
            let c = ColorCutQuantizer.approximateToRgb888(color: $0)
            
            let hsb = c.hsb()
            
            let curHue = hsb![0]
            let saturation = hsb![1]
            let brightness = hsb![2]
            
            if (brightness > CGFloat(minBrightness) && saturation > CGFloat(minSaturation)) {
                filteredColors.append(c)
                
                if histogram[$0]! > maxHistoCount {
                    maxHistoCount = histogram[$0]!
                }
                filteredHistogram[c] = histogram[$0]!
                return true
            }
            
            
            self.histogram.removeValue(forKey: $0)
            return false
        }
        
        if distanceWeigthing {
            var maxDistance: CGFloat = 0
            var averageDistance: CGFloat = 0
            var totalDistance: CGFloat = 0
            var distanceCount = 0
            
            var colorToAverageDistance: [UIColor: CGFloat] = [:]
            
            for c in filteredColors {
                var colorCount = 0
                var colorAverageDistance: CGFloat = 0
                for innerc in filteredColors {
                    let xDist = abs(c.XYZ.X - innerc.XYZ.X)
                    let yDist = abs(c.XYZ.Y - innerc.XYZ.Y)
                    let zDist = abs(c.XYZ.Z - innerc.XYZ.Z)
                    let dist = sqrt(xDist * xDist + yDist * yDist + zDist * zDist)
                    totalDistance += dist
                    distanceCount += 1
                    
                    colorAverageDistance += dist
                    colorCount += 1
                    
                    if dist > maxDistance {
                        maxDistance = dist
                    }
                }
                
                colorToAverageDistance[c] = colorAverageDistance / CGFloat(colorCount)
            }
            
            averageDistance = (totalDistance / CGFloat(distanceCount)) * 1/5
            
            
            var colorsToKeep: [UIColor] = []
            self.colors = colors.filter {
                let c = ColorCutQuantizer.approximateToRgb888(color: $0)

                var toKeep: Bool = true
                for ck in colorsToKeep {
                    let xDist = abs(c.XYZ.X - ck.XYZ.X)
                    let yDist = abs(c.XYZ.Y - ck.XYZ.Y)
                    let zDist = abs(c.XYZ.Z - ck.XYZ.Z)
                    let dist = sqrt(xDist * xDist + yDist * yDist + zDist * zDist)
                    
                    if dist < averageDistance {
                        toKeep = false
                        break
                    }
                }
                
                if toKeep {
                    colorsToKeep.append(c)
                    
                    self.histogram[$0]! += (maxHistoCount * Int(colorToAverageDistance[c]! / averageDistance)) * 2 // dividing by averageDistance gives better results than macDistance
                    
                    return true
                }
                
                
                filteredHistogram.removeValue(forKey: c)
                self.histogram.removeValue(forKey: $0)
                return false
            }
        }
  
        if (distinctColorCount <= maxColors) {
            // The image has fewer colors than the maximum requested, so just return the colors
            for (color, count) in histogram {
                self.quantizedColors.append(Palette.Swatch(color: ColorCutQuantizer.approximateToRgb888(color: color), population: count));
            }
        } else {
            // We need use quantization to reduce the number of colors
            self.quantizedColors.append(contentsOf: quantizePixels(maxColors: maxColors))
            // self.quantizedColors.appendContentsOf(quantizePixels(maxColors: maxColors))
        }
    }
    
    private func quantizePixels(maxColors: Int) -> [Palette.Swatch] {
        // Create the priority queue which is sorted by volume descending. This means we always
        // split the largest box in the queue
        var pq = PriorityQueue<Vbox>()
        if colors.count > 1 {
            // To start, offer a box which contains all of the colors
            pq.push(element: Vbox(lowerIndex: 0, upperIndex: colors.count - 1, colors: colors, histogram: histogram))
            
            // Now go through the boxes, splitting them until we have reached maxColors or there are no
            // more boxes to split
            pq = splitBoxes(queue: &pq, maxSize: maxColors)
        
            // Finally, return the average colors of the color boxes
            return generateAverageColors(vboxes: pq)
        } else {
            let emptypq: PriorityQueue<Vbox> = PriorityQueue<Vbox>()
            return generateAverageColors(vboxes: emptypq)
        }
    }
    
    /**
    * Iterate through the {@link java.util.Queue}, popping
    * {@link ColorCutQuantizer.Vbox} objects from the queue
    * and splitting them. Once split, the new box and the remaining box are offered back to the
    * queue.
    *
    * @param queue {@link java.util.PriorityQueue} to poll for boxes
    * @param maxSize Maximum amount of boxes to split
    */
    private func splitBoxes(queue: inout PriorityQueue<Vbox>, maxSize: Int) -> PriorityQueue<Vbox> {
        while (queue.count < maxSize) {
            if let vbox = queue.pop() {
                if (vbox.canSplit()) {
                    // First split the box, and offer the result
                    queue.push(element: vbox.splitBox())
                    
                    // Then offer the box back
                    queue.push(element: vbox)
                } else {
                    return queue
                }
            } else {
                // If we get here then there are no more boxes to split, so return
                return queue
            }
        }
        return queue
    }
    
    private func generateAverageColors(vboxes: PriorityQueue<Vbox>) -> [Palette.Swatch] {
        var colors: [Palette.Swatch] = []
        for vbox in vboxes {
            let swatch = vbox.getAverageColor()
            colors.append(swatch)
        }
        return colors
    }
    
    /**
    * Represents a tightly fitting box around a color space.
    */
    class Vbox : Comparable {
        private var colors: [Int]
        private let histogram: [Int: Int]
        // lower and upper index are inclusive
        private var lowerIndex: Int
        private var upperIndex: Int
        // Population of colors within this box
        private var population: Int
        
        private var minRed: Int, maxRed: Int
        private var minGreen: Int, maxGreen: Int
        private var minBlue: Int, maxBlue: Int
        
        init(lowerIndex: Int, upperIndex: Int, colors: [Int], histogram: [Int: Int]) {
            self.lowerIndex = lowerIndex
            self.upperIndex = upperIndex
            self.colors = colors
            self.histogram = histogram

            population = 0
            minRed = Int.max
            minGreen = Int.max
            minBlue = Int.max
            maxRed = Int.min
            maxGreen = Int.min
            maxBlue = Int.min
            fitBox()
        }
        
        func getVolume() -> Int {
            return (maxRed - minRed + 1) * (maxGreen - minGreen + 1) * (maxBlue - minBlue + 1)
        }
        
        func canSplit() -> Bool {
            return getColorCount() > 1
        }
        
        func getColorCount() -> Int {
            return 1 + upperIndex - lowerIndex
        }
        
        /**
        * Recomputes the boundaries of this box to tightly fit the colors within the box.
        */
        func fitBox() {
            // Reset the min and max to opposite values
            var minRed = Int.max
            var minGreen = Int.max
            var minBlue = Int.max
            var maxRed = Int.min
            var maxGreen = Int.min
            var maxBlue = Int.min
            var count = 0
            
            for i in lowerIndex...upperIndex {
                let color = self.colors[i]
                count += self.histogram[color]!
                
                let r = ColorCutQuantizer.quantizedRed(color: color)
                let g = ColorCutQuantizer.quantizedGreen(color: color)
                let b = ColorCutQuantizer.quantizedBlue(color: color)
                if (r > maxRed) {
                    maxRed = r
                }
                if (r < minRed) {
                    minRed = r
                }
                if (g > maxGreen) {
                    maxGreen = g
                }
                if (g < minGreen) {
                    minGreen = g
                }
                if (b > maxBlue) {
                    maxBlue = b
                }
                if (b < minBlue) {
                    minBlue = b
                }
            }
            
            self.minRed = minRed
            self.maxRed = maxRed
            self.minGreen = minGreen
            self.maxGreen = maxGreen
            self.minBlue = minBlue
            self.maxBlue = maxBlue
            self.population = count
        }
        
        /**
        * Split this color box at the mid-point along it's longest dimension
        *
        * @return the new ColorBox
        */
        func splitBox() -> Vbox {
            assert(canSplit())
        
            // find median along the longest dimension
            let splitPoint = findSplitPoint()
//            let newBox = Vbox(lowerIndex: splitPoint, upperIndex: self.upperIndex, colors: colors, histogram: histogram)
            
            let colorDistanceForVBox = self.lowerIndex - self.upperIndex
            let newBox = Vbox(lowerIndex: min(splitPoint - colorDistanceForVBox/2, self.upperIndex), upperIndex: max(splitPoint + colorDistanceForVBox/2, self.upperIndex), colors: colors, histogram: histogram)
            
            // Now change this box's upperIndex and recompute the color boundaries
            self.upperIndex = splitPoint

            fitBox()
            return newBox
        }
        
        /**
        * @return the dimension which this box is largest in
        */
        func getLongestColorDimension() -> Dimension {
            let redLength = maxRed - minRed
            let greenLength = maxGreen - minGreen
            let blueLength = maxBlue - minBlue
            
            if (redLength >= greenLength && redLength >= blueLength) {
                return Dimension.COMPONENT_RED
            } else if (greenLength >= redLength && greenLength >= blueLength) {
                return Dimension.COMPONENT_GREEN
            } else {
                return Dimension.COMPONENT_BLUE
            }
        }
        
        /**
        * Finds the point within this box's lowerIndex and upperIndex index of where to split.
        *
        * This is calculated by finding the longest color dimension, and then sorting the
        * sub-array based on that dimension value in each color. The colors are then iterated over
        * until a color is found with at least the midpoint of the whole box's dimension midpoint.
        *
        * @return the index of the colors array to split from
        */
        func findSplitPoint() -> Int {
            let longestDimension = getLongestColorDimension()
            
            // We need to sort the colors in this box based on the longest color dimension.
            // As we can't use a Comparator to define the sort logic, we modify each color so that
            // its most significant is the desired dimension
            ColorCutQuantizer.modifySignificantOctet(a: &colors, dimension: longestDimension, lower: lowerIndex, upper: upperIndex)
            
            var newColors: [Int] = []
            // TODO: Should this sort prior to concatenating slices
            if (lowerIndex > 0) { newColors.append(contentsOf: Array(colors[0..<lowerIndex])) }
            newColors.append(contentsOf: colors[lowerIndex...upperIndex].sorted())
            newColors.append(contentsOf: Array(colors[(upperIndex+1)..<colors.count]))
            colors = newColors
            
            // Now revert all of the colors so that they are packed as RGB again
            ColorCutQuantizer.modifySignificantOctet(a: &colors, dimension: longestDimension, lower: lowerIndex, upper: upperIndex)
            
            let midPoint: Int = population / 2
            var count = 0
            for i in lowerIndex...upperIndex {
                count += histogram[colors[i]]!
                if (count >= midPoint) {
                    return i
                }
            }
        
            return lowerIndex;
        }
        
        /**
        * @return the average color of this box.
        */
        func getAverageColor() -> Palette.Swatch {
            var redSum = 0;
            var greenSum = 0;
            var blueSum = 0;
            var totalPopulation = 0;
            
            for i in lowerIndex...upperIndex {
                let color = colors[i]
                let colorPopulation = histogram[color]!
                
                totalPopulation += colorPopulation
                redSum += colorPopulation * ColorCutQuantizer.quantizedRed(color: color)
                greenSum += colorPopulation * ColorCutQuantizer.quantizedGreen(color: color)
                blueSum += colorPopulation * ColorCutQuantizer.quantizedBlue(color: color)
            }
            
            let redMean: Int = Int(round(Float(redSum) / Float(totalPopulation)))
            let greenMean: Int = Int(round(Float(greenSum) / Float(totalPopulation)))
            let blueMean: Int = Int(round(Float(blueSum) / Float(totalPopulation)))
            
            return Palette.Swatch(color: ColorCutQuantizer.approximateToRgb888(r: redMean, g: greenMean, b: blueMean), population: totalPopulation)
        }
    }

    
    /**
    * Quantized a RGB888 value to have a word width of {@value #QUANTIZE_WORD_WIDTH}.
    */
    private static func quantizeFromRgb888(red: UInt8, green: UInt8, blue: UInt8) -> Int {
        let r = modifyWordWidth(value: Int(red), currentWidth: 8, targetWidth: QUANTIZE_WORD_WIDTH)
        let g = modifyWordWidth(value: Int(green), currentWidth: 8, targetWidth: QUANTIZE_WORD_WIDTH)
        let b = modifyWordWidth(value: Int(blue), currentWidth: 8, targetWidth: QUANTIZE_WORD_WIDTH)
        return r << (QUANTIZE_WORD_WIDTH + QUANTIZE_WORD_WIDTH) | g << QUANTIZE_WORD_WIDTH | b
    }
    
    /**
    * Quantized RGB888 values to have a word width of {@value #QUANTIZE_WORD_WIDTH}.
    */
    private static func approximateToRgb888(r: Int, g: Int, b: Int) -> UIColor {
        return UIColor(red: CGFloat(modifyWordWidth(value: r, currentWidth: QUANTIZE_WORD_WIDTH, targetWidth: 8))/255.0,
                       green: CGFloat(modifyWordWidth(value: g, currentWidth: QUANTIZE_WORD_WIDTH, targetWidth: 8))/255.0, blue: CGFloat(modifyWordWidth(value: b, currentWidth: QUANTIZE_WORD_WIDTH, targetWidth: 8))/255.0, alpha: 1.0)
    }
    
    private static func approximateToRgb888(color: Int) -> UIColor {
        return approximateToRgb888(r: quantizedRed(color: color), g: quantizedGreen(color: color), b: quantizedBlue(color: color))
    }
    
    /**
    * @return red component of the quantized color
    */
    private static func quantizedRed(color: Int) -> Int {
        return (color >> (QUANTIZE_WORD_WIDTH + QUANTIZE_WORD_WIDTH)) & QUANTIZE_WORD_MASK
    }
    
    /**
    * @return green component of a quantized color
    */
    private static func quantizedGreen(color: Int) -> Int {
        return (color >> QUANTIZE_WORD_WIDTH) & QUANTIZE_WORD_MASK
    }
    
    /**
    * @return blue component of a quantized color
    */
    private static func quantizedBlue(color: Int) -> Int {
        return color & QUANTIZE_WORD_MASK
    }
    
    /**
    * Modify the significant octet in a packed color int. Allows sorting based on the value of a
    * single color component. This relies on all components being the same word size.
    *
    * @see Vbox#findSplitPoint()
    */
    private static func modifySignificantOctet(a: inout [Int], dimension: Dimension, lower: Int, upper: Int) {
        switch (dimension) {
            case Dimension.COMPONENT_RED:
            // Already in RGB, no need to do anything
            break;
            case Dimension.COMPONENT_GREEN:
            // We need to do a RGB to GRB swap, or vice-versa
            
            for i in lower...upper {
                let color = a[i]
                a[i] = quantizedGreen(color: color) << (QUANTIZE_WORD_WIDTH + QUANTIZE_WORD_WIDTH)
                    | quantizedRed(color: color) << QUANTIZE_WORD_WIDTH
                    | quantizedBlue(color: color)
            }
            break;
            case Dimension.COMPONENT_BLUE:
            // We need to do a RGB to BGR swap, or vice-versa
            
            for i in lower...upper {
                let color = a[i]
                a[i] = quantizedBlue(color: color) << (QUANTIZE_WORD_WIDTH + QUANTIZE_WORD_WIDTH)
                    | quantizedGreen(color: color) << QUANTIZE_WORD_WIDTH
                    | quantizedRed(color: color);
            }
            break;
        }
    }
    
    private static func modifyWordWidth(value: Int, currentWidth: Int, targetWidth: Int) -> Int {
        let newValue = targetWidth > currentWidth ?
            // If we're approximating up in word width, we'll shift up
            value << (targetWidth - currentWidth) :
            // Else, we will just shift and keep the MSB
            value >> (currentWidth - targetWidth)
        return newValue & ((1 << targetWidth) - 1)
    }
}

/**
* Comparator which sorts {@link Vbox} instances based on their volume, in descending order (largest first)
*/
func < (lhs: ColorCutQuantizer.Vbox, rhs: ColorCutQuantizer.Vbox) -> Bool {
    return rhs.getVolume() - lhs.getVolume() > 0
}

func == (lhs: ColorCutQuantizer.Vbox, rhs: ColorCutQuantizer.Vbox) -> Bool {
    return rhs.getVolume() - lhs.getVolume() == 0
}

extension CGImage {
    func getPixelColor(pos: CGPoint) -> UIColor {
        
        let pixelData = CFDataGetBytePtr(self.dataProvider!.data)
        let data: UnsafePointer<UInt8> = CFDataGetBytePtr(pixelData as! CFData)
        
        let pixelInfo: Int = ((self.width * Int(pos.y)) + Int(pos.x)) * 4
        
        let r = CGFloat(data[pixelInfo]) / CGFloat(255.0)
        let g = CGFloat(data[pixelInfo+1]) / CGFloat(255.0)
        let b = CGFloat(data[pixelInfo+2]) / CGFloat(255.0)
        let a = CGFloat(data[pixelInfo+3]) / CGFloat(255.0)
        
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
}

// https://gist.github.com/adamgraham/677c0c41901f3eafb441951de9bc914c
//
/// An extension to provide conversion to and from CIE 1931 XYZ colors.
extension UIColor {

    /// The CIE 1931 XYZ components of a color - luminance (Y) and chromaticity (X,Z).
    struct CIEXYZ: Hashable {

        /// A mix of cone response curves chosen to be orthogonal to luminance and
        /// non-negative, in the range [0, 95.047].
        var X: CGFloat
        /// The luminance component of the color, in the range [0, 100].
        var Y: CGFloat
        /// Somewhat equal to blue, or the "S" cone response, in the range [0, 108.883].
        var Z: CGFloat

    }

    /// The CIE 1931 XYZ components of the color.
    var XYZ: CIEXYZ {
        var (r, g, b) = (CGFloat(), CGFloat(), CGFloat())
        getRed(&r, green: &g, blue: &b, alpha: nil)
        
        // sRGB (D65) gamma correction - inverse companding to get linear values
        r = (r > 0.03928) ? pow((r + 0.055) / 1.055, 2.4) : (r / 12.92)
        g = (g > 0.03928) ? pow((g + 0.055) / 1.055, 2.4) : (g / 12.92)
        b = (b > 0.03928) ? pow((b + 0.055) / 1.055, 2.4) : (b / 12.92)

        // sRGB (D65) matrix transformation
        // http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
        let X = (0.4124564 * r) + (0.3575761 * g) + (0.1804375 * b)
        let Y = (0.2126729 * r) + (0.7151522 * g) + (0.0721750 * b)
        let Z = (0.0193339 * r) + (0.1191920 * g) + (0.9503041 * b)

        return CIEXYZ(X: X * 100.0,
                      Y: Y * 100.0,
                      Z: Z * 100.0)
    }

    /// Initializes a color from CIE 1931 XYZ components.
    /// - parameter XYZ: The components used to initialize the color.
    /// - parameter alpha: The alpha value of the color.
    convenience init(_ XYZ: CIEXYZ, alpha: CGFloat = 1.0) {
        let X = XYZ.X / 100.0
        let Y = XYZ.Y / 100.0
        let Z = XYZ.Z / 100.0

        // sRGB (D65) matrix transformation
        // http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
        var r =  (3.2404542 * X) - (1.5371385 * Y) - (0.4985314 * Z)
        var g = (-0.9692660 * X) + (1.8760108 * Y) + (0.0415560 * Z)
        var b =  (0.0556434 * X) - (0.2040259 * Y) + (1.0572252 * Z)
        
        // sRGB (D65) gamma correction - companding to get non-linear values
        let k: CGFloat = 1.0 / 2.4
        r = (r <= 0.00304) ? (12.92 * r) : (1.055 * pow(r, k) - 0.055)
        g = (g <= 0.00304) ? (12.92 * g) : (1.055 * pow(g, k) - 0.055)
        b = (b <= 0.00304) ? (12.92 * b) : (1.055 * pow(b, k) - 0.055)
        
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }

}

