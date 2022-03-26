/*
 * Copyright (C) 2022 Zoe Knox <zoe@pixin.net>
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#import <AppKit/AppKit.h>
#import "desktop.h"

@implementation MenuView
- init {
    NSRect frame = [[NSScreen mainScreen] visibleFrame];

    self = [super initWithFrame:NSMakeRect(0, 0, frame.size.width/2, menuBarHeight)];
    NSString *ravyn = [[NSBundle mainBundle] pathForResource:@"ravynos-mark-64" ofType:@"png"];
    NSImage *logo = [[NSImage alloc] initWithContentsOfFile:ravyn];
    logoView = [[NSImageView alloc] initWithFrame:NSMakeRect(menuBarHPad,menuBarVPad,16,16)];
    [logoView setImage:logo];
    [self addSubview:logoView];

    NSRect bounds = [self bounds];
    NSFontManager *fontmgr = [NSFontManager sharedFontManager];
    NSDictionary *attributes = [NSDictionary dictionaryWithObject:[fontmgr convertFont:
        [NSFont systemFontOfSize:14] toHaveTrait:NSBoldFontMask] forKey:NSFontAttributeName];

    NSAttributedString *title = [[NSAttributedString alloc] initWithString:@"アプリケーション" attributes:attributes];
    NSSize size = [title size];
    NSPopUpButton *b = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(menuBarHPad*3,
        menuBarVPad, size.width + menuBarHPad, menuBarHeight - menuBarVPad) pullsDown:YES];
    NSMenu *appmenu = [[NSMenu alloc] initWithTitle:[title string]];
    [b setMenu:appmenu];
    [b addItemWithTitle:[appmenu title]];
    [b setAttributedTitle:title];
    [b setBordered:NO];
    [b setBezeled:NO];
    [[b cell] setArrowPosition:NSPopUpNoArrow];
    [self addSubview:b];

    [self setNeedsDisplay:YES];
    return self;
}

@end

