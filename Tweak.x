#import <version.h>
#import <rootless.h>
#import "Header.h"
#import "../YouTubeHeader/GIMBindingBuilder.h"
#import "../YouTubeHeader/GPBExtensionRegistry.h"
#import "../YouTubeHeader/MLPIPController.h"
#import "../YouTubeHeader/MLDefaultPlayerViewFactory.h"
#import "../YouTubeHeader/YTBackgroundabilityPolicy.h"
#import "../YouTubeHeader/YTMainAppControlsOverlayView.h"
#import "../YouTubeHeader/YTMainAppVideoPlayerOverlayViewController.h"
#import "../YouTubeHeader/YTHotConfig.h"
#import "../YouTubeHeader/YTLocalPlaybackController.h"
#import "../YouTubeHeader/YTPlayerPIPController.h"
#import "../YouTubeHeader/YTSettingsSectionItem.h"
#import "../YouTubeHeader/YTSettingsSectionItemManager.h"
#import "../YouTubeHeader/YTIPictureInPictureRendererRoot.h"
#import "../YouTubeHeader/YTColor.h"
#import "../YouTubeHeader/QTMIcon.h"
#import "../YouTubeHeader/YTSlimVideoScrollableActionBarCellController.h"
#import "../YouTubeHeader/YTSlimVideoScrollableDetailsActionsView.h"
#import "../YouTubeHeader/YTSlimVideoDetailsActionView.h"
#import "../YouTubeHeader/YTISlimMetadataButtonSupportedRenderers.h"
#import "../YouTubeHeader/YTPageStyleController.h"
#import "../YouTubeHeader/YTPlayerStatus.h"
#import "../YouTubeHeader/YTWatchViewController.h"

#define PiPButtonType 801

@interface YTMainAppControlsOverlayView (YP)
@property (retain, nonatomic) YTQTMButton *pipButton;
- (void)didPressPiP:(id)arg;
- (UIImage *)pipImage;
@end

BOOL FromUser = NO;
BOOL PiPDisabled = NO;

extern BOOL LegacyPiP();
extern YTHotConfig *(*InjectYTHotConfig)(void);

BOOL TweakEnabled() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:EnabledKey];
}

BOOL UsePiPButton() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:PiPActivationMethodKey];
}

BOOL NoMiniPlayerPiP() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:NoMiniPlayerPiPKey];
}

BOOL UseTabBarPiPButton() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:PiPActivationMethod2Key];
}

BOOL NonBackgroundable() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:NonBackgroundableKey];
}

BOOL FakeVersion() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:FakeVersionKey];
}

BOOL isPictureInPictureActive(MLPIPController *pip) {
    return [pip respondsToSelector:@selector(pictureInPictureActive)] ? [pip pictureInPictureActive] : [pip isPictureInPictureActive];
}

static NSString *PiPIconPath;
static NSString *TabBarPiPIconPath;
static NSString *PiPVideoPath;

static void forcePictureInPicture(YTHotConfig *hotConfig, BOOL value) {
    [hotConfig mediaHotConfig].enablePictureInPicture = value;
    YTIIosMediaHotConfig *iosMediaHotConfig = hotConfig.hotConfigGroup.mediaHotConfig.iosMediaHotConfig;
    iosMediaHotConfig.enablePictureInPicture = value;
    if ([iosMediaHotConfig respondsToSelector:@selector(setEnablePipForNonBackgroundableContent:)])
        iosMediaHotConfig.enablePipForNonBackgroundableContent = value && NonBackgroundable();
    if ([iosMediaHotConfig respondsToSelector:@selector(setEnablePipForNonPremiumUsers:)])
        iosMediaHotConfig.enablePipForNonPremiumUsers = value;
}

