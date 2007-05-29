/*
 * Copyright (c) 2006 KATO Kazuyoshi <kzys@8-p.info>
 * This source code is released under the MIT license.
 */

#import "CMController.h"

#import <WebKit/WebKit.h>
#import "CMUserScript.h"
#import "XMLHttpRequest.h"

@implementation CMController
- (NSString*) loadScriptTemplate
{
    NSBundle* bundle = [NSBundle bundleWithIdentifier: @"info.8-p.Creammonkey"];
    NSString* path = [NSString stringWithFormat: @"%@/template.js", [bundle resourcePath]];   
    NSLog(@"path = %@", path);
    return [NSString stringWithContentsOfFile: path];
}

- (NSArray*) scripts
{
	return scripts_;
}

- (NSDictionary*) scriptsConfig
{
    NSString* path = [@"~/Library/Application Support/Creammonkey/config.plist" stringByExpandingTildeInPath];
    return [NSDictionary dictionaryWithContentsOfFile: path];
}

- (void) saveScriptsConfig
{
    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    
    NSEnumerator* enumerator = [scripts_ objectEnumerator];
    CMUserScript* script;
    while (script = [enumerator nextObject]) {
        [dict setObject: [NSNumber numberWithBool: [script isEnabled]]
                 forKey: [script basename]];
    }
    
    NSString* path = [@"~/Library/Application Support/Creammonkey/config.plist" stringByExpandingTildeInPath];
    [dict writeToFile: path atomically: YES];
}

- (void) installScript: (CMUserScript*) s
{
    [s install: scriptDir_];
    
    [scripts_ addObject: s];
    [self saveScriptsConfig];
    [self reloadUserScripts: nil];
}

- (void) reloadMenu
{
    int i;

    int count = [menu indexOfItemWithTag: -1];
    for (i = 0; i < count; i++) {
        [menu removeItemAtIndex: 0];
    }
    
    for (i = 0; i < [scripts_ count]; i++) {  
        CMUserScript* script = [scripts_ objectAtIndex: i];
        
        NSMenuItem* item = [[NSMenuItem alloc] init];
        
        [item setTag: i];
        [item setTarget: self];
        [item setAction: @selector(toggleScriptEnable:)];
        [item setState: [script isEnabled] ? NSOnState : NSOffState];
        
        [item setTitle: [script name]];
        [menu insertItem: item atIndex: i];
    }
}

- (void) loadUserScripts
{
	NSFileManager* manager;
	manager = [NSFileManager defaultManager];
	
	NSArray* files;
	files = [manager directoryContentsAtPath: scriptDir_];
	
	if (! files) {
		[manager createDirectoryAtPath: scriptDir_
							attributes: nil];
		files = [manager directoryContentsAtPath: scriptDir_];
	}
	
    NSDictionary* config = [self scriptsConfig];
    
	[self willChangeValueForKey: @"scripts"];
	
	int i;
	for (i = 0; i < [files count]; i++) {
		NSString* path;
		path = [NSString stringWithFormat: @"%@/%@", scriptDir_, [files objectAtIndex: i]];
		
		if (! [path hasSuffix: @".user.js"]) {
			continue;
		}
		
		CMUserScript* script;
		script = [[CMUserScript alloc] initWithContentsOfFile: path];

        [script setEnabled: [[config objectForKey: [script basename]] intValue]];
		
		[scripts_ addObject: script];
		[script release];
	}
	[self didChangeValueForKey: @"scripts"];
    
    [self reloadMenu];
}

- (NSArray*) matchedScripts: (NSURL*) url
{
	NSMutableArray* result = [[NSMutableArray alloc] init];
	
	int i;
	for (i = 0; i < [scripts_ count]; i++) {
		CMUserScript* script = [scripts_ objectAtIndex: i];
		if ([script isEnabled] && [script isMatched: url]) {
			[result addObject: [script script]];
		}
	}
	
	return [result autorelease];
}

- (void) installAlertDidEnd: (NSAlert*) alert
				 returnCode: (int) returnCode
				contextInfo: (void*) contextInfo
{
	CMUserScript* script = (CMUserScript*) contextInfo;
	if (returnCode == NSAlertFirstButtonReturn) {
        [self installScript: script];
	}
	[script release];
}

