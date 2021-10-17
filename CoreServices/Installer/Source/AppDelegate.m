/*
 * Copyright (C) 2021 Zoe Knox <zoe@pixin.net>
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

#import "AppDelegate.h"
#import "GSGeomDisk.h"

@interface AppDelegate ()
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [_mainWindow setBackgroundColor:[NSColor textBackgroundColor]];

    [_scrollView setAutoresizesSubviews:YES];
    NSBundle *myBundle = [NSBundle mainBundle];
    NSData *rtf = [NSData dataWithContentsOfFile:[myBundle pathForResource:@"terms" ofType:@"rtf"]];
    NSAttributedString *text = [[NSAttributedString alloc] initWithRTF:rtf documentAttributes:nil];

    NSTextView *content = [[_scrollView contentView] documentView];
    [[content textStorage] setAttributedString:text];
    [content setSelectable:NO];
    [content setEditable:NO];

    rtf = [NSData dataWithContentsOfFile:[myBundle pathForResource:@"header" ofType:@"rtf"]];
    text = [[NSAttributedString alloc] initWithRTF:rtf documentAttributes:nil];
    content = [[_instructionsView contentView] documentView];
    [[content textStorage] setAttributedString:text];
    [content setSelectable:NO];
    [content setEditable:NO];

    [_ProceedButton setAction:@selector(proceedToUserInfo:)];
    [_ProceedButton performClick:nil];
}

- (IBAction)proceedToDiskList:(id)sender {
    if(discoverGEOMs(YES) == NO) {
        NSLog(@"error discovering devices!");
        // FIXME: do error sheet
    }

    NSFont *font = [NSFont systemFontOfSize:12.0];
    font = [[NSFontManager sharedFontManager] convertFont:font
        toNotHaveTrait:NSItalicFontMask];
    NSMutableDictionary *attr = [NSMutableDictionary
        dictionaryWithObjects:@[font, [NSColor blackColor]]
        forKeys:@[NSFontAttributeName, NSForegroundColorAttributeName]];

    NSTextStorage *textStorage = [[[_instructionsView contentView]
        documentView] textStorage];
    [textStorage setAttributedString:[[NSAttributedString alloc]
        initWithString:@"\nSelect where airyxOS should be installed.\n\n" // FIXME: localize
        attributes:attr]];

    [attr setObject:[NSColor redColor] forKey:NSForegroundColorAttributeName];
    font = [[NSFontManager sharedFontManager] convertFont:font
        toHaveTrait:NSBoldFontMask];
    [attr setObject:font forKey:NSFontAttributeName];

    [textStorage appendAttributedString:[[NSAttributedString alloc]
        initWithString:@"WARNING! Everything on the selected disk will be erased." // FIXME: localize
        attributes:attr]];

    NSTableView *table = [[NSTableView alloc]
        initWithFrame:[[_scrollView contentView] frame]];
    [table setAllowsColumnReordering:NO];
    [table setDelegate:self];
    [table setDataSource:[GSGeomDisk new]];

    NSArray *columnIDs = @[@"device",@"size",@"descr"];
    NSArray *headerLabels = @[@"Device",@"Size",@"Description"]; // FIXME: localize
    for(int x = 0; x < 3; ++x) {
        NSTableColumn *col = [NSTableColumn new];
        [col setIdentifier:[columnIDs objectAtIndex:x]];
        [col setMinWidth:10.0];
        [col setMaxWidth:MAXFLOAT];
        [col setWidth:100.0];
        [col setHeaderCell:[[NSTableHeaderCell alloc]
            initTextCell:[headerLabels objectAtIndex:x]]];
        [col setDataCell:[[NSTextFieldCell alloc] initTextCell:@""]];
        [table addTableColumn:col];
    }

    NSClipView *clip = [NSClipView new];
    [clip setDocumentView:table];
    [table sizeLastColumnToFit];

    [_scrollView setContentView:clip];
    [_scrollView setAutohidesScrollers:YES];

    [_CancelButton setHidden:YES];
    [_ProceedButton setEnabled:NO];

    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(deviceSelected:)
        name:NSTableViewSelectionDidChangeNotification
        object:table];
    [_ProceedButton setAction:@selector(proceedToUserInfo:)]; // FIXME: do confirmation sheet
}

- (IBAction)proceedToUserInfo:(id)sender {
    NSFont *font = [NSFont systemFontOfSize:12.0];
    font = [[NSFontManager sharedFontManager] convertFont:font
        toNotHaveTrait:NSItalicFontMask];
    NSMutableDictionary *attr = [NSMutableDictionary
        dictionaryWithObjects:@[font, [NSColor blackColor]]
        forKeys:@[NSFontAttributeName, NSForegroundColorAttributeName]];

    NSTextStorage *textStorage = [[[_instructionsView contentView]
        documentView] textStorage];
    [textStorage setAttributedString:[[NSAttributedString alloc]
        initWithString:@"\nEnter the information below to finish setting "
        "up your new system.\nAll fields are required.\n\n" // FIXME: localize
        attributes:attr]];

    [_timeZones removeAllItems];
    [_timeZones setTitle:@"select a zone"];
    [_timeZones addItemWithTitle:@"zone one"];
    [_timeZones addItemWithTitle:@"zone two"];

    [_scrollView setAutohidesScrollers:YES];
    [[_scrollView contentView] removeFromSuperview];
    [_scrollView setContentView:_userInfoView];
    [_ProceedButton setAction:@selector(validateUserInfo:)];
}

- (IBAction)validateUserInfo:(id)sender {
    NSLog(@"validating user info");
    NSLog(@"menu is %@, selected %@", [_timeZones menu],[_timeZones selectedItem]);
    NSLog(@"name is %@", [_fullName stringValue]);
    [_ProceedButton setAction:@selector(proceedToFinalize:)];
}

- (IBAction)proceedToFinalize:(id)sender {
    NSLog(@"finalizing");
}

- (void)deviceSelected:(NSNotification *)aNotification {
    [_ProceedButton setEnabled:YES];
    selectedDisk = [[[aNotification object] selectedRowIndexes] firstIndex];
}

- (IBAction)proceedToPartition:(id)sender {
    [_ProceedButton setEnabled:NO];

    NSTextView *v = [[NSTextView alloc] initWithFrame:[[_scrollView contentView] frame]];
#ifdef __AIRYX__
    [[[_scrollView contentView] documentView] release];
    [[_scrollView contentView] release];
#endif

    NSClipView *clip = [NSClipView new];
    [clip setDocumentView:v];

    [_scrollView setContentView:clip];
    [_scrollView setAutohidesScrollers:YES];

    GSGeomDisk *disk = [disks objectAtIndex:selectedDisk];
    [disk setDelegate:self];

#ifdef __AIRYX__
    [self appendInstallLog:[NSString
        stringWithFormat:@"Clearing disk %@\n", [disk name]]];
    [disk createGPT];
    [self appendInstallLog:@"Creating partitions\n"];
    [disk createPartitions];
    [self appendInstallLog:@"Creating volumes\n"];
    [disk createPools];
    [self appendInstallLog:@"Installing EFI loader\n"];
    [disk initializeEFI];

    [self appendInstallLog:@"Installing files\n"];
    [disk copyFilesystem];
#endif

    [_ProceedButton setEnabled:YES];
    [_ProceedButton setAction:@selector(proceedToUserInfo:)];
    [_ProceedButton performClick:nil];
}

- (void)appendInstallLog:(NSString *)text {
    NSFont *font = [NSFont systemFontOfSize:12.0];
    font = [[NSFontManager sharedFontManager] convertFont:font
        toNotHaveTrait:NSItalicFontMask];
    NSDictionary *attr = [NSDictionary
        dictionaryWithObjects:@[font, [NSColor blackColor]]
        forKeys:@[NSFontAttributeName, NSForegroundColorAttributeName]];
    NSAttributedString *string = [[NSAttributedString alloc] initWithString:text
        attributes:attr];
    NSTextStorage *ts = [[[_scrollView contentView] documentView] textStorage];
    if([ts length] == 0)
        [ts setAttributedString:string];
    else
        [ts appendAttributedString:string];
}

- (void)fileHandleReadDidComplete:(NSNotification *)aNotification {
    NSData *data = [[aNotification userInfo] objectForKey:NSFileHandleNotificationDataItem];
    if([data length] == 0)
        return;
    NSString *text = [[NSString alloc] initWithData:data
        encoding:NSUTF8StringEncoding];
    [self appendInstallLog:text];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
    NSLog(@"will terminate");
}


- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}


@end
