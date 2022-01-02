/*
 * airyxOS Application Launcher & Status Bar
 *
 * Copyright (C) 2021-2022 Zoe Knox <zoe@pixin.net>
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

#import <Foundation/Foundation.h>
#import <LaunchServices/LaunchServices.h>

#include "Dock.h"
#include "DockItem.h"

#include <QPainterPath>
#include <QRegion>
#include <QWindow>
#include <QFrame>
#include <QLabel>
#include <QPixmap>
#include <QPainter>
#include <QMouseEvent>
#include <QDebug>

#include <fcntl.h>
#include <unistd.h>
#include <X11/Xlib.h>
#include <X11/Xatom.h>

Dock::Dock()
    :QWidget(nullptr, Qt::FramelessWindowHint | Qt::WindowStaysOnTopHint |
            Qt::WindowOverridesSystemGestures | Qt::WindowDoesNotAcceptFocus)
    ,m_currentSize(900,64)
    ,m_itemSlots(0)
{
    m_prefs = [[NSUserDefaults standardUserDefaults] retain];
    m_items = [NSMutableArray arrayWithCapacity:20];

    this->setAttribute(Qt::WA_AlwaysShowToolTips);

    m_iconRun = new QPixmap(QIcon(QString::fromUtf8(
        [[[NSBundle mainBundle] pathForResource:@"running" ofType:@"png"]
        UTF8String])).pixmap(8, 8));

    NSString *s = [m_prefs stringForKey:INFOKEY_CUR_SIZE];
    if(s) {
        NSSize sz = NSSizeFromString(s);
        m_currentSize.setWidth(sz.width);
        m_currentSize.setHeight(sz.height);
    }

    int pos = [m_prefs integerForKey:INFOKEY_LOCATION];
    switch(pos) {
        case LOCATION_LEFT:
        case LOCATION_RIGHT:
            m_location = (Location)pos;
            break;
        default:
            m_location = LOCATION_BOTTOM;
    }

    this->relocate();
    this->setWindowOpacity(0.92);

    Display *display = XOpenDisplay(":0");
    Atom wintype = XInternAtom(display, "_NET_WM_WINDOW_TYPE_DOCK", True);

    XChangeProperty(display, this->winId(),
        XInternAtom(display, "_NET_WM_WINDOW_TYPE", True),
        XA_ATOM, 32, PropModeReplace,
        (const unsigned char *)&wintype, 1L);
    XFlush(display);

    m_cells = new QGridLayout(this);

    this->loadItems();
    this->loadProcessTable();
}

Dock::~Dock()
{
    delete m_cells;
    delete m_iconRun;
    [m_prefs release];
    [m_items release];
}

void Dock::loadItems()
{
    int size = (m_location == LOCATION_BOTTOM
        ? m_currentSize.height() : m_currentSize.width()) - 16;

    int items = (m_location == LOCATION_BOTTOM
        ? m_currentSize.width() : m_currentSize.height())
        / (size + CELL_SPACER + CELL_SPACER);
    m_itemSlots = items;

    // addItem( trash, items );
    --items;
    m_cells->setMargin(2);
    if(m_location == LOCATION_BOTTOM) {
        m_cells->setHorizontalSpacing(CELL_SPACER);
        m_cells->setVerticalSpacing(0);
        m_cells->setColumnStretch(items, 100);
    } else {
        m_cells->setHorizontalSpacing(0);
        m_cells->setVerticalSpacing(CELL_SPACER);
        m_cells->setRowStretch(items, 100);
    }
    --items;

    int item = 0;


    NSMutableArray *apps = [NSMutableArray new];
    [apps addObject:@"/System/Library/CoreServices/Filer.app"];
    NSEnumerator *currentItems = [[m_prefs objectForKey:INFOKEY_CUR_ITEMS]
        objectEnumerator];
    NSString *cur;
    while(cur = [currentItems nextObject])
        [apps addObject:cur];

    for(int x = 0; x < [apps count]; ++x) {
        NSString *s = [apps objectAtIndex:x];
        DockItem *info = [DockItem dockItemWithPath:s];
        if(item == 0)
            [info setLocked:YES];
        [m_items addObject:info]; // must keep in same order as m_cells!

        QLabel *iconLabel = new QLabel;
        iconLabel->setAlignment(Qt::AlignCenter);
        iconLabel->setSizePolicy(QSizePolicy::Expanding,
            QSizePolicy::Expanding);

        QPixmap pix([info icon]->pixmap(QSize(size, size)));
        iconLabel->setPixmap(pix);
        iconLabel->setToolTip(QString::fromUtf8([[info label] UTF8String]));

        if(m_location == LOCATION_BOTTOM)
            m_cells->addWidget(iconLabel, 0, item++, Qt::AlignCenter);
        else
            m_cells->addWidget(iconLabel, item++, 0, Qt::AlignCenter);

        if(item > items) {
            // FIXME: do resize up to maximum
            NSLog(@"Too many items!");
            return;
        }
    }

    // FIXME: fill in remaining item slots with empty iteminfo & trash info
}

void Dock::swapWH()
{
    int h = m_currentSize.height();
    m_currentSize.setHeight(m_currentSize.width());
    m_currentSize.setWidth(h);
}

void Dock::savePrefs()
{
    NSSize sz = NSMakeSize(m_currentSize.width(), m_currentSize.height());
    [m_prefs setObject:NSStringFromSize(sz) forKey:INFOKEY_CUR_SIZE];
    [m_prefs setInteger:m_location forKey:INFOKEY_LOCATION];
    if([m_prefs stringForKey:INFOKEY_FILER_DEF_FOLDER] == nil)
        [m_prefs setObject:@"~" forKey:INFOKEY_FILER_DEF_FOLDER];
    [m_prefs synchronize];
}

bool Dock::capLength()
{
    bool capped = false;

    switch(m_location) {
        case LOCATION_BOTTOM:
            if(m_currentSize.width() > m_maxLength) {
                m_currentSize.setWidth(m_maxLength);
                capped = true;
            }
            if(m_currentSize.width() < DOCK_LENGTH_MIN)
                m_currentSize.setWidth(DOCK_LENGTH_MIN);
            break;
        default:
            if(m_currentSize.height() > m_maxLength) {
                m_currentSize.setHeight(m_maxLength);
                capped = true;
            }
            if(m_currentSize.height() < DOCK_LENGTH_MIN)
                m_currentSize.setHeight(DOCK_LENGTH_MIN);
    }
    return capped;
}

// TODO: connect primaryScreenChanged signal to this
// TODO: connect availableGeometryChanged signal to this
void Dock::relocate()
{
    m_screen = QGuiApplication::primaryScreen();
    QRect geom(m_screen->availableGeometry());

    int edgeGap = 0;
    int ypos, xpos;

    if(m_location == LOCATION_BOTTOM) {
        edgeGap = 8;
        m_maxLength = geom.right() - geom.left() - 16;

        // currently taller than wide? swap width & height for new layout
        if(m_currentSize.width() < m_currentSize.height())
            swapWH();
        capLength();

        ypos = geom.bottom() - edgeGap - m_currentSize.height();
        xpos = geom.center().x() - (m_currentSize.width() / 2);
    } else {
        // available geom should already exclude menu bar
        m_maxLength = geom.bottom() - geom.top() - 16;

        // wider than tall? swap width & height for new layout
        if(m_currentSize.width() > m_currentSize.height())
            swapWH();
        capLength();

        ypos = geom.center().y() - edgeGap - (m_currentSize.height() / 2);
        
        if(m_location == LOCATION_LEFT)
            xpos = edgeGap;
        else
            xpos = geom.right() - edgeGap - m_currentSize.width();
    }

    // Get in position and update size
    this->move(xpos, ypos);
    this->resize(m_currentSize);

    // Round our corners
    QPainterPath roundy;
    roundy.addRoundedRect(this->rect(), RADIUS, RADIUS);
    QRegion mask = QRegion(roundy.toFillPolygon().toPolygon());
    this->clearMask();
    this->setMask(mask);

    this->savePrefs();
    this->show();
}

int Dock::itemFromPos(int x, int y)
{
    int size = (m_location == LOCATION_BOTTOM)
        ? m_currentSize.width() : m_currentSize.height();
    int cellsize = size / m_itemSlots;

    int item = -1;
    if(m_location == LOCATION_BOTTOM)
        item = x / cellsize;
    else
        item = y / cellsize;
    return item;
}

void Dock::mousePressEvent(QMouseEvent *e)
{
    int itempos = itemFromPos(e->x(), e->y());
    DockItem *item = [m_items objectAtIndex:itempos];
    if(!item)
        return;

    switch(e->button()) {
        case Qt::LeftButton: // logical left, the primary action
        {
            LSLaunchURLSpec spec = { 0 };
            spec.appURL = (CFURLRef)[NSURL fileURLWithPath:[item path]];
            if(itempos == 0) // Filer is special
                spec.itemURLs = (CFArrayRef)[NSArray arrayWithObject:
                    [NSURL fileURLWithPath:
                    [[m_prefs stringForKey:INFOKEY_FILER_DEF_FOLDER]
                    stringByStandardizingPath]]];
            LSOpenFromURLSpec(&spec, NULL);
            [item setNeedsAttention:YES]; // bouncy bouncy
            // FIXME: get and save PID
            break;
        }
        case Qt::RightButton: // logical right, the secondary action
            NSLog(@"right click %d, show the menu now",itempos);
            break;
        default: break;
    }
}

void Dock::mouseReleaseEvent(QMouseEvent *e)
{
    NSLog(@"mouseRelease");
}

void Dock::mouseDoubleClickEvent(QMouseEvent *e)
{
    NSLog(@"mouseDouble");
}

void Dock::mouseMoveEvent(QMouseEvent *e)
{
    NSLog(@"mouseMove - dragging item %d", itemFromPos(e->x(), e->y()));
}

// At startup, load a snapshot of running processes to init status indicators
// After startup, we track launch/exits in other ways
void Dock::loadProcessTable()
{
    NSMutableDictionary *processDict = [NSMutableDictionary
        dictionaryWithCapacity:200];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSEnumerator *procs = [[fm directoryContentsAtPath:@"/proc"]
        objectEnumerator];

    NSString *spid;
    char buf[PATH_MAX];
    while((spid = [procs nextObject])) {
        int pid = [spid intValue];
        if(pid < 2)
            continue;

        // Read the actual path of the executable
        NSString *path = [NSString stringWithFormat:@"/proc/%@/file", spid];
        int len = readlink([path UTF8String], buf, PATH_MAX-1);
        if(len <= 0)
            continue;
        NSString *name = [NSString stringWithCString:buf length:len];
        NSBundle *bundle = [NSBundle bundleWithModulePath:name];
        NSString *bname = [bundle bundlePath];

        if([processDict objectForKey:name] == nil) {
            NSMutableArray *pids = [NSMutableArray new];
            [pids addObject:[NSNumber numberWithInteger:pid]];
            [processDict setObject:pids forKey:name];
        } else {
            NSMutableArray *pids = [processDict objectForKey:name];
            [pids addObject:[NSNumber numberWithInteger:pid]];
        }

        if(![bname isEqualToString:@"/"] && ![bname isEqualToString:name]) {
            if([processDict objectForKey:bname] == nil) {
                NSMutableArray *pids = [NSMutableArray new];
                [pids addObject:[NSNumber numberWithInteger:pid]];
                [processDict setObject:pids forKey:bname];
            } else {
                NSMutableArray *pids = [processDict objectForKey:bname];
                [pids addObject:[NSNumber numberWithInteger:pid]];
            }
        }
    }

    for(int i = 0; i < [m_items count]; ++i) {
        DockItem *di = [m_items objectAtIndex:i];
        pid_t pid = 0;
        NSArray *pids = [processDict objectForKey:[di execPath]];
        if(pids)
            pid = [[pids firstObject] intValue];
        if(pid == 0) {
            pids = [processDict objectForKey:[di path]];
            if(pids)
                pid = [[pids firstObject] intValue];
        }
        [di setRunning:pid];

        if([di isRunning]) {
            QLabel *l = new QLabel;
            l->setPixmap(*m_iconRun);
            [di setRunningMarker:l]; // save this so we can delete later

            switch(m_location) {
                case LOCATION_LEFT:
                    m_cells->addWidget(l, i, 0,
                        Qt::AlignVCenter | Qt::AlignLeft);
                    break;
                case LOCATION_RIGHT:
                    m_cells->addWidget(l, i, 0,
                        Qt::AlignVCenter | Qt::AlignRight);
                    break;
                default:
                    m_cells->addWidget(l, 0, i,
                        Qt::AlignHCenter | Qt::AlignBottom);
                    break;
            }
        }
    }
}