static void activatePiPBase(YTPlayerPIPController *controller, BOOL playPiP) {
    MLPIPController *pip = [controller valueForKey:@"_pipController"];
    if ([controller respondsToSelector:@selector(maybeEnablePictureInPicture)])
        [controller maybeEnablePictureInPicture];
    else if ([controller respondsToSelector:@selector(maybeInvokePictureInPicture)])
        [controller maybeInvokePictureInPicture];
    else {
        BOOL canPiP = [controller respondsToSelector:@selector(canEnablePictureInPicture)] && [controller canEnablePictureInPicture];
        if (!canPiP)
            canPiP = [controller respondsToSelector:@selector(canInvokePictureInPicture)] && [controller canInvokePictureInPicture];
        if (canPiP) {
            if ([pip respondsToSelector:@selector(activatePiPController)])
                [pip activatePiPController];
            else
                [pip startPictureInPicture];
        }
    }
    AVPictureInPictureController *avpip = [pip valueForKey:@"_pictureInPictureController"];
    if (playPiP) {
        if ([avpip isPictureInPicturePossible])
            [avpip startPictureInPicture];
    } else {
        if ([pip respondsToSelector:@selector(deactivatePiPController)])
            [pip deactivatePiPController];
        else
            [avpip stopPictureInPicture];
    }
}

static void activatePiP(YTLocalPlaybackController *local, BOOL playPiP) {
    if (![local isKindOfClass:%c(YTLocalPlaybackController)])
        return;
    YTPlayerPIPController *controller = [local valueForKey:@"_playerPIPController"];
    activatePiPBase(controller, playPiP);
}

static void bootstrapPiP(YTPlayerViewController *self, BOOL playPiP) {
    YTHotConfig *hotConfig;
    @try {
        if (InjectYTHotConfig)
            hotConfig = InjectYTHotConfig();
        else
            hotConfig = [self valueForKey:@"_hotConfig"];
    } @catch (id ex) {
        hotConfig = [[self gimme] instanceForType:%c(YTHotConfig)];
    }
    forcePictureInPicture(hotConfig, YES);
    YTLocalPlaybackController *local = [self valueForKey:@"_playbackController"];
    activatePiP(local, playPiP);
}

#pragma mark - Video tab bar PiP Button

static UIButton *makeUnderPlayerButton(ELMCellNode *node, NSString *title, NSString *accessibilityLabel) {
    ELMContainerNode *containerNode = (ELMContainerNode *)node.yogaChildren[0].yogaChildren[0]; // To get node container properties
    UIButton *buttonView = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 65, containerNode.calculatedSize.height)];
    buttonView.center = CGPointMake(CGRectGetMaxX([node.layoutAttributes frame]) + 65 / 2, CGRectGetMidY([node.layoutAttributes frame]));
    buttonView.backgroundColor = containerNode.backgroundColor;
    buttonView.accessibilityLabel = accessibilityLabel;
    buttonView.layer.cornerRadius = 16;

    UIImageView *buttonImage = [[UIImageView alloc] initWithFrame:CGRectMake(12, ([buttonView frame].size.height - 15.5) / 2, 15.5, 15.5)];
    buttonImage.image = [%c(QTMIcon) tintImage:[UIImage imageWithContentsOfFile:TabBarPiPIconPath] color:[%c(YTColor) white1]];

    UILabel *buttonTitle = [[UILabel alloc] initWithFrame:CGRectMake(33, 9, 20, 14)];
    buttonTitle.font = [UIFont fontWithName:@".SFUIText-Semibold" size:12];
    buttonTitle.textColor = [%c(YTColor) white3];
    buttonTitle.text = title;

    [buttonView addSubview:buttonImage];
    [buttonView addSubview:buttonTitle];
    return buttonView;
}

%hook ASCollectionView

%property (retain, nonatomic) UIButton *pipButton;
%property (retain, nonatomic) YTTouchFeedbackController *pipTouchController;

- (BOOL)touchesShouldCancelInContentView:(id)arg1 {
    return YES; // Ensure we can scroll
}

- (ELMCellNode *)nodeForItemAtIndexPath:(NSIndexPath *)indexPath {
    if (UseTabBarPiPButton() && [self.accessibilityIdentifier isEqual:@"id.video.scrollable_action_bar"] && !self.pipButton) {
        self.contentInset = UIEdgeInsetsMake(0, 0, 0, 73);
        if ([self numberOfItemsInSection:0] - 1 == indexPath.row) {
            self.pipButton = makeUnderPlayerButton(%orig, @"PiP", @"Play in PiP");
            [self addSubview:self.pipButton];

            [self.pipButton addTarget:self action:@selector(didPressPiP:event:) forControlEvents:UIControlEventTouchUpInside];
            YTTouchFeedbackController *controller = [[%c(YTTouchFeedbackController) alloc] initWithView:self.pipButton];
            controller.touchFeedbackView.customCornerRadius = 16;
            self.pipTouchController = controller;
        }
    }
    return %orig;
}

