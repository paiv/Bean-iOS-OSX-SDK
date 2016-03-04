#import "BeanContainer.h"
#import "StatelessUtils.h"
#import "PTDBean+Protected.h"

@interface BeanContainer () <PTDBeanManagerDelegate, PTDBeanExtendedDelegate>

#pragma mark Local state set in constructor

@property (nonatomic, strong) XCTestCase *testCase;
@property (nonatomic, strong) BOOL (^beanFilter)(PTDBean *);
@property (nonatomic, strong) NSDictionary *options;
@property (nonatomic, strong) PTDBeanManager *beanManager;
@property (nonatomic, strong) XCTestExpectation *beanManagerPoweredOn;
@property (nonatomic, strong) PTDBean *bean;

#pragma mark Test expectations and delegate callback values

@property (nonatomic, strong) XCTestExpectation *beanDiscovered;
@property (nonatomic, strong) XCTestExpectation *beanConnected;
@property (nonatomic, strong) XCTestExpectation *beanDisconnected;
@property (nonatomic, strong) XCTestExpectation *beanDidUpdateLedColor;
@property (nonatomic, strong) NSColor *ledColor;
@property (nonatomic, strong) XCTestExpectation *beanDidProgramArduino;
@property (nonatomic, strong) NSError *programArduinoError;
@property (nonatomic, strong) XCTestExpectation *beanCompletedFirmwareUploadOfSingleImage;
@property (nonatomic, strong) NSString *imagePath;
@property (nonatomic, strong) XCTestExpectation *beanCompletedFirmwareUpload;
@property (nonatomic, strong) NSError *firmwareUploadError;

#pragma mark Helpers to prevent spamming the debug log

@property (nonatomic, assign) NSInteger lastPercentagePrinted;

@end

@implementation BeanContainer

#pragma mark - Constructors

+ (BeanContainer *)containerWithTestCase:(XCTestCase *)testCase andBeanFilter:(BOOL (^)(PTDBean *bean))filter andOptions:(NSDictionary *)options
{
    return [[BeanContainer alloc] initWithTestCase:testCase andBeanFilter:filter andOptions:options];
}

+ (BeanContainer *)containerWithTestCase:(XCTestCase *)testCase andBeanNamePrefix:(NSString *)prefix andOptions:(NSDictionary *)options
{
    return [[BeanContainer alloc] initWithTestCase:testCase andBeanFilter:^BOOL(PTDBean *bean) {
        return [bean.name hasPrefix:prefix];
    } andOptions:options];
}

- (instancetype)initWithTestCase:(XCTestCase *)testCase andBeanFilter:(BOOL (^)(PTDBean *bean))filter andOptions:(NSDictionary *)options
{
    self = [super init];
    if (!self) return nil;

    _lastPercentagePrinted = -1;
    
    _testCase = testCase;
    _beanFilter = filter;
    _options = options;
    
    _beanManager = [[PTDBeanManager alloc] initWithDelegate:self];
    if (_beanManager.state != BeanManagerState_PoweredOn) {
        _beanManagerPoweredOn = [testCase expectationWithDescription:@"Bean Manager powered on"];
        [testCase waitForExpectationsWithTimeout:5 handler:nil];
        _beanManagerPoweredOn = nil;
    }
    
    _beanDiscovered = [testCase expectationWithDescription:@"Bean with prefix found"];
    
    NSError *error;
    [_beanManager startScanningForBeans_error:&error];
    if (error) return nil;
    
    [testCase waitForExpectationsWithTimeout:10 handler:nil];
    self.beanDiscovered = nil;
    if (!_bean) return nil;
    
    [_beanManager stopScanningForBeans_error:&error];
    if (error) return nil;
    
    return self;
}

#pragma mark - Interact with Bean

- (BOOL)connect
{
    self.beanConnected = [self.testCase expectationWithDescription:@"Bean connected"];

    NSError *error;
    self.bean.delegate = self;
    [self.beanManager connectToBean:self.bean error:&error];
    if (error) return NO;

    NSTimeInterval defaultTimeout = 20;
    NSTimeInterval override = [(NSNumber *)self.options[@"connectTimeout"] integerValue];
    NSTimeInterval timeout = override ? override : defaultTimeout;
    [self.testCase waitForExpectationsWithTimeout:timeout handler:nil];
    self.beanConnected = nil;

    return (self.bean.state == BeanState_ConnectedAndValidated);
}

- (BOOL)disconnect
{
    self.beanDisconnected = [self.testCase expectationWithDescription:@"Bean connected"];

    NSError *error;
    [self.beanManager disconnectBean:self.bean error:&error];
    if (error) return NO;

    [self.testCase waitForExpectationsWithTimeout:10 handler:nil];
    self.beanDisconnected = nil;
    return (self.bean.state != BeanState_ConnectedAndValidated);
}

- (BOOL)blinkWithColor:(NSColor *)color
{
    self.beanDidUpdateLedColor = [self.testCase expectationWithDescription:@"Bean LED blinked"];
    [self.bean setLedColor:color];

    [self.bean readLedColor];
    [self.testCase waitForExpectationsWithTimeout:10 handler:nil];
    self.beanDidUpdateLedColor = nil;

    NSColor *black = [NSColor colorWithRed:0 green:0 blue:0 alpha:1];
    [self.bean setLedColor:black];
    [StatelessUtils delayTestCase:self.testCase forSeconds:1];

    return [self.ledColor isEqualTo:color];
}

