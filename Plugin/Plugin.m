/*

The MIT License

Copyright (c) 2008-2009 Click to Flash Developers

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/
#import "Plugin.h"
#import "CTFWhitelistWindowController.h"
#import "NSBezierPath-RoundedRectangle.h"

@interface NSBezierPath(MRGradientFill)
-(void)linearGradientFill:(NSRect)thisRect
               startColor:(NSColor *)startColor
                 endColor:(NSColor *)endColor;
@end

static NSString *sFlashOldMIMEType = @"application/x-shockwave-flash";
static NSString *sFlashNewMIMEType = @"application/futuresplash";
static NSString *sHostWhitelistDefaultsKey = @"ClickToFlash.whitelist";

@interface CTFClickToFlashPlugin (Internal)
- (void) _convertTypesForContainer;
- (void) _drawBackground;
- (BOOL) _isOptionPressed;
- (BOOL) _isHostWhitelisted;
- (NSMutableArray *)_hostWhitelist;
- (void) _addHostToWhitelist;
- (void) _removeHostFromWhitelist;
- (void) _askToAddCurrentSiteToWhitelist;
@end


@implementation CTFClickToFlashPlugin


#pragma mark -
#pragma mark Class Methods

+ (NSView *)plugInViewWithArguments:(NSDictionary *)arguments
{
    return [[[self alloc] initWithArguments:arguments] autorelease];
}


#pragma mark -
#pragma mark Initialization and Superclass Overrides

- (id) initWithArguments:(NSDictionary *)arguments
{
    self = [super init];
    if (self) {
        [self setContainer:[arguments objectForKey:WebPlugInContainingElementKey]];

        NSURL *base = [arguments objectForKey:WebPlugInBaseURLKey];
        if (base) {
			[self setBaseURL:base];
            if ([self _isHostWhitelisted] && ![self _isOptionPressed]) {
                [self performSelector:@selector(_convertTypesForContainer) withObject:nil afterDelay:0];
            }
        }

        if (![NSBundle loadNibNamed:@"ContextualMenu" owner:self])
            NSLog(@"Could not load conextual menu plugin");

        NSDictionary *attributes = [arguments objectForKey:WebPlugInAttributesKey];
        if (attributes != nil) {
            NSString *src = [attributes objectForKey:@"src"];
            if (src)
                [self setToolTip:src];
            else {
                src = [attributes objectForKey:@"data"];
                if (src)
                    [self setToolTip:src];
            }
        }
    }

    return self;
}


- (void) dealloc
{
    [self setContainer:nil];
    [self setBaseURL:nil];
    [_whitelistWindowController release];
    [super dealloc];
}


- (void) drawRect:(NSRect)rect
{
    [self _drawBackground];
}


- (void) mouseDown:(NSEvent *)event
{
    mouseIsDown = YES;
    mouseInside = YES;
    [self setNeedsDisplay:YES];

    // Track the mouse so that we can undo our pressed-in look if the user drags the mouse outside the view, and reinstate it if the user drags it back in.
    trackingArea = [[MATrackingArea alloc] initWithRect:[self bounds]
                                                options:MATrackingMouseEnteredAndExited | MATrackingActiveInKeyWindow | MATrackingEnabledDuringMouseDrag
                                                  owner:self
                                               userInfo:nil];
    [MATrackingArea addTrackingArea:trackingArea toView:self];
}

- (void)mouseEntered:(NSEvent *)event
{
    mouseInside = YES;
    [self setNeedsDisplay:YES];
}
- (void)mouseExited:(NSEvent *)event
{
    mouseInside = NO;
    [self setNeedsDisplay:YES];
}

- (void) mouseUp:(NSEvent *)event
{
    mouseIsDown = NO;
    // Display immediately because we don't want to end up drawing after we've swapped in the Flash movie.
    [self display];

    // We're done tracking.
    [MATrackingArea removeTrackingArea:trackingArea fromView:self];
    [trackingArea release];
    trackingArea = nil;

    if (mouseInside) {
        if ([self _isOptionPressed] && ![self _isHostWhitelisted]) {
            [self _askToAddCurrentSiteToWhitelist];
        } else {
            [self _convertTypesForContainer];
        }
    }
}

- (NSMenu *)menuForEvent:(NSEvent *)theEvent
{
    return [self menu];
}

- (BOOL) _isOptionPressed;
{
    BOOL isOptionPressed = (([[NSApp currentEvent] modifierFlags] & NSAlternateKeyMask) != 0);
    return isOptionPressed;
}

- (void) _askToAddCurrentSiteToWhitelist
{
    NSString *title = NSLocalizedString(@"Always load flash for this site?", @"Always load flash for this site?");
    NSString *message = [NSString stringWithFormat:NSLocalizedString(@"Add %@ to the white list?", @"Add %@ to the white list?"), [[self baseURL] host]];

    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert addButtonWithTitle:NSLocalizedString(@"Add to white list", @"Add to white list")];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"Cancel")];
    [alert setMessageText:title];
    [alert setInformativeText:message];
    [alert setAlertStyle:NSInformationalAlertStyle];
    [alert beginSheetModalForWindow:[self window]
                      modalDelegate:self
                     didEndSelector:@selector(addToWhitelistAlertDidEnd:returnCode:contextInfo:)
                        contextInfo:nil];
}

- (void)addToWhitelistAlertDidEnd:(NSAlert *)alert returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
    if (returnCode == NSAlertFirstButtonReturn)
    {
        [self _addHostToWhitelist];
        [self _convertTypesForContainer];
    }
}

- (BOOL) _isHostWhitelisted
{
    NSArray *hostWhitelist = [[NSUserDefaults standardUserDefaults] stringArrayForKey:sHostWhitelistDefaultsKey];
    return hostWhitelist && [hostWhitelist containsObject:[[self baseURL] host]];
}

- (NSMutableArray *)_hostWhitelist
{
    NSMutableArray *hostWhitelist = [[[[NSUserDefaults standardUserDefaults] stringArrayForKey:sHostWhitelistDefaultsKey] mutableCopy] autorelease];
    if (hostWhitelist == nil) {
        hostWhitelist = [NSMutableArray array];
    }
    return hostWhitelist;
}

- (void) _addHostToWhitelist
{
    NSMutableArray *hostWhitelist = [self _hostWhitelist];
    [hostWhitelist addObject:[[self baseURL] host]];
    [[NSUserDefaults standardUserDefaults] setObject:hostWhitelist forKey:sHostWhitelistDefaultsKey];
}

- (void) _removeHostFromWhitelist
{
    NSMutableArray *hostWhitelist = [self _hostWhitelist];
    [hostWhitelist removeObject:[[self baseURL] host]];
    [[NSUserDefaults standardUserDefaults] setObject:hostWhitelist forKey:sHostWhitelistDefaultsKey];
}

#pragma mark -
#pragma mark Contextual menu

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    BOOL enabled = YES;
    SEL action = [menuItem action];
    if (action == @selector(addToWhitelist:))
    {
        if ([self _isHostWhitelisted])
            enabled = NO;
    }
    else if (action == @selector(removeFromWhitelist:))
    {
        if (![self _isHostWhitelisted])
            enabled = NO;
    }

    return enabled;
}

- (IBAction)addToWhitelist:(id)sender;
{
    if ([self _isHostWhitelisted])
        return;

    if ([self _isOptionPressed])
    {
        [self _addHostToWhitelist];
        [self _convertTypesForContainer];
        return;
    }

    [self _askToAddCurrentSiteToWhitelist];
}

- (IBAction)removeFromWhitelist:(id)sender;
{
    if (![self _isHostWhitelisted])
        return;

    NSString *title = NSLocalizedString(@"Remove from white list?", @"Remove from white list?");
    NSString *message = [NSString stringWithFormat:NSLocalizedString(@"Remove %@ from the white list?", @"Remove %@ from the white list?"), [[self baseURL] host]];

    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert addButtonWithTitle:NSLocalizedString(@"Remove from white list", @"Remove from white list")];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"Cancel")];
    [alert setMessageText:title];
    [alert setInformativeText:message];
    [alert setAlertStyle:NSInformationalAlertStyle];
    [alert beginSheetModalForWindow:[self window]
                      modalDelegate:self
                     didEndSelector:@selector(removeFromWhitelistAlertDidEnd:returnCode:contextInfo:)
                        contextInfo:nil];
}

- (void)removeFromWhitelistAlertDidEnd:(NSAlert *)alert returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
    if (returnCode == NSAlertFirstButtonReturn)
    {
        [self _removeHostFromWhitelist];
    }
}

- (IBAction)editWhitelist:(id)sender;
{
    if (_whitelistWindowController == nil)
    {
        _whitelistWindowController = [[CTFWhitelistWindowController alloc] init];
    }
    [_whitelistWindowController showWindow:self];
}

- (IBAction)copyFlashMovieURLToGeneralPasteboard:(id)sender
{
    NSString *movieURLString = nil;
    NSURL *movieURL = nil;
	
    DOMElement *element = [self container];
    if ([[element tagName] isEqualToString:@"EMBED"])
        movieURLString = [element getAttribute:@"src"];
    else if ([[element tagName] isEqualToString:@"OBJECT"])
        movieURLString = [element getAttribute:@"data"];
	
    if (movieURLString)
        movieURL = [NSURL URLWithString:movieURLString relativeToURL:[self baseURL]];
	
    if (movieURL) {
        NSPasteboard *pboard = [NSPasteboard generalPasteboard];
        [pboard declareTypes:[NSArray arrayWithObject:NSURLPboardType] owner:self];
        [movieURL writeToPasteboard:pboard];
    }
}

- (IBAction)loadFlash:(id)sender;
{
    [self _convertTypesForContainer];
}

#pragma mark -
#pragma mark Drawing
- (void) _drawBadge
{
	// What and how are we going to draw?
	
	const float kFrameXInset = 10;
	const float kFrameYInset =  4;
	const float kMinMargin   = 11.5;
	const float kMinHeight   =  6;
	
	NSString* str = NSLocalizedString( @"Flash", @"Flash" );
	
	NSColor* badgeColor = [ NSColor colorWithCalibratedWhite: 0.0 alpha: 0.25 ];
	
	NSDictionary* attrs = [ NSDictionary dictionaryWithObjectsAndKeys: 
		[ NSFont boldSystemFontOfSize: 20 ], NSFontAttributeName,
		[ NSNumber numberWithInt: -1 ], NSKernAttributeName,
		badgeColor, NSForegroundColorAttributeName,
		nil ];
	
	// Set up for drawing.
	
	NSRect bounds = [ self bounds ];
	
	// How large would this text be?
	
	NSSize strSize = [ str sizeWithAttributes: attrs ];
	
	float w = strSize.width + kFrameXInset * 2;
	float h = strSize.height + kFrameYInset * 2;
	
	// Compute a scale factor based on the view's size.
	
	float maxW = NSWidth( bounds ) - kMinMargin;
	float maxH = NSHeight( bounds ) - kMinMargin;
	
	if( maxW <= kMinHeight * w / h || maxH <= kMinHeight )
		return;    // nothing to draw
	
	float scaleFactor = 1.0;
	
	if( maxW < w )
		scaleFactor = maxW / w;
	
	if( maxH < h && maxH / h < scaleFactor )
		scaleFactor = maxH / h;
	
	// Apply the scale, and a transform so the result is centered in the view.
	
	[ NSGraphicsContext saveGraphicsState ];
	
	NSAffineTransform* xform = [ NSAffineTransform transform ];
	[ xform translateXBy: NSWidth( bounds ) / 2 yBy: NSHeight( bounds ) / 2 ];
	[ xform scaleBy: scaleFactor ];
	[ xform concat ];
	
	// Draw everything at full size, centered on the origin.
	
	NSPoint loc = { -strSize.width / 2, -strSize.height / 2 };
	NSRect borderRect = NSMakeRect( loc.x - kFrameXInset, loc.y - kFrameYInset, w, h );
	
	[ str drawAtPoint: loc withAttributes: attrs ];
	
	NSBezierPath* path = bezierPathWithRoundedRectCornerRadius( borderRect, 4 );
	[ badgeColor set ];
	[ path setLineWidth: 3 ];
	[ path stroke ];
	
	// Now restore the graphics state:
	
	[NSGraphicsContext restoreGraphicsState ];
}

- (void) _drawBackground
{
    NSRect selfBounds  = [self bounds];

    NSRect fillRect   = NSInsetRect(selfBounds, 1.0, 1.0);
    NSRect strokeRect = selfBounds;

    NSColor *startingColor = [NSColor colorWithDeviceWhite:1.0 alpha:0.15];
    NSColor *endingColor = [NSColor colorWithDeviceWhite:0.0 alpha:0.15];

    // When the mouse is up or outside the view, we want a convex look, so we draw the gradient downward (90+180=270 degrees).
    // When the mouse is down and inside the view, we want a concave look, so we draw the gradient upward (90 degrees).
    id gradient = [NSClassFromString(@"NSGradient") alloc];
    if (gradient != nil)
    {
        [gradient initWithStartingColor:startingColor endingColor:endingColor];
        [gradient drawInBezierPath:[NSBezierPath bezierPathWithRect:fillRect] angle:90.0 + ((mouseIsDown && mouseInside) ? 0.0 : 180.0)];
        [gradient release];
    }
    else
    {
		//tweak colors for better compatibility with linearGradientFill
		startingColor = [NSColor colorWithDeviceWhite:0.667 alpha:0.15];
		endingColor = [NSColor colorWithDeviceWhite:0.333 alpha:0.15];
		NSBezierPath *path = [NSBezierPath bezierPath];

        //Draw Gradient
        [path linearGradientFill:fillRect
                      startColor:((mouseIsDown && mouseInside) ? endingColor : startingColor)
                        endColor:((mouseIsDown && mouseInside) ? startingColor : endingColor)];
        [[NSColor colorWithCalibratedWhite:0.0 alpha:0.50] set];
        [path stroke];
    }

    // Draw stroke
    [NSBezierPath setDefaultLineWidth:2.0];
    [NSBezierPath setDefaultLineCapStyle:NSSquareLineCapStyle];
    [[NSBezierPath bezierPathWithRect:strokeRect] stroke];

    // Draw an image on top to make it insanely obvious that this is clickable Flash.
    /*NSString *containerImageName = [[NSBundle bundleForClass:[self class]] pathForResource:@"ContainerImage" ofType:@"png"];
    NSImage *containerImage = [[NSImage alloc] initWithContentsOfFile:containerImageName];

    NSSize viewSize  = fillRect.size;
    NSSize imageSize = [containerImage size];

    NSPoint viewCenter;
    viewCenter.x = viewSize.width  * 0.50;
    viewCenter.y = viewSize.height * 0.50;

    NSPoint imageOrigin = viewCenter;
    imageOrigin.x -= imageSize.width  * 0.50;
    imageOrigin.y -= imageSize.height * 0.50;

    NSRect destinationRect;
    destinationRect.origin = imageOrigin;
    destinationRect.size = imageSize;

    // Draw the image centered in the view
    [containerImage drawInRect:destinationRect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];

    [containerImage release];*/
	
	//Draw a vector badge
	[self _drawBadge];
}