- (void)nodesDidRelayout:(NSArray <ELMCellNode *> *)nodes {
    if (UseTabBarPiPButton() && [self.accessibilityIdentifier isEqual:@"id.video.scrollable_action_bar"] && [nodes count] == 1) {
        CGFloat offset = nodes[0].calculatedSize.width - [nodes[0].layoutAttributes frame].size.width;
        [UIView animateWithDuration:0.3 animations:^{
            self.pipButton.center = (CGPoint){self.pipButton.center.x + offset, self.pipButton.center.y};
        }];
    }
    %orig;
}

%new(v@:@@)
- (void)didPressPiP:(UIButton *)button event:(UIEvent *)event {
    CGPoint location = [[[event allTouches] anyObject] locationInView:button];
    if (CGRectContainsPoint(button.bounds, location)) {
        UIViewController *controller = [self.collectionNode closestViewController];
        YTPlaybackStrippedWatchController *provider = [controller valueForKey:@"_metadataPanelStateProvider"];
        YTWatchViewController *watchViewController = [provider valueForKey:@"_watchViewController"];
        YTPlayerViewController *playerViewController = [watchViewController valueForKey:@"_playerViewController"];
        FromUser = YES;
        bootstrapPiP(playerViewController, YES);
    }
}

%end

#pragma mark - Overlay PiP Button

%hook YTMainAppVideoPlayerOverlayViewController

- (void)updateTopRightButtonAvailability {
    %orig;
    YTMainAppVideoPlayerOverlayView *v = [self videoPlayerOverlayView];
    YTMainAppControlsOverlayView *c = [v valueForKey:@"_controlsOverlayView"];
    c.pipButton.hidden = !UsePiPButton();
    [c setNeedsLayout];
}

%end

static void createPiPButton(YTMainAppControlsOverlayView *self) {
    if (self) {
        CGFloat padding = [[self class] topButtonAdditionalPadding];
        UIImage *image = [self pipImage];
        self.pipButton = [self buttonWithImage:image accessibilityLabel:@"pip" verticalContentPadding:padding];
        self.pipButton.hidden = YES;
        self.pipButton.alpha = 0;
        [self.pipButton addTarget:self action:@selector(didPressPiP:) forControlEvents:UIControlEventTouchUpInside];
        @try {
            [[self valueForKey:@"_topControlsAccessibilityContainerView"] addSubview:self.pipButton];
        } @catch (id ex) {
            [self addSubview:self.pipButton];
        }
    }
}

static NSMutableArray *topControls(YTMainAppControlsOverlayView *self, NSMutableArray *controls) {
    if (UsePiPButton())
        [controls insertObject:self.pipButton atIndex:0];
    return controls;
}

%hook YTMainAppControlsOverlayView

%property (retain, nonatomic) YTQTMButton *pipButton;

- (id)initWithDelegate:(id)delegate {
    self = %orig;
    createPiPButton(self);
    return self;
}

- (id)initWithDelegate:(id)delegate autoplaySwitchEnabled:(BOOL)autoplaySwitchEnabled {
    self = %orig;
    createPiPButton(self);
    return self;
}

- (NSMutableArray *)topButtonControls {
    return topControls(self, %orig);
}

- (NSMutableArray *)topControls {
    return topControls(self, %orig);
}

- (void)setTopOverlayVisible:(BOOL)visible isAutonavCanceledState:(BOOL)canceledState {
    if (UsePiPButton())
        self.pipButton.alpha = canceledState || !visible ? 0.0 : 1.0;
    %orig;
}

%new(@@:)
- (UIImage *)pipImage {
    static UIImage *image = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UIColor *color = [%c(YTColor) white1];
        image = [%c(QTMIcon) tintImage:[UIImage imageWithContentsOfFile:PiPIconPath] color:color];
        if ([image respondsToSelector:@selector(imageFlippedForRightToLeftLayoutDirection)])
            image = [image imageFlippedForRightToLeftLayoutDirection];
    });
    return image;
}

%new(v@:@)
- (void)didPressPiP:(id)arg {
    YTMainAppVideoPlayerOverlayViewController *c = [self valueForKey:@"_eventsDelegate"];
    FromUser = YES;
    bootstrapPiP([c delegate], YES);
}

%end

#pragma mark - PiP Support

%hook AVPictureInPictureController

+ (BOOL)isPictureInPictureSupported {
    return YES;
}

