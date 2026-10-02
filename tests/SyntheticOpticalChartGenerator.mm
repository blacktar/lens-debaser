#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>

#include <cmath>
#include <filesystem>
#include <string>
#include <vector>

namespace {
constexpr size_t kWidth = 4096;
constexpr size_t kHeight = 2304;
constexpr double kPi = 3.14159265358979323846;

void gray(CGContextRef c, CGFloat value) {
  CGContextSetGrayFillColor(c, value, 1.0);
  CGContextSetGrayStrokeColor(c, value, 1.0);
}

void siemensStar(CGContextRef c, CGFloat cx, CGFloat cy, CGFloat radius,
                 int sectors) {
  CGContextSaveGState(c);
  CGContextAddEllipseInRect(c, CGRectMake(cx-radius, cy-radius,
                                          radius*2, radius*2));
  CGContextClip(c);
  gray(c, 0.035);
  const CGFloat outer = radius * 1.035;
  for (int i=0; i<sectors; i+=2) {
    const double a0 = 2.0*kPi*double(i)/double(sectors);
    const double a1 = 2.0*kPi*double(i+1)/double(sectors);
    CGContextBeginPath(c);
    CGContextMoveToPoint(c, cx, cy);
    CGContextAddLineToPoint(c, cx+std::cos(a0)*outer,
                            cy+std::sin(a0)*outer);
    CGContextAddLineToPoint(c, cx+std::cos(a1)*outer,
                            cy+std::sin(a1)*outer);
    CGContextClosePath(c);
    CGContextFillPath(c);
  }
  CGContextRestoreGState(c);
  gray(c, 0.22);
  CGContextSetLineWidth(c, 3.0);
  CGContextStrokeEllipseInRect(c, CGRectMake(cx-radius, cy-radius,
                                              radius*2, radius*2));
  gray(c, 0.55);
  CGContextFillEllipseInRect(c, CGRectMake(cx-5, cy-5, 10, 10));
}

void linePairPatch(CGContextRef c, CGRect box, int pairs, bool vertical) {
  gray(c, 0.96);
  CGContextFillRect(c, box);
  gray(c, 0.06);
  const int stripes = pairs*2;
  for (int i=0; i<stripes; i+=2) {
    if (vertical) {
      const CGFloat x = box.origin.x + box.size.width*i/stripes;
      CGContextFillRect(c, CGRectMake(x, box.origin.y,
          box.size.width/stripes, box.size.height));
    } else {
      const CGFloat y = box.origin.y + box.size.height*i/stripes;
      CGContextFillRect(c, CGRectMake(box.origin.x, y,
          box.size.width, box.size.height/stripes));
    }
  }
  gray(c, 0.35);
  CGContextSetLineWidth(c, 2.0);
  CGContextStrokeRect(c, box);
}

void slantedEdge(CGContextRef c, CGRect box, CGFloat lean) {
  gray(c, 0.92);
  CGContextFillRect(c, box);
  gray(c, 0.04);
  CGContextBeginPath(c);
  CGContextMoveToPoint(c, box.origin.x, box.origin.y);
  CGContextAddLineToPoint(c, box.origin.x+box.size.width*lean,
                          box.origin.y+box.size.height);
  CGContextAddLineToPoint(c, box.origin.x+box.size.width,
                          box.origin.y+box.size.height);
  CGContextAddLineToPoint(c, box.origin.x+box.size.width, box.origin.y);
  CGContextClosePath(c);
  CGContextFillPath(c);
  gray(c, 0.35);
  CGContextSetLineWidth(c, 2.0);
  CGContextStrokeRect(c, box);
}

void cornerMark(CGContextRef c, CGFloat x, CGFloat y, CGFloat sx, CGFloat sy) {
  gray(c, 0.03);
  CGContextSetLineWidth(c, 9.0);
  CGContextMoveToPoint(c, x, y+sy*90);
  CGContextAddLineToPoint(c, x, y);
  CGContextAddLineToPoint(c, x+sx*90, y);
  CGContextStrokePath(c);
}
}

