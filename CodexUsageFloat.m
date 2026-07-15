#import <Cocoa/Cocoa.h>

@interface UsageView : NSView
@property NSDictionary *snapshot;
@property NSRect refreshRect, closeRect;
@property NSRect statsRect;
@property NSRect resizeRect;
@property (copy) void (^refreshHandler)(void);
@property (copy) void (^closeHandler)(void);
@property (copy) void (^toggleStatsHandler)(void);
@property BOOL statsVisible;
@property NSInteger hoveredBar;
@property NSArray *barRects;
@property NSTrackingArea *hoverTrackingArea;
@property BOOL resizing;
@property NSPoint resizeStart;
@property NSRect resizeStartFrame;
@end

static NSDictionary *DecodeLimit(NSDictionary *d) {
    if (![d isKindOfClass:NSDictionary.class]) return nil;
    if (![d[@"used_percent"] isKindOfClass:NSNumber.class] || ![d[@"resets_at"] isKindOfClass:NSNumber.class]) return nil;
    return d;
}

static NSDictionary *TokenStats(NSArray *files) {
    NSCalendar *calendar=NSCalendar.currentCalendar; NSDate *today=[calendar startOfDayForDate:NSDate.date];
    NSDate *cutoff=[calendar dateByAddingUnit:NSCalendarUnitDay value:-6 toDate:today options:0];
    NSISO8601DateFormatter *iso=NSISO8601DateFormatter.new; iso.formatOptions=NSISO8601DateFormatWithInternetDateTime|NSISO8601DateFormatWithFractionalSeconds;
    NSDateFormatter *keyFormatter=NSDateFormatter.new; keyFormatter.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]; keyFormatter.dateFormat=@"yyyy-MM-dd";
    NSMutableArray *days=NSMutableArray.array; NSMutableDictionary *values=NSMutableDictionary.dictionary;
    for(NSInteger offset=4;offset>=0;offset--){NSDate *date=[calendar dateByAddingUnit:NSCalendarUnitDay value:-offset toDate:today options:0];NSString *key=[keyFormatter stringFromDate:date];[days addObject:@{ @"key":key,@"date":date }];values[key]=@0;}
    NSSet *wanted=[NSSet setWithArray:[days valueForKey:@"key"]];
    for(NSDictionary *file in files){
        if([file[@"date"] compare:cutoff]==NSOrderedAscending)continue;
        NSString *text=[NSString stringWithContentsOfURL:file[@"url"] encoding:NSUTF8StringEncoding error:nil]; long long previous=0;
        for(NSString *line in [text componentsSeparatedByString:@"\n"]){
            if([line rangeOfString:@"\"total_token_usage\""].location==NSNotFound)continue;
            NSDictionary *json=[NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
            NSDictionary *payload=[json isKindOfClass:NSDictionary.class]?json[@"payload"]:nil; NSDictionary *info=[payload isKindOfClass:NSDictionary.class]?payload[@"info"]:nil; NSDictionary *total=[info isKindOfClass:NSDictionary.class]?info[@"total_token_usage"]:nil;
            NSNumber *number=[total isKindOfClass:NSDictionary.class]?total[@"total_tokens"]:nil; if(![number isKindOfClass:NSNumber.class])continue;
            long long current=number.longLongValue,delta=current>=previous?current-previous:current;previous=current;if(delta<=0)continue;
            NSString *stamp=json[@"timestamp"]; NSDate *date=nil; if([stamp isKindOfClass:NSString.class])date=[iso dateFromString:stamp]; if(!date)continue;
            NSString *key=[keyFormatter stringFromDate:date]; if([wanted containsObject:key])values[key]=@([values[key] longLongValue]+delta);
        }
    }
    long long total=0;for(NSString *key in wanted)total+=[values[key] longLongValue];return @{ @"days":days,@"values":values,@"total":@(total) };
}