#pragma mark -
#pragma mark DOM Conversion

- (void) _convertTypesForElement:(DOMElement *)element
{
    NSString *type = [element getAttribute:@"type"];

    if ([type isEqualToString:sFlashOldMIMEType] || [type length] == 0) {
        [element setAttribute:@"type" value:sFlashNewMIMEType];
    }
}


- (void) _convertTypesForContainer
{
    DOMElement *newElement = (DOMElement *)[[self container] cloneNode:YES];

    DOMNodeList *nodeList = nil;
    unsigned int i;

    [self _convertTypesForElement:newElement];

    nodeList = [newElement getElementsByTagName:@"object"];
    for (i = 0; i < [nodeList length]; i++) {
        [self _convertTypesForElement:(DOMElement *)[nodeList item:i]];
    }

    nodeList = [newElement getElementsByTagName:@"embed"];
    for (i = 0; i < [nodeList length]; i++) {
        [self _convertTypesForElement:(DOMElement *)[nodeList item:i]];
    }

    // Just to be safe, since we are about to replace our containing element
    [[self retain] autorelease];

    [[[self container] parentNode] replaceChild:newElement oldChild:[self container]];
    [self setContainer:nil];
}


- (DOMElement *) container
{
    return _container;
}

- (void) setContainer:(DOMElement *)newContainer
{
    [_container autorelease];
    _container = [newContainer retain];
}

