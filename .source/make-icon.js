// Draws Claude's icon with a coloured name label, as an .iconset folder (turn it into .icns with iconutil).
// usage: osascript -l JavaScript make-icon.js <source.icns> <out.iconset> <label> <r,g,b>
ObjC.import('AppKit');

function run(argv) {
  var src = $.NSImage.alloc.initWithContentsOfFile(argv[0]);
  if (src.isNil()) throw new Error('cannot read icon ' + argv[0]);
  var outDir = argv[1], label = argv[2];
  var rgb = argv[3].split(',').map(Number);
  $.NSFileManager.defaultManager.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(outDir, true, $(), $());

  var sizes = [[16, '16x16'], [32, '16x16@2x'], [32, '32x32'], [64, '32x32@2x'], [128, '128x128'],
               [256, '128x128@2x'], [256, '256x256'], [512, '256x256@2x'], [512, '512x512'], [1024, '512x512@2x']];
  sizes.forEach(function (s) {
    var px = s[0];
    var rep = $.NSBitmapImageRep.alloc.initWithBitmapDataPlanesPixelsWidePixelsHighBitsPerSampleSamplesPerPixelHasAlphaIsPlanarColorSpaceNameBytesPerRowBitsPerPixel(
      null, px, px, 8, 4, true, false, $.NSCalibratedRGBColorSpace, 0, 0);
    rep.setSize($.NSMakeSize(px, px));
    $.NSGraphicsContext.saveGraphicsState;
    $.NSGraphicsContext.setCurrentContext($.NSGraphicsContext.graphicsContextWithBitmapImageRep(rep));
    src.drawInRectFromRectOperationFraction($.NSMakeRect(0, 0, px, px), $.NSZeroRect, $.NSCompositingOperationSourceOver, 1.0);

    // Label pill near the bottom. It must stay inside the icon's rounded square, or macOS 26
    // puts the whole icon in a grey frame.
    var bh = px * 0.20, bw = px * 0.68, bx = px * 0.16, by = px * 0.15;
    var pill = $.NSBezierPath.bezierPathWithRoundedRectXRadiusYRadius($.NSMakeRect(bx, by, bw, bh), bh / 2, bh / 2);
    $.NSColor.colorWithCalibratedRedGreenBlueAlpha(rgb[0], rgb[1], rgb[2], 1.0).setFill;
    pill.fill;

    // Shrink long names until they fit inside the pill.
    var fontSize = bh * 0.62, attrs, textSize;
    var text = $.NSString.alloc.initWithString(label);
    for (;;) {
      attrs = $.NSDictionary.dictionaryWithObjectsForKeys(
        $([$.NSFont.boldSystemFontOfSize(fontSize), $.NSColor.whiteColor]),
        $([$.NSFontAttributeName, $.NSForegroundColorAttributeName]));
      textSize = text.sizeWithAttributes(attrs);
      if (textSize.width <= bw - bh * 0.6 || fontSize < 2) break;
      fontSize *= 0.92;
    }
    text.drawAtPointWithAttributes($.NSMakePoint(bx + (bw - textSize.width) / 2, by + (bh - textSize.height) / 2), attrs);

    $.NSGraphicsContext.restoreGraphicsState;
    var png = rep.representationUsingTypeProperties($.NSBitmapImageFileTypePNG, $({}));
    if (!png.writeToFileAtomically(outDir + '/icon_' + s[1] + '.png', true)) throw new Error('cannot write ' + outDir);
  });
  return 'ok';
}