static NSDictionary *LatestUsage(void) {
    NSString *home = NSHomeDirectory();
    NSArray *roots = @[[home stringByAppendingPathComponent:@".codex/sessions"], [home stringByAppendingPathComponent:@".codex/archived_sessions"]];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableArray *files = NSMutableArray.array;
    for (NSString *root in roots) {
        NSDirectoryEnumerator *e = [fm enumeratorAtURL:[NSURL fileURLWithPath:root] includingPropertiesForKeys:@[NSURLContentModificationDateKey] options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
        for (NSURL *url in e) if ([url.pathExtension isEqualToString:@"jsonl"]) {
            NSDate *date; [url getResourceValue:&date forKey:NSURLContentModificationDateKey error:nil];
            [files addObject:@{ @"url": url, @"date": date ?: NSDate.distantPast }];
        }
    }
    [files sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [b[@"date"] compare:a[@"date"]]; }];
    NSInteger count = MIN(20, files.count);
    for (NSInteger i = 0; i < count; i++) {
        NSDictionary *file = files[i];
        NSString *text = [NSString stringWithContentsOfURL:file[@"url"] encoding:NSUTF8StringEncoding error:nil];
        NSArray *lines = [text componentsSeparatedByString:@"\n"];
        for (NSString *line in lines.reverseObjectEnumerator) {
            if ([line rangeOfString:@"\"rate_limits\""].location == NSNotFound) continue;
            NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (![json isKindOfClass:NSDictionary.class] || ![json[@"payload"] isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *rates = json[@"payload"][@"rate_limits"];
            if (![rates isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *primary = DecodeLimit(rates[@"primary"]), *secondary = DecodeLimit(rates[@"secondary"]), *weekly = nil;
            if ([primary[@"window_minutes"] integerValue] == 10080) weekly = primary;
            else if ([secondary[@"window_minutes"] integerValue] == 10080) weekly = secondary;
            if (weekly) { NSMutableDictionary *result=[@{ @"weekly": weekly, @"plan": [rates[@"plan_type"] capitalizedString] ?: @"Codex", @"date": file[@"date"] } mutableCopy]; result[@"tokens"]=TokenStats(files); return result; }
        }
    }
    return nil;
}

@implementation UsageView
- (instancetype)initWithFrame:(NSRect)frame { if((self=[super initWithFrame:frame]))_hoveredBar=-1;return self; }
- (void)updateTrackingAreas { [super updateTrackingAreas];if(self.hoverTrackingArea)[self removeTrackingArea:self.hoverTrackingArea];self.hoverTrackingArea=[[NSTrackingArea alloc]initWithRect:NSZeroRect options:NSTrackingMouseMoved|NSTrackingMouseEnteredAndExited|NSTrackingActiveAlways|NSTrackingInVisibleRect owner:self userInfo:nil];[self addTrackingArea:self.hoverTrackingArea]; }
- (void)resetCursorRects { [super resetCursorRects];NSRect rect=NSMakeRect(self.bounds.size.width-25,1,24,24);[self addCursorRect:rect cursor:NSCursor.resizeLeftRightCursor]; }
- (BOOL)isOpaque { return NO; }
- (NSColor *)mint { return [NSColor colorWithCalibratedRed:.47 green:.27 blue:.91 alpha:1]; }
- (NSColor *)ink { return [NSColor colorWithCalibratedRed:.13 green:.09 blue:.20 alpha:1]; }
- (void)text:(NSString *)text x:(CGFloat)x y:(CGFloat)y size:(CGFloat)size color:(NSColor *)color weight:(NSFontWeight)weight {
    [text drawAtPoint:NSMakePoint(x,y) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:size weight:weight], NSForegroundColorAttributeName:color}];
}
- (NSString *)resetText:(NSNumber *)epoch {
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:epoch.doubleValue]; NSTimeInterval left = date.timeIntervalSinceNow;
    if (left <= 0) return @"即将更新";
    NSInteger d = left/86400, h = ((NSInteger)left%86400)/3600, m = ((NSInteger)left%3600)/60;
    if (d > 0) { NSDateFormatter *f=NSDateFormatter.new; f.locale=[NSLocale localeWithLocaleIdentifier:@"zh_CN"]; f.dateFormat=@"E HH:mm"; return [NSString stringWithFormat:@"%@ · %ld天%ld时",[f stringFromDate:date],d,h]; }
    return [NSString stringWithFormat:@"%ld时%ld分",h,m];
}
- (NSString *)compactNumber:(long long)value { if(value>=1000000)return [NSString stringWithFormat:@"%.2fM",value/1000000.0];if(value>=1000)return [NSString stringWithFormat:@"%.1fK",value/1000.0];return [NSString stringWithFormat:@"%lld",value]; }
- (void)drawTokenStats {
    NSDictionary *stats=self.snapshot[@"tokens"],*values=stats[@"values"];NSArray *days=stats[@"days"];CGFloat x=454;
    [[NSColor colorWithCalibratedRed:.47 green:.27 blue:.91 alpha:.10]setFill];NSRectFill(NSMakeRect(437,20,1,self.bounds.size.height-40));
    [self text:@"过去 5 天 Token" x:x y:145 size:14 color:self.ink weight:NSFontWeightSemibold];
    [self text:@"总用量" x:x y:119 size:11 color:[NSColor colorWithCalibratedRed:.45 green:.41 blue:.51 alpha:1] weight:NSFontWeightRegular];
    [self text:[self compactNumber:[stats[@"total"] longLongValue]] x:x y:85 size:30 color:self.ink weight:NSFontWeightBold];
    long long maximum=1;for(NSDictionary *day in days)maximum=MAX(maximum,[values[day[@"key"]] longLongValue]);
    NSDateFormatter *label=NSDateFormatter.new;label.locale=[NSLocale localeWithLocaleIdentifier:@"zh_CN"];label.dateFormat=@"M/d";
    CGFloat base=38,barWidth=30,gap=13;NSMutableArray *rects=NSMutableArray.array;
    for(NSInteger i=0;i<days.count;i++){NSDictionary *day=days[i];long long value=[values[day[@"key"]]longLongValue];CGFloat bx=x+i*(barWidth+gap),height=MAX(3,38.0*value/maximum);
        NSRect track=NSMakeRect(bx,base,barWidth,38);[[NSColor colorWithCalibratedRed:.47 green:.27 blue:.91 alpha:.08]setFill];[[NSBezierPath bezierPathWithRoundedRect:track xRadius:5 yRadius:5]fill];
        NSRect bar=NSMakeRect(bx,base,barWidth,height);[rects addObject:[NSValue valueWithRect:track]];NSGradient *g=[[NSGradient alloc]initWithStartingColor:[NSColor colorWithCalibratedRed:.39 green:.19 blue:.86 alpha:1] endingColor:[NSColor colorWithCalibratedRed:.70 green:.48 blue:.98 alpha:1]];[g drawInBezierPath:[NSBezierPath bezierPathWithRoundedRect:bar xRadius:5 yRadius:5] angle:90];
        [self text:[label stringFromDate:day[@"date"]] x:bx+2 y:20 size:9 color:[NSColor colorWithCalibratedRed:.47 green:.43 blue:.54 alpha:1] weight:NSFontWeightRegular];
    }
    self.barRects=rects;
    if(self.hoveredBar>=0&&self.hoveredBar<days.count){NSDictionary *day=days[self.hoveredBar];long long value=[values[day[@"key"]]longLongValue];NSString *tip=[self compactNumber:value];NSDictionary *a=@{NSFontAttributeName:[NSFont systemFontOfSize:10 weight:NSFontWeightSemibold],NSForegroundColorAttributeName:NSColor.whiteColor};NSSize size=[tip sizeWithAttributes:a];NSRect bar=[rects[self.hoveredBar]rectValue];NSRect bubble=NSMakeRect(NSMidX(bar)-size.width/2-7,82,size.width+14,22);[[NSColor colorWithCalibratedRed:.30 green:.16 blue:.55 alpha:.96]setFill];[[NSBezierPath bezierPathWithRoundedRect:bubble xRadius:8 yRadius:8]fill];[tip drawAtPoint:NSMakePoint(NSMinX(bubble)+7,NSMinY(bubble)+5)withAttributes:a];}
}
- (void)drawLimit:(NSString *)title value:(NSDictionary *)limit y:(CGFloat)y {
    double used=[limit[@"used_percent"] doubleValue], remain=MAX(0,100-used); NSColor *muted=[NSColor colorWithCalibratedRed:.42 green:.38 blue:.49 alpha:1];
    [self text:@"本周剩余" x:24 y:y+30 size:12.5 color:muted weight:NSFontWeightMedium];
    [self text:[NSString stringWithFormat:@"%.0f",remain] x:22 y:y-10 size:42 color:self.ink weight:NSFontWeightBold];
    [self text:@"%" x:80 y:y+1 size:19 color:self.mint weight:NSFontWeightSemibold];

    NSString *reset=[NSString stringWithFormat:@"↻  %@ 重置",[self resetText:limit[@"resets_at"]]];
    NSDictionary *attrs=@{NSFontAttributeName:[NSFont systemFontOfSize:11.5 weight:NSFontWeightMedium],NSForegroundColorAttributeName:[NSColor colorWithCalibratedRed:.36 green:.25 blue:.53 alpha:1]};
    NSSize resetSize=[reset sizeWithAttributes:attrs]; NSRect pill=NSMakeRect(430-resetSize.width-40,y+2,resetSize.width+20,28);
    [[NSColor colorWithCalibratedRed:.47 green:.27 blue:.91 alpha:.09] setFill]; [[NSBezierPath bezierPathWithRoundedRect:pill xRadius:14 yRadius:14] fill];
    [reset drawAtPoint:NSMakePoint(NSMinX(pill)+10,NSMinY(pill)+7) withAttributes:attrs];

    NSRect track=NSMakeRect(24,y-24,382,7); [[NSColor colorWithCalibratedRed:.47 green:.27 blue:.91 alpha:.10] setFill]; [[NSBezierPath bezierPathWithRoundedRect:track xRadius:3.5 yRadius:3.5] fill];
    NSRect fill=track; fill.size.width*=remain/100; NSBezierPath *fillPath=[NSBezierPath bezierPathWithRoundedRect:fill xRadius:3.5 yRadius:3.5];
    NSGradient *bar=[[NSGradient alloc]initWithStartingColor:[NSColor colorWithCalibratedRed:.39 green:.19 blue:.86 alpha:1] endingColor:[NSColor colorWithCalibratedRed:.68 green:.44 blue:.97 alpha:1]]; [bar drawInBezierPath:fillPath angle:0];
    [self text:[NSString stringWithFormat:@"已使用 %.0f%%",used] x:24 y:y-45 size:10.5 color:[NSColor colorWithCalibratedRed:.48 green:.44 blue:.54 alpha:1] weight:NSFontWeightRegular];
}
- (void)drawRect:(NSRect)dirty {
    NSRect b=NSInsetRect(self.bounds,1,1); NSBezierPath *bg=[NSBezierPath bezierPathWithRoundedRect:b xRadius:25 yRadius:25];
    NSGradient *surface=[[NSGradient alloc]initWithColors:@[[NSColor colorWithCalibratedRed:1 green:1 blue:1 alpha:.985],[NSColor colorWithCalibratedRed:.965 green:.95 blue:1 alpha:.985]]]; [surface drawInBezierPath:bg angle:-62];
    [[NSColor colorWithCalibratedRed:.47 green:.27 blue:.91 alpha:.20] setStroke]; bg.lineWidth=1; [bg stroke];
    NSBezierPath *glow=[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(-80,80,250,170)]; [[NSColor colorWithCalibratedRed:.53 green:.31 blue:.95 alpha:.08] setFill]; [glow fill];

    NSRect mark=NSMakeRect(22,139,27,27); [[NSColor colorWithCalibratedRed:.47 green:.27 blue:.91 alpha:.12] setFill]; [[NSBezierPath bezierPathWithRoundedRect:mark xRadius:8 yRadius:8] fill];
    [self text:@"C" x:29 y:144 size:13 color:self.mint weight:NSFontWeightBold];
    NSColor *muted=[NSColor colorWithCalibratedRed:.45 green:.41 blue:.51 alpha:1]; [self text:@"Codex Usage" x:58 y:145 size:15 color:self.ink weight:NSFontWeightSemibold];
    NSString *plan=self.snapshot[@"plan"]?:@"等待数据"; [self text:plan x:154 y:146 size:11 color:self.mint weight:NSFontWeightMedium];
    self.refreshRect=NSMakeRect(354,137,28,28); self.closeRect=NSMakeRect(388,137,28,28);
    [[NSColor colorWithCalibratedRed:.47 green:.27 blue:.91 alpha:.075] setFill]; [[NSBezierPath bezierPathWithRoundedRect:self.refreshRect xRadius:9 yRadius:9] fill]; [[NSBezierPath bezierPathWithRoundedRect:self.closeRect xRadius:9 yRadius:9] fill];
    [self text:@"↻" x:NSMinX(self.refreshRect)+6 y:141 size:18 color:muted weight:NSFontWeightRegular]; [self text:@"×" x:NSMinX(self.closeRect)+7 y:142 size:17 color:muted weight:NSFontWeightRegular];
    [[NSColor colorWithCalibratedRed:.47 green:.27 blue:.91 alpha:.10] setFill]; NSRect divider=NSMakeRect(22,128,386,1); NSRectFill(divider);
    self.resizeRect=NSMakeRect(b.size.width-25,1,24,24);NSColor *grip=[NSColor colorWithCalibratedRed:.47 green:.27 blue:.91 alpha:.28];[grip setStroke];
    for(NSInteger i=0;i<3;i++){NSBezierPath *line=NSBezierPath.bezierPath;[line moveToPoint:NSMakePoint(b.size.width-7-i*5,5)];[line lineToPoint:NSMakePoint(b.size.width-5,7+i*5)];line.lineWidth=1.2;[line stroke];}
    if (self.snapshot) {
        [self drawLimit:@"本周" value:self.snapshot[@"weekly"] y:74];
        NSTimeInterval age=-[self.snapshot[@"date"] timeIntervalSinceNow]; NSString *relative=age<60?@"刚刚更新":age<3600?[NSString stringWithFormat:@"%.0f 分钟前",age/60]:[NSString stringWithFormat:@"%.0f 小时前",age/3600];
        NSString *status=[@"●  本机数据 · " stringByAppendingString:relative]; [self text:status x:285 y:29 size:10.5 color:[NSColor colorWithCalibratedRed:.47 green:.27 blue:.91 alpha:.78] weight:NSFontWeightRegular];
        self.statsRect=NSMakeRect(103,23,104,24);[[NSColor colorWithCalibratedRed:.47 green:.27 blue:.91 alpha:.09]setFill];[[NSBezierPath bezierPathWithRoundedRect:self.statsRect xRadius:12 yRadius:12]fill];
        [self text:self.statsVisible?@"Token 统计  ‹":@"Token 统计  ›" x:115 y:29 size:10.5 color:self.mint weight:NSFontWeightSemibold];if(self.statsVisible)[self drawTokenStats];
    } else { [self text:@"尚未找到用量数据" x:24 y:89 size:22 color:self.ink weight:NSFontWeightSemibold]; [self text:@"在 Codex 中发送一条消息后点击刷新" x:24 y:62 size:12.5 color:muted weight:NSFontWeightRegular]; }
}
- (void)mouseDown:(NSEvent *)event { NSPoint p=[self convertPoint:event.locationInWindow fromView:nil];if(NSPointInRect(p,self.resizeRect)){self.resizing=YES;self.resizeStart=NSEvent.mouseLocation;self.resizeStartFrame=self.window.frame;return;}if(NSPointInRect(p,self.refreshRect)){if(self.refreshHandler)self.refreshHandler();}else if(NSPointInRect(p,self.closeRect)){if(self.closeHandler)self.closeHandler();}else if(NSPointInRect(p,self.statsRect)){if(self.toggleStatsHandler)self.toggleStatsHandler();}else[self.window performWindowDragWithEvent:event]; }
- (void)mouseDragged:(NSEvent *)event { if(!self.resizing)return;NSPoint now=NSEvent.mouseLocation;CGFloat dx=now.x-self.resizeStart.x,dy=now.y-self.resizeStart.y;CGFloat baseWidth=self.statsVisible?700:430,baseHeight=184;CGFloat horizontal=(self.resizeStartFrame.size.width+dx)/baseWidth,vertical=(self.resizeStartFrame.size.height-dy)/baseHeight;CGFloat scale=fabs(dx)>=fabs(dy)?horizontal:vertical;scale=MAX(.72,MIN(1.85,scale));NSRect frame=self.resizeStartFrame;frame.size=NSMakeSize(baseWidth*scale,baseHeight*scale);frame.origin.y=NSMaxY(self.resizeStartFrame)-frame.size.height;[self.window setFrame:frame display:YES];[self setBoundsSize:NSMakeSize(baseWidth,baseHeight)]; }
- (void)mouseUp:(NSEvent *)event { self.resizing=NO; }
- (void)mouseMoved:(NSEvent *)event { if(!self.statsVisible)return;NSPoint p=[self convertPoint:event.locationInWindow fromView:nil];NSInteger hit=-1;for(NSInteger i=0;i<self.barRects.count;i++)if(NSPointInRect(p,[self.barRects[i]rectValue])){hit=i;break;}if(hit!=self.hoveredBar){self.hoveredBar=hit;[self setNeedsDisplay:YES];} }
- (void)mouseExited:(NSEvent *)event { if(self.hoveredBar!=-1){self.hoveredBar=-1;[self setNeedsDisplay:YES];} }
@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property NSPanel *panel; @property UsageView *view; @property NSStatusItem *statusItem;
@end
@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)n {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory]; self.view=[[UsageView alloc]initWithFrame:NSMakeRect(0,0,430,184)];
    self.panel=[[NSPanel alloc]initWithContentRect:self.view.bounds styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    self.panel.contentView=self.view; self.panel.opaque=NO; self.panel.backgroundColor=NSColor.clearColor; self.panel.hasShadow=YES; self.panel.level=NSFloatingWindowLevel; self.panel.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary; self.panel.movableByWindowBackground=YES; self.panel.hidesOnDeactivate=NO;self.panel.acceptsMouseMovedEvents=YES;
    NSRect screen=NSScreen.mainScreen.visibleFrame; [self.panel setFrameOrigin:NSMakePoint(NSMaxX(screen)-452,NSMaxY(screen)-206)]; [self.panel orderFrontRegardless];
    __weak typeof(self) weak=self; self.view.refreshHandler=^{[weak refresh];}; self.view.closeHandler=^{[weak hidePanel];};
    self.view.toggleStatsHandler=^{[weak toggleStats];};
    self.statusItem=[NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength]; self.statusItem.button.image=[NSImage imageWithSystemSymbolName:@"gauge.with.dots.needle.33percent" accessibilityDescription:@"Codex 用量"]; self.statusItem.button.toolTip=@"Codex 用量";
    NSMenu *menu=NSMenu.new;
    [menu addItemWithTitle:@"显示悬浮窗" action:@selector(showPanel) keyEquivalent:@""];
    [menu addItemWithTitle:@"隐藏悬浮窗" action:@selector(hidePanel) keyEquivalent:@""];
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItemWithTitle:@"立即刷新" action:@selector(refresh) keyEquivalent:@"r"];
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItemWithTitle:@"退出 Codex 用量" action:@selector(quitApp) keyEquivalent:@"q"];
    for(NSMenuItem *item in menu.itemArray)item.target=self; self.statusItem.menu=menu;
    [self refresh]; [NSTimer scheduledTimerWithTimeInterval:45 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
}
- (void)showPanel { [self.panel orderFrontRegardless]; }
- (void)hidePanel { [self.panel orderOut:nil]; }
- (void)toggleStats { BOOL show=!self.view.statsVisible;CGFloat newBase=show?700:430;CGFloat scale=self.panel.frame.size.height/184.0;self.view.statsVisible=show;NSRect frame=self.panel.frame;CGFloat right=NSMaxX(frame);frame.size.width=newBase*scale;frame.origin.x=right-frame.size.width;[self.panel setFrame:frame display:YES animate:YES];[self.view setBoundsSize:NSMakeSize(newBase,184)];[self.view setNeedsDisplay:YES]; }
- (void)quitApp { [NSApp terminate:nil]; }
- (void)refresh { dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{ NSDictionary *s=LatestUsage(); dispatch_async(dispatch_get_main_queue(),^{self.view.snapshot=s; [self.view setNeedsDisplay:YES];});}); }
@end

int main(int argc,const char *argv[]){@autoreleasepool{NSApplication *app=NSApplication.sharedApplication;AppDelegate *delegate=AppDelegate.new;app.delegate=delegate;[app run];}return 0;}