%end

%hook AVPlayerController

- (BOOL)isPictureInPictureSupported {
    return YES;
}

%end

%hook AVSampleBufferDisplayLayerPlayerController

- (void)setPictureInPictureAvailable:(BOOL)available {
    %orig(YES);
}

%end

%hook MLPIPController

- (void)activatePiPController {
    %orig;
    if (!IS_IOS_OR_NEWER(iOS_15_0) && !LegacyPiP()) {
        MLHAMSBDLSampleBufferRenderingView *view = [self valueForKey:@"_HAMPlayerView"];
        CGSize size = [self renderSizeForView:view];
        AVPictureInPictureController *avpip = [self valueForKey:@"_pictureInPictureController"];
        [avpip sampleBufferDisplayLayerRenderSizeDidChangeToSize:size];
        [avpip sampleBufferDisplayLayerDidAppear];
    }
}

- (BOOL)isPictureInPictureSupported {
    return YES;
}

%new(B@:@)
- (BOOL)pictureInPictureControllerPlaybackPaused:(AVPictureInPictureController *)pictureInPictureController {
    return [self pictureInPictureControllerIsPlaybackPaused:pictureInPictureController];
}

%new(v@:@)
- (void)pictureInPictureControllerStartPlayback:(id)arg1 {
    [self pictureInPictureControllerStartPlayback];
}

%new(v@:@)
- (void)pictureInPictureControllerStopPlayback:(id)arg1 {
    [self pictureInPictureControllerStopPlayback];
}

%new(v@:{CGSize=dd})
- (void)renderingViewSampleBufferFrameSizeDidChange:(CGSize)size {
    if (!IS_IOS_OR_NEWER(iOS_15_0) && size.width && size.height) {
        AVPictureInPictureController *avpip = [self valueForKey:@"_pictureInPictureController"];
        [avpip sampleBufferDisplayLayerRenderSizeDidChangeToSize:size];
    }
}

%new(v@:@)
- (void)appWillEnterForeground:(id)arg1 {
    if (!IS_IOS_OR_NEWER(iOS_15_0) && !LegacyPiP()) {
        AVPictureInPictureController *avpip = [self valueForKey:@"_pictureInPictureController"];
        [avpip sampleBufferDisplayLayerDidAppear];
    }
}

%new(v@:@)
- (void)appWillEnterBackground:(id)arg1 {
    if (!IS_IOS_OR_NEWER(iOS_15_0) && !LegacyPiP()) {
        AVPictureInPictureController *avpip = [self valueForKey:@"_pictureInPictureController"];
        [avpip sampleBufferDisplayLayerDidDisappear];
    }
}

%end

%hook MLDefaultPlayerViewFactory

- (MLAVPlayerLayerView *)AVPlayerViewForVideo:(MLVideo *)video playerConfig:(MLInnerTubePlayerConfig *)playerConfig {
    forcePictureInPicture([self valueForKey:@"_hotConfig"], YES);
    return %orig;
}

%end

#pragma mark - PiP Support, Backgroundable

%hook YTIHamplayerConfig

- (BOOL)enableBackgroundable {
    return YES;
}

%end

%hook YTIBackgroundOfflineSettingCategoryEntryRenderer

- (BOOL)isBackgroundEnabled {
    return YES;
}

%end

%hook YTBackgroundabilityPolicy

- (void)updateIsBackgroundableByUserSettings {
    %orig;
    [self setValue:@(YES) forKey:@"_backgroundableByUserSettings"];
}

%end

%hook YTSettingsSectionItemManager

- (YTSettingsSectionItem *)pictureInPictureSectionItem {
    forcePictureInPicture([self valueForKey:@"_hotConfig"], YES);
    return %orig;
}

- (YTSettingsSectionItem *)pictureInPictureSectionItem:(id)arg1 {
    forcePictureInPicture([self valueForKey:@"_hotConfig"], YES);
    return %orig;
}

%end

#pragma mark - Hacks

BOOL YTSingleVideo_isLivePlayback_override = NO;

%hook YTSingleVideo

- (BOOL)isLivePlayback {
    return YTSingleVideo_isLivePlayback_override ? NO : %orig;
}

%end

static YTHotConfig *getHotConfig(YTPlayerPIPController *self) {
    @try {
        return [self valueForKey:@"_hotConfig"];
    } @catch (id ex) {
        return [[self valueForKey:@"_config"] valueForKey:@"_hotConfig"];
    }
}