int main(int argc, char **argv) {
  if (argc != 2) return 2;
  std::filesystem::path output(argv[1]);
  std::filesystem::create_directories(output.parent_path());

  std::vector<uint8_t> rgba(kWidth*kHeight*4, 255);
  CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
  CGContextRef c = CGBitmapContextCreate(
      rgba.data(), kWidth, kHeight, 8, kWidth*4, space,
      CGBitmapInfo(kCGImageAlphaPremultipliedLast)|
      CGBitmapInfo(kCGBitmapByteOrder32Big));
  if (!c) return 3;
  CGContextSetShouldAntialias(c, true);
  CGContextSetAllowsAntialiasing(c, true);
  CGContextSetInterpolationQuality(c, kCGInterpolationHigh);

  gray(c, 0.985);
  CGContextFillRect(c, CGRectMake(0, 0, kWidth, kHeight));

  // An original asymmetric layout: one large centre star, four smaller stars,
  // neutral patches, slanted edges and frequency patches. It deliberately
  // avoids logos, text and the arrangement of any photographed chart.
  siemensStar(c, kWidth*.50, kHeight*.51, 750, 144);
  siemensStar(c, kWidth*.087, kHeight*.846, 280, 96);
  siemensStar(c, kWidth*.913, kHeight*.846, 280, 96);
  siemensStar(c, kWidth*.087, kHeight*.154, 280, 96);
  siemensStar(c, kWidth*.913, kHeight*.154, 280, 96);

  for (int i=0; i<10; ++i) {
    gray(c, CGFloat(i)/9.0);
    CGContextFillRect(c, CGRectMake(1198+i*170, 2090, 170, 115));
  }
  gray(c, 0.3);
  CGContextSetLineWidth(c, 3.0);
  CGContextStrokeRect(c, CGRectMake(1198, 2090, 1700, 115));

  const int pairCounts[] = {3, 5, 8, 12, 18};
  for (int i=0; i<5; ++i) {
    const CGFloat y = 650+i*200;
    linePairPatch(c, CGRectMake(620, y, 140, 105), pairCounts[i], true);
    linePairPatch(c, CGRectMake(795, y, 140, 105), pairCounts[4-i], false);
    linePairPatch(c, CGRectMake(kWidth-935, y, 140, 105), pairCounts[4-i], false);
    linePairPatch(c, CGRectMake(kWidth-760, y, 140, 105), pairCounts[i], true);
  }

  slantedEdge(c, CGRectMake(620, 2120, 280, 135), .42);
  slantedEdge(c, CGRectMake(kWidth-900, 2120, 280, 135), .58);
  slantedEdge(c, CGRectMake(620, 49, 280, 135), .58);
  slantedEdge(c, CGRectMake(kWidth-900, 49, 280, 135), .42);

  gray(c, 0.62);
  CGContextSetLineWidth(c, 2.0);
  CGContextStrokeRect(c, CGRectMake(55, 55, kWidth-110, kHeight-110));
  CGContextSetLineWidth(c, 5.0);
  CGContextMoveToPoint(c, kWidth*.5, 105);
  CGContextAddLineToPoint(c, kWidth*.5, 285);
  CGContextMoveToPoint(c, kWidth*.5, kHeight-105);
  CGContextAddLineToPoint(c, kWidth*.5, kHeight-285);
  CGContextMoveToPoint(c, 105, kHeight*.5);
  CGContextAddLineToPoint(c, 285, kHeight*.5);
  CGContextMoveToPoint(c, kWidth-105, kHeight*.5);
  CGContextAddLineToPoint(c, kWidth-285, kHeight*.5);
  CGContextStrokePath(c);
  cornerMark(c, 35, 35, 1, 1);
  cornerMark(c, kWidth-35, 35, -1, 1);
  cornerMark(c, 35, kHeight-35, 1, -1);
  cornerMark(c, kWidth-35, kHeight-35, -1, -1);

  CGImageRef image = CGBitmapContextCreateImage(c);
  CFURLRef url = CFURLCreateFromFileSystemRepresentation(
      nullptr, reinterpret_cast<const UInt8*>(output.c_str()),
      output.string().size(), false);
  CGImageDestinationRef destination = CGImageDestinationCreateWithURL(
      url, CFSTR("public.png"), 1, nullptr);
  if (destination && image) CGImageDestinationAddImage(destination, image, nullptr);
  const bool ok = destination && CGImageDestinationFinalize(destination);
  if (destination) CFRelease(destination);
  if (url) CFRelease(url);
  if (image) CGImageRelease(image);
  CGContextRelease(c);
  CGColorSpaceRelease(space);
  return ok ? 0 : 4;
}