- (void) showInstallAlertSheet: (CMUserScript*) script
					   webView: (WebView*) webView
{
	NSAlert* alert = [[NSAlert alloc] init];

	// Informative Text
	NSMutableString* text = [[NSMutableString alloc] init];
	
	if ([script name] && [script description]) {
		[text appendFormat: @"%@ - %@", [script name], [script description]];
	} else {
		if ([script name])
			[text appendString: [script name]];
		else if ([script description])
			[text appendString: [script description]];
	}
	
	[alert setInformativeText: text];
	[text release];
	
	// Message and Buttons
	if([script isInstalled: scriptDir_]) {
		[alert setMessageText: @"This script is installed, Override?"];	
		[alert addButtonWithTitle: @"Override"];
	} else {
		[alert setMessageText: @"Install this script?"];	
		[alert addButtonWithTitle: @"Install"];
	}
	[alert addButtonWithTitle: @"Cancel"];
	
	// Begin Sheet
	[alert beginSheetModalForWindow: [webView window]
					  modalDelegate: self
					 didEndSelector: @selector(installAlertDidEnd:returnCode:contextInfo:)
						contextInfo: script];	
}

- (void) evalScriptsInWebView: (WebView*) webView
{
	WebDataSource* dataSource = [[webView mainFrame] dataSource];
	NSURL* url = [[dataSource request] URL];

    if (! [[webView mainFrame] DOMDocument]) {
		return;
	}

    // Eval Once?
    NSString* s = [webView stringByEvaluatingJavaScriptFromString: @"document.body.__creammonkeyed__;"];
    if ([s isEqualToString: @"true"]) {
        return;
    } else {
		[webView stringByEvaluatingJavaScriptFromString: @"document.body.__creammonkeyed__ = true;"];
    }
	
    // Eval!
    id scriptObject = [webView windowScriptObject];
    NSString* bridgeName = [NSString stringWithFormat: @"bridge%x", rand()];
    if ([scriptObject valueForKey: bridgeName] != self) {
        [scriptObject setValue: self forKey: bridgeName];
    }

	NSArray* ary = [self matchedScripts: url];
	int i;
	for (i = 0; i < [ary count]; i++) {
        NSMutableString* ms = [NSMutableString stringWithString: scriptTemplate_];

        [ms replaceOccurrencesOfString: @"<bridge>"
                            withString: bridgeName
                               options: 0
                                 range: NSMakeRange(0, [ms length])];
        [ms replaceOccurrencesOfString: @"<body>"
                            withString: [ary objectAtIndex: i]
                               options: 0
                                 range: NSMakeRange(0, [ms length])];
     
        NSLog(@"ms = %@", ms);
        [webView stringByEvaluatingJavaScriptFromString: ms];
	}
    [scriptObject setValue: nil forKey: bridgeName];
}

- (void) progressStarted: (NSNotification*) n
{
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
	[center addObserver: self
			   selector: @selector(progressChanged:)
				   name: WebViewProgressEstimateChangedNotification
				 object: [n object]];
}

+ (BOOL) isSelectorExcludedFromWebScript: (SEL) sel
{
    if (sel == @selector(gmLog:) ||
        sel == @selector(gmValueForKey:defaultValue:) ||
        sel == @selector(gmSetValue:forKey:) ||
        sel == @selector(gmRegisterMenuCommand:callback:) ||
        sel == @selector(gmXmlhttpRequest:))
        return NO;
    else
        return YES;
}

+ (BOOL) isKeyExcludedFromWebScript: (const char*) name
{
    return YES;
}

- (id) gmLog: (NSString*) s
{
    NSLog(@"%@", s);
    return nil;
}

- (id) gmValueForKey: (NSString*) key
        defaultValue: (NSString*) value
{
    return value;
}

- (id) gmSetValue: (NSString*) value
           forKey: (NSString*) key
{
    return nil;
}

- (id) gmRegisterMenuCommand: (NSString*) text
                    callback: (id) func
{
    return nil;
}