- (BOOL)uploadSketch:(NSString *)hexName
{
    NSData *imageHex = [StatelessUtils bytesFromIntelHexResource:hexName usingBundleForClass:[self class]];
    self.beanDidProgramArduino = [self.testCase expectationWithDescription:@"Sketch uploaded to Bean"];

    [self.bean programArduinoWithRawHexImage:imageHex andImageName:hexName];
    [self.testCase waitForExpectationsWithTimeout:120 handler:nil];
    self.beanDidProgramArduino = nil;

    return !self.programArduinoError;
}

- (BOOL)updateFirmware
{
    NSArray *imagePaths = [StatelessUtils firmwareImagesFromResource:@"Firmware Images"];
    self.beanCompletedFirmwareUpload = [self.testCase expectationWithDescription:@"Firmware updated for Bean"];
    
    [self.bean updateFirmwareWithImages:imagePaths];
    [self.testCase waitForExpectationsWithTimeout:480 handler:nil];
    self.beanCompletedFirmwareUpload = nil;
    
    return !self.firmwareUploadError;
}

- (BOOL)updateFirmwareOnce
{
    NSArray *imagePaths = [StatelessUtils firmwareImagesFromResource:@"Firmware Images"];
    NSString *desc = @"Single firmware image uploaded to Bean";
    self.beanCompletedFirmwareUploadOfSingleImage = [self.testCase expectationWithDescription:desc];
    
    [self.bean updateFirmwareWithImages:imagePaths];
    [self.testCase waitForExpectationsWithTimeout:120 handler:nil];
    self.beanCompletedFirmwareUploadOfSingleImage = nil;
    
    return !self.firmwareUploadError;
}

- (BOOL)cancelFirmwareUpdate
{
    NSString *desc = @"Firmware update cancelled without error";
    self.beanCompletedFirmwareUpload = [self.testCase expectationWithDescription:desc];

    [self.bean cancelFirmwareUpdate];
    [self.testCase waitForExpectationsWithTimeout:10 handler:nil];
    self.beanCompletedFirmwareUpload = nil;
    
    return !self.firmwareUploadError;
}

#pragma mark - Helpers that depend on BeanContainer state

- (void)printProgressTimeLeft:(NSNumber *)seconds withPercentage:(NSNumber *)percentageComplete
{
    NSInteger percentage = [percentageComplete floatValue] * 100;
    if (percentage != self.lastPercentagePrinted) {
        self.lastPercentagePrinted = percentage;
        NSLog(@"Upload progress: %ld%%, %ld seconds remaining", percentage, [seconds integerValue]);
    }
}

#pragma mark - PTDBeanManagerDelegate

- (void)beanManagerDidUpdateState:(PTDBeanManager *)beanManager
{
    if (beanManager.state != BeanManagerState_PoweredOn) return;
    [self.beanManagerPoweredOn fulfill];
}

- (void)beanManager:(PTDBeanManager *)beanManager didDiscoverBean:(PTDBean *)bean error:(NSError *)error
{
    if (!self.beanFilter(bean)) return;
    if (!self.beanDiscovered) return;

    self.bean = bean;
    [self.beanDiscovered fulfill];
}

- (void)beanManager:(PTDBeanManager *)beanManager didConnectBean:(PTDBean *)bean error:(NSError *)error
{
    if (![bean isEqualToBean:self.bean]) return;
    if (!self.beanConnected) return;

    [self.beanConnected fulfill];
}

- (void)beanManager:(PTDBeanManager *)beanManager didDisconnectBean:(PTDBean *)bean error:(NSError *)error
{
    if (![bean isEqualToBean:self.bean]) return;
    if (!self.beanDisconnected) return;

    [self.beanDisconnected fulfill];
}

#pragma mark - PTDBeanDelegate

- (void)bean:(PTDBean *)bean didUpdateLedColor:(NSColor *)color
{
    if (![bean isEqualToBean:self.bean]) return;
    if (!self.beanDidUpdateLedColor) return;

    self.ledColor = color;
    [self.beanDidUpdateLedColor fulfill];
}

- (void)bean:(PTDBean *)bean ArduinoProgrammingTimeLeft:(NSNumber *)seconds withPercentage:(NSNumber *)percentageComplete
{
    [self printProgressTimeLeft:seconds withPercentage:percentageComplete];
}

- (void)bean:(PTDBean *)bean firmwareUploadTimeLeft:(NSNumber *)seconds withPercentage:(NSNumber *)percentageComplete
{
    [self printProgressTimeLeft:seconds withPercentage:percentageComplete];
}

- (void)bean:(PTDBean *)bean didProgramArduinoWithError:(NSError *)error
{
    if (![bean isEqualToBean:self.bean]) return;
    if (!self.beanDidProgramArduino) return;

    self.programArduinoError = error;
    [self.beanDidProgramArduino fulfill];
}

- (void)bean:(PTDBean *)bean completedFirmwareUploadOfSingleImage:(NSString *)imagePath
{
    if (![bean isEqualToBean:self.bean]) return;
    if (!self.beanCompletedFirmwareUploadOfSingleImage) return;

    self.imagePath = imagePath;
    [self.beanCompletedFirmwareUploadOfSingleImage fulfill];
}

- (void)bean:(PTDBean *)bean completedFirmwareUploadWithError:(NSError *)error
{
    if (![bean isEqualToBean:self.bean]) return;
    if (!self.beanCompletedFirmwareUpload) return;
    
    self.firmwareUploadError = error;
    [self.beanCompletedFirmwareUpload fulfill];
}

- (void)beanFoundWithIncompleteFirmware:(PTDBean *)bean
{
    NSLog(@"Refetching firmware images and restarting update process");
    NSArray *imagePaths = [StatelessUtils firmwareImagesFromResource:@"Firmware Images"];
    [self.bean updateFirmwareWithImages:imagePaths];
}

@end