%hook YTPlayerPIPController

- (BOOL)canInvokePictureInPicture {
    forcePictureInPicture(getHotConfig(self), YES);
    YTSingleVideo_isLivePlayback_override = YES;
    BOOL value = %orig;
    YTSingleVideo_isLivePlayback_override = NO;
    return value;
}

- (BOOL)canEnablePictureInPicture {
    forcePictureInPicture(getHotConfig(self), YES);
    YTSingleVideo_isLivePlayback_override = YES;
    BOOL value = %orig;
    YTSingleVideo_isLivePlayback_override = NO;
    return value;
}

- (void)didStopPictureInPicture {
    FromUser = NO;
    %orig;
}

- (void)appWillResignActive:(id)arg1 {
    // If PiP button on, PiP doesn't activate on app resign unless it's from user
    BOOL hasPiPButton = UsePiPButton() || UseTabBarPiPButton();
    BOOL disablePiP = hasPiPButton && !FromUser;
    if (disablePiP) {
        MLPIPController *pip = [self valueForKey:@"_pipController"];
        [pip setValue:nil forKey:@"_pictureInPictureController"];
    } else {
        if (LegacyPiP())
            activatePiPBase(self, YES);
        %orig;
    }
}

%end

%hook YTSingleVideoController

- (void)playerStatusDidChange:(YTPlayerStatus *)playerStatus {
    %orig;
    PiPDisabled = NoMiniPlayerPiP() && playerStatus.visibility == 1;
}

%end

%hook AVPictureInPicturePlatformAdapter

- (BOOL)isSystemPictureInPicturePossible {
    return PiPDisabled ? NO : %orig;
}

%end

%hook YTIPlayabilityStatus

- (BOOL)isPlayableInBackground {
    return YES;
}

- (BOOL)isPlayableInPictureInPicture {
    return YES;
}

- (BOOL)hasPictureInPicture {
    return YES;
}

%end

#pragma mark - PiP Support, Binding

%hook YTAppModule

- (void)configureWithBinder:(GIMBindingBuilder *)binder {
    %orig;
    [[binder bindType:%c(MLPIPController)] initializedWith:^(id a) {
        MLPIPController *pip = [%c(MLPIPController) alloc];
        if ([pip respondsToSelector:@selector(initWithPlaceholderPlayerItemResourcePath:)])
            pip = [pip initWithPlaceholderPlayerItemResourcePath:PiPVideoPath];
        else if ([pip respondsToSelector:@selector(initWithPlaceholderPlayerItem:)])
            pip = [pip initWithPlaceholderPlayerItem:[AVPlayerItem playerItemWithURL:[NSURL URLWithString:PiPVideoPath]]];
        return pip;
    }];
}

%end

%hook YTIInnertubeResourcesIosRoot

- (GPBExtensionRegistry *)extensionRegistry {
    GPBExtensionRegistry *registry = %orig;
    [registry addExtension:[%c(YTIPictureInPictureRendererRoot) pictureInPictureRenderer]];
    return registry;
}

%end

%hook GoogleGlobalExtensionRegistry

- (GPBExtensionRegistry *)extensionRegistry {
    GPBExtensionRegistry *registry = %orig;
    [registry addExtension:[%c(YTIPictureInPictureRendererRoot) pictureInPictureRenderer]];
    return registry;
}

%end

NSBundle *YouPiPBundle() {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
        NSString *tweakBundlePath = [[NSBundle mainBundle] pathForResource:@"YouPiP" ofType:@"bundle"];
        if (tweakBundlePath)
            bundle = [NSBundle bundleWithPath:tweakBundlePath];
        else
            bundle = [NSBundle bundleWithPath:ROOT_PATH_NS(@"/Library/Application Support/YouPiP.bundle")];
    });
    return bundle;
}

%ctor {
    if (!TweakEnabled()) return;
    NSBundle *tweakBundle = YouPiPBundle();
    PiPVideoPath = [tweakBundle pathForResource:@"PiPPlaceholderAsset" ofType:@"mp4"];
    PiPIconPath = [tweakBundle pathForResource:@"yt-pip-overlay" ofType:@"png"];
    TabBarPiPIconPath = [tweakBundle pathForResource:@"yt-pip-tabbar" ofType:@"png"];
    %init;
}