- (void) gmXmlhttpRequest: (WebScriptObject*) details
{
    [[XMLHttpRequest alloc] initWithDetails: details
                                   delegate: self];
}

- (void) progressChanged: (NSNotification*) n
{    
	WebView* webView = [n object];
    
    if (! [[webView mainFrame] DOMDocument]) {
		return;
    }

    NSString* s = [webView stringByEvaluatingJavaScriptFromString: @"document.readyState"];
    if ([s isEqualToString: @"loaded"]) {
        [self evalScriptsInWebView: webView];
        
        NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
        [center removeObserver: self
                          name: WebViewProgressEstimateChangedNotification
                        object: webView];
    }
}    

- (void) progressFinished: (NSNotification*) n
{
	WebView* webView = [n object];
	WebDataSource* dataSource = [[webView mainFrame] dataSource];
	NSURL* url = [[dataSource request] URL];

    // User Script
	if ([[url absoluteString] hasSuffix: @".user.js"]) {
		CMUserScript* script;
		script = [[CMUserScript alloc] initWithContentsOfURL: url];
		
		if (script) {
			[self showInstallAlertSheet: script webView: webView];
		}
	} else {
        [self evalScriptsInWebView: webView];
    }
}

#pragma mark Action
- (IBAction) toggleScriptEnable: (id) sender
{
    CMUserScript* script = [scripts_ objectAtIndex: [sender tag]];
    
    [script setEnabled: [sender state] != NSOnState];
    [sender setState: [script isEnabled] ? NSOnState : NSOffState];
    
    [self saveScriptsConfig];
}

- (IBAction) uninstallSelected: (id) sender
{
	CMUserScript* script = [[scriptsController selectedObjects] objectAtIndex: 0];
	[script uninstall];
	
	[self reloadUserScripts: sender];
}

- (IBAction) orderFrontAboutPanel: (id) sender
{
	NSImage* icon = [[NSWorkspace sharedWorkspace] iconForFileType: @"bundle"];
	[icon setSize: NSMakeSize(128, 128)];
	
	NSDictionary* options;
	options = [NSDictionary dictionaryWithObjectsAndKeys: 
		@"Creammonkey",  @"ApplicationName",
		icon,  @"ApplicationIcon",
		@"",  @"Version",
		@"Version 0.8",  @"ApplicationVersion",
		@"Copyright (c) 2006 KATO Kazuyoshi",  @"Copyright",
		nil];
	[NSApp orderFrontStandardAboutPanelWithOptions: options];
}


- (IBAction) reloadUserScripts: (id) sender
{
	[scripts_ release];
	
	scripts_ = [[NSMutableArray alloc] init];
	[self loadUserScripts];
}

#pragma mark Override
- (id) init
{
	// Safari?
	NSString* identifier = [[NSBundle mainBundle] bundleIdentifier];
	if (! [identifier isEqual: @"com.apple.Safari"]) {
		return nil;
	}
	
	NSLog(@"CMController %p - init", self);
	self = [super init];
	if (! self)
		return nil;
	
	scriptDir_ = [@"~/Library/Application Support/Creammonkey/" stringByExpandingTildeInPath];
	[scriptDir_ retain];
	
	scripts_ = nil;    
	
	[NSBundle loadNibNamed: @"Menu.nib" owner: self];

    scriptTemplate_ = [[self loadScriptTemplate] retain];
	
	return self;
}

- (void) dealloc
{
	NSLog(@"CMController - dealloc");
	
	[scripts_ release];
    
	[super dealloc];
}

- (void) awakeFromNib
{
	[self reloadUserScripts: nil];

	// Menu
	NSMenuItem* item;

	item = [[NSMenuItem alloc] init];
	[item setSubmenu: menu];
	
	[menu setTitle: @":)"];
	
	[[NSApp mainMenu] addItem: item];
	[item release];
    	
	// Notification
	NSNotificationCenter* center = [NSNotificationCenter defaultCenter];    
	[center addObserver: self
			   selector: @selector(progressStarted:)
				   name: WebViewProgressStartedNotification
				 object: nil];
	[center addObserver: self
			   selector: @selector(progressFinished:)
				   name: WebViewProgressFinishedNotification
				 object: nil];
}


@end