- (NSURL *) baseURL
{
	return _baseURL;
}

- (void) setBaseURL:(NSURL *)newBaseURL
{
	[_baseURL autorelease];
    _baseURL = [newBaseURL retain];
}
@end


//### globals
float start_red,
start_green,
start_blue,
start_alpha;
float end_red,
end_green,
end_blue,
end_alpha;
float d_red,
d_green,
d_blue,
d_alpha;

@implementation NSBezierPath(MRGradientFill)

static void
evaluate(void *info, const float *in, float *out)
{
    // red
    *out++ = start_red + *in * d_red;

    // green
    *out++ = start_green + *in * d_green;

    // blue
    *out++ = start_blue + *in * d_blue;

    //alpha
    *out++ = start_alpha + *in * d_alpha;
}

float absDiff(float a, float b)
{
    return (a < b) ? b-a : a-b;
}

-(void)linearGradientFill:(NSRect)thisRect
               startColor:(NSColor *)startColor
                 endColor:(NSColor *)endColor
{
    CGColorSpaceRef colorspace = nil;
    CGShadingRef shading;
    static CGPoint startPoint = { 0, 0 };
    static CGPoint endPoint = { 0, 0 };
    int k;
    CGFunctionRef function;
    CGFunctionRef (*getFunction)(CGColorSpaceRef);
    CGShadingRef (*getShading)(CGColorSpaceRef, CGFunctionRef);

    // get my context
    CGContextRef currentContext =
        (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];


    NSColor *s = [startColor colorUsingColorSpaceName:NSDeviceRGBColorSpace];
    NSColor *e = [endColor colorUsingColorSpaceName:NSDeviceRGBColorSpace];

    // set up colors for gradient
    start_red = [s redComponent];
    start_green = [s greenComponent];
    start_blue = [s blueComponent];
    start_alpha = [s alphaComponent];

    end_red = [e redComponent];
    end_green = [e greenComponent];
    end_blue = [e blueComponent];
    end_alpha = [e alphaComponent];

    d_red = absDiff(end_red, start_red);
    d_green = absDiff(end_green, start_green);
    d_blue = absDiff(end_blue, start_blue);
    d_alpha = absDiff(end_alpha ,start_alpha);


    // draw gradient
    colorspace = CGColorSpaceCreateDeviceRGB();

    size_t components;
    static const float domain[2] = { 0.0, 1.0 };
    static const float range[10] = { 0, 1, 0, 1, 0, 1, 0, 1, 0, 1 };
    static const CGFunctionCallbacks callbacks = { 0, &evaluate, NULL };

    components = 1 + CGColorSpaceGetNumberOfComponents(colorspace);
    function = CGFunctionCreate((void *)components, 1, domain, components,
                                range, &callbacks);

    // function = getFunction(colorspace);
    startPoint.x = 0;
    startPoint.y = thisRect.origin.y;
    endPoint.x = 0;
    endPoint.y = NSMaxY(thisRect);


    shading = CGShadingCreateAxial(colorspace,
                                   startPoint, endPoint,
                                   function,
                                   NO, NO);

    CGContextDrawShading(currentContext, shading);

    CGFunctionRelease(function);
    CGShadingRelease(shading);
    CGColorSpaceRelease(colorspace);
}
@end
