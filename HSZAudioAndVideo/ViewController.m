//
//  ViewController.m
//  HSZAudioAndVideo
//
//  Created by Hank on 2021/6/21.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>

@interface ViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate>

@property(nonatomic,strong)UILabel *cLabel;
///捕捉会话，用于输入输出设备之间的数据传递
@property (nonatomic, strong) AVCaptureSession *cCapturesession;
///捕捉输入
@property (nonatomic, strong) AVCaptureDeviceInput *cCaptureDeviceInput;
///捕捉输出
@property (nonatomic, strong) AVCaptureVideoDataOutput *cCaptureDataOurput;
///预览图层
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *cPreviewLayer;

@end

@implementation ViewController
{
    ///帧ID
    int fremeID;
    ///捕获队列
    dispatch_queue_t cCaptureQueue;
    ///编码队列
    dispatch_queue_t cEncodeQueue;
    ///编码session
    VTCompressionSessionRef cEncodeingSession;
    ///编码格式
    CMFormatDescriptionRef format;
    NSFileHandle *fileHandle;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor whiteColor];
    [self loadMainView];
    // Do any additional setup after loading the view.
}

- (void)loadMainView
{
    //基础UI实现
    UILabel *cLabel = [[UILabel alloc]initWithFrame:CGRectMake(20, 20, 200, 100)];
    cLabel.text = @"采集和H.264硬编码";
    cLabel.textColor = [UIColor redColor];
    [self.view addSubview:cLabel];
    self.cLabel = cLabel;
    
    UIButton *cButton = [[UIButton alloc]initWithFrame:CGRectMake(200, 20, 100, 100)];
    [cButton setTitle:@"录制和H264编码" forState:UIControlStateNormal];
    [cButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [cButton setBackgroundColor:[UIColor orangeColor]];
    [cButton addTarget:self action:@selector(buttonClick:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:cButton];
}

#pragma mark - Private
///开始捕捉
- (void)startCapture
{
    self.cCapturesession = [[AVCaptureSession alloc] init];
    ///设置捕捉分辨率
    self.cCapturesession.sessionPreset = AVCaptureSessionPreset640x480;
    //使用函数dispath_get_global_queue去得到队列
    cCaptureQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    cEncodeQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    AVCaptureDevice *inputCamera = nil;
    //获取iPhone视频捕捉的设备，例如前置摄像头、后置摄像头......
    AVCaptureDeviceDiscoverySession *devicesSession = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera] mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified];//[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in devicesSession.devices) {
        //拿到后置摄像头
        if ([device position] == AVCaptureDevicePositionBack) {
            inputCamera = device;
        }
    }
    
    //将捕捉设备 封装成 AVCaptureDeviceInput 对象
    self.cCaptureDeviceInput = [[AVCaptureDeviceInput alloc] initWithDevice:inputCamera error:nil];
    //判断是否能加入后置摄像头作为输入设备
    if ([self.cCapturesession canAddInput:self.cCaptureDeviceInput]) {
        //将设备添加到会话中
        [self.cCapturesession addInput:self.cCaptureDeviceInput];
    }
    
    //配置输出
    self.cCaptureDataOurput = [[AVCaptureVideoDataOutput alloc] init];
    //设置丢弃最后的video frame 为NO
    [self.cCaptureDataOurput setAlwaysDiscardsLateVideoFrames:NO];
    //设置video的视频捕捉的像素点压缩方式为 420
    NSDictionary *videoSettingDict = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange] forKey:(id)kCVPixelBufferPixelFormatTypeKey];
    [self.cCaptureDataOurput setVideoSettings:videoSettingDict];
    
    //设置捕捉代理 和 捕捉队列
    [self.cCaptureDataOurput setSampleBufferDelegate:self queue:self->cCaptureQueue];
    //判断是否能添加输出
    if ([self.cCapturesession canAddOutput:self.cCaptureDataOurput]) {
        //添加输出
        [self.cCapturesession addOutput:self.cCaptureDataOurput];
    }
    
    //创建连接
    AVCaptureConnection *connection = [self.cCaptureDataOurput connectionWithMediaType:AVMediaTypeVideo];
    //设置连接的方向
    [connection setVideoOrientation:AVCaptureVideoOrientationPortrait];
    
    //初始化图层
    self.cPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.cCapturesession];
    //设置视频重力
    [self.cPreviewLayer setVideoGravity:AVLayerVideoGravityResizeAspect];
    //设置图层的frame
    [self.cPreviewLayer setFrame:self.view.bounds];
    //添加图层
    [self.view.layer addSublayer:self.cPreviewLayer];
    
    //文件写入沙盒
    NSString *filePath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES)lastObject]stringByAppendingPathComponent:@"hsz_video.h264"];
    //先移除已存在的文件
    [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
    
    //新建文件
    BOOL createFile = [[NSFileManager defaultManager] createFileAtPath:filePath contents:nil attributes:nil];
    if (!createFile) {
        
        NSLog(@"create file failed");
    }else
    {
        NSLog(@"create file success");

    }
    
    NSLog(@"filePaht = %@",filePath);
    fileHandle = [NSFileHandle fileHandleForWritingAtPath:filePath];
    
    //初始化videoToolbBox
    [self initVideoToolBox];
    
    //开始捕捉
    [self.cCapturesession startRunning];
}

///初始化videoToolBox
- (void)initVideoToolBox
{
    dispatch_async(cEncodeQueue, ^{
        self->fremeID = 0;
        int width = 480,height = 640;
        //1.调用VTCompressionSessionCreate创建编码session
        //参数1：NULL 分配器,设置NULL为默认分配
        //参数2：width
        //参数3：height
        //参数4：编码类型,如kCMVideoCodecType_H264
        //参数5：NULL encoderSpecification: 编码规范。设置NULL由videoToolbox自己选择
        //参数6：NULL sourceImageBufferAttributes: 源像素缓冲区属性.设置NULL不让videToolbox创建,而自己创建
        //参数7：NULL compressedDataAllocator: 压缩数据分配器.设置NULL,默认的分配
        //参数8：回调  当VTCompressionSessionEncodeFrame被调用压缩一次后会被异步调用.注:当你设置NULL的时候,你需要调用VTCompressionSessionEncodeFrameWithOutputHandler方法进行压缩帧处理,支持iOS9.0以上
        //参数9：outputCallbackRefCon: 回调客户定义的参考值
        //参数10：compressionSessionOut: 编码会话变量
        OSStatus status = VTCompressionSessionCreate(NULL, width, height, kCMVideoCodecType_H264, NULL, NULL, NULL, didCompressH264, (__bridge void *)self, &self->cEncodeingSession);
        NSLog(@"H264:VTCompressionSessionCreate:%d",(int)status);
        if (status != 0) {
            NSLog(@"H264:Unable to create a H264 session");
            return ;
        }
        //设置实时编码输出（避免延迟）
        VTSessionSetProperty(self->cEncodeingSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
        VTSessionSetProperty(self->cEncodeingSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_AutoLevel);
        
        //是否产生B帧(因为B帧在解码时并不是必要的,是可以抛弃B帧的)
        VTSessionSetProperty(self->cEncodeingSession, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse);
        //设置关键帧（GOPsize）间隔，GOP太小的话图像会模糊
        int frameInterval = 10;
        CFNumberRef fameIntervalRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &frameInterval);
        VTSessionSetProperty(self->cEncodeingSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, fameIntervalRef);
        
        //设置期望帧率，不是实际帧率
        int fps = 10;
        CFNumberRef fpsRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &fps);
        VTSessionSetProperty(self->cEncodeingSession, kVTCompressionPropertyKey_ExpectedFrameRate, fpsRef);
        
        //码率的理解：码率大了话就会非常清晰，但同时文件也会比较大。码率小的话，图像有时会模糊，但也勉强能看
        //码率计算公式，参考印象笔记
        //设置码率、上限、单位是bps
        int bitRate = width * height * 3 * 4 * 8;
        CFNumberRef bitRateRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &bitRate);
        VTSessionSetProperty(self->cEncodeingSession, kVTCompressionPropertyKey_AverageBitRate, bitRateRef);
        
        //设置码率，均值，单位是byte
        int bigRateLimit = width * height * 3 * 4;
        CFNumberRef bitRateLimitRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &bigRateLimit);
        VTSessionSetProperty(self->cEncodeingSession, kVTCompressionPropertyKey_DataRateLimits, bitRateLimitRef);
        
        //开始编码
        VTCompressionSessionPrepareToEncodeFrames(self->cEncodeingSession);
        
    });
}

//编码完成回调
/*
 1.H264硬编码完成后，回调VTCompressionOutputCallback
 2.将硬编码成功的CMSampleBuffer转换成H264码流，通过网络传播
 3.解析出参数集SPS & PPS，加上开始码组装成 NALU。提现出视频数据，将长度码转换为开始码，组成NALU，将NALU发送出去。
 */
void didCompressH264(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus status,VTEncodeInfoFlags infoFlags,CMSampleBufferRef sampleBuffer)
{
    NSLog(@"didCompressH264 called with status %d infoFlags %d",(int)status,(int)infoFlags);
    //状态错误
    if (status != 0) {
        return;
    }
    //没准备好
    if (!CMSampleBufferDataIsReady(sampleBuffer)) {
        NSLog(@"didCompressH264 data is not ready");
        return;
    }
    
    ViewController *encoder = (__bridge  ViewController*)outputCallbackRefCon;
    
    //判断当前帧是否为关键帧
    /* 分步骤判断
    CFArrayRef array = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true);
    CFDictionaryRef dic = CFArrayGetValueAtIndex(array, 0);
    bool isKeyFrame = !CFDictionaryContainsKey(dic, kCMSampleAttachmentKey_NotSync);
    */
    CFArrayRef array = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true);
    CFDictionaryRef theDict = CFArrayGetValueAtIndex(array, 0);
    bool keyFrame = !CFDictionaryContainsKey(theDict, kCMSampleAttachmentKey_NotSync);
    //判断当前帧是否为关键帧
    //获取sps & pps 数据 只获取1次，保存在h264文件开头的第一帧中
    //sps(sample per second 采样次数/s),是衡量模数转换（ADC）时采样速率的单位
    //pps()
    if (keyFrame) {
        //图像存储方式，编码器等格式描述
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
        //sps
        size_t sparameterSetSize,sparameterSetCount;
        const uint8_t *sparameterSet;
        OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sparameterSet, &sparameterSetSize, &sparameterSetCount, 0);

        if (statusCode == noErr) {
            //获取pps
            size_t pparameterSetSize,pparameterSetCount;
            const uint8_t *pparameterSet;
            //从第一个关键帧获取sps & pps
            OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pparameterSet, &pparameterSetSize, &pparameterSetCount, 0);
            
            //获取H264参数集合中的SPS和PPS
            if (statusCode == noErr) {
                //Found pps & sps
                NSData *sps = [NSData dataWithBytes:sparameterSet length:sparameterSetSize];
                NSData *pps = [NSData dataWithBytes:pparameterSet length:pparameterSetSize];
                
                if (encoder) {
                    [encoder gotSpsPps:sps pps:pps];
                }
            }
            
            //Found pps & sps
//            NSData *sps = [NSData dataWithBytes:sparameterSet length:sparameterSetSize];
//            NSData *pps = [NSData dataWithBytes:pp length:<#(NSUInteger)#>];
        }
    }
    
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t length,totalLength;
    char *dataPointer;
    OSStatus statusCodeRet = CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &dataPointer);
    if (statusCodeRet == noErr) {
        size_t bufferOffset = 0;
        //返回的nalu数据前4个字节不是001的startcode,而是大端模式的帧长度length
        static const int AVCCHeaderLength = 4;
        //循环获取nalu数据
        while (bufferOffset < totalLength - AVCCHeaderLength) {
            uint32_t NALUnitLength = 0;
            //读取 一单元长度的 nalu
            memcpy(&NALUnitLength, dataPointer + bufferOffset, AVCCHeaderLength);
            //从大端模式转换为系统端模式
            NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);
            //获取nalu数据
            NSData *data = [[NSData alloc] initWithBytes:(dataPointer + bufferOffset + AVCCHeaderLength)  length:NALUnitLength];
            //将nalu数据写入到文件
            [encoder gotEncodedData:data isKeyFrame:keyFrame];
            //move to the next NAL unit in the block buffer
            //读取下一个nalu 一次回调可能包含多个nalu数据
            bufferOffset += AVCCHeaderLength + NALUnitLength;
        }
    }
}

//第一帧写入 sps & pps
- (void)gotSpsPps:(NSData*)sps pps:(NSData*)pps
{
    NSLog(@"gotSpsPp %d %d",(int)[sps length],(int)[pps length]);
    const char bytes[] = "\x00\x00\x00\x01";
    size_t length = (sizeof bytes) - 1;
    NSData *ByteHeader = [NSData dataWithBytes:bytes length:length];
    [fileHandle writeData:ByteHeader];
    [fileHandle writeData:sps];
    [fileHandle writeData:ByteHeader];
    [fileHandle writeData:pps];
}

- (void)gotEncodedData:(NSData*)data isKeyFrame:(BOOL)isKeyFrame
{
    NSLog(@"gotEncodeData %d",(int)[data length]);
    if (fileHandle != NULL) {
        //添加4个字节的H264 协议 start code 分割符
        //一般来说编码器编出的首帧数据为PPS & SPS
        //H264编码时，在每个NAL前添加起始码 0x000001,解码器在码流中检测起始码，当前NAL结束。
        /*
         为了防止NAL内部出现0x000001的数据，h.264又提出'防止竞争 emulation prevention"机制，在编码完一个NAL时，如果检测出有连续两个0x00字节，就在后面插入一个0x03。当解码器在NAL内部检测到0x000003的数据，就把0x03抛弃，恢复原始数据。
         
         总的来说H264的码流的打包方式有两种,一种为annex-b byte stream format 的格式，这个是绝大部分编码器的默认输出格式，就是每个帧的开头的3~4个字节是H264的start_code,0x00000001或者0x000001。
         另一种是原始的NAL打包格式，就是开始的若干字节（1，2，4字节）是NAL的长度，而不是start_code,此时必须借助某个全局的数据来获得编 码器的profile,level,PPS,SPS等信息才可以解码。
         
         */
        const char bytes[] ="\x00\x00\x00\x01";
        //长度
        size_t length = (sizeof bytes) - 1;
        //头字节
        NSData *ByteHeader = [NSData dataWithBytes:bytes length:length];
        
        //写入头字节
        [fileHandle writeData:ByteHeader];
        
        //写入H264数据
        [fileHandle writeData:data];
    }
}

//停止捕捉
- (void)stopCapture
{
    //停止捕捉
    [self.cCapturesession stopRunning];
    //移除预览图层
    [self.cPreviewLayer removeFromSuperlayer];
    //结束videoToolbBox
    [self endVideoToolBox];
    //关闭文件
    [fileHandle closeFile];
    fileHandle = nil;
}

//结束VideoToolBox
-(void)endVideoToolBox
{
    VTCompressionSessionCompleteFrames(cEncodeingSession, kCMTimeInvalid);
    VTCompressionSessionInvalidate(cEncodeingSession);
    CFRelease(cEncodeingSession);
    cEncodeingSession = NULL;
}

///获取视频流开始编码
- (void)encode:(CMSampleBufferRef)sampleBuffer
{
    //拿到每一帧未编码数据
    CVImageBufferRef imageBuffer = (CVImageBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
    //设置帧时间，如果不设置会导致时间轴过长。
    CMTime presentationTimeStamp = CMTimeMake(self->fremeID++, 100);
    VTEncodeInfoFlags flags;
    //参数1：编码会话变量
    //参数2：未编码数据
    //参数3：获取到的这个sample buffer数据的展示时间戳。每一个传给这个session的时间戳都要大于前一个展示时间戳.
    //参数4：对于获取到sample buffer数据,这个帧的展示时间.如果没有时间信息,可设置kCMTimeInvalid.
    //参数5：frameProperties: 包含这个帧的属性.帧的改变会影响后边的编码帧.
    //参数6：ourceFrameRefCon: 回调函数会引用你设置的这个帧的参考值.
    //参数7：infoFlagsOut: 指向一个VTEncodeInfoFlags来接受一个编码操作.如果使用异步运行,kVTEncodeInfo_Asynchronous被设置；同步运行,kVTEncodeInfo_FrameDropped被设置；设置NULL为不想接受这个信息.
    OSStatus statusCode = VTCompressionSessionEncodeFrame(self->cEncodeingSession, imageBuffer, presentationTimeStamp, kCMTimeInvalid, NULL, NULL, &flags);
    if (statusCode != noErr) {
        NSLog(@"H.264:VTCompressionSessionEncodeFrame faild with %d",(int)statusCode);
        VTCompressionSessionInvalidate(cEncodeingSession);
        CFRelease(cEncodeingSession);
        cEncodeingSession = NULL;
        return;
    }
    NSLog(@"H264:VTCompressionSessionEncodeFrame Success");
}

#pragma mark - Event
///点击事件
- (void)buttonClick:(UIButton *)button
{
    ///判断_cCapturesession 和 _cCapturesession是否正在捕捉
    if (!self.cCapturesession || !self.cCapturesession.isRunning) {
        //修改按钮状态
        [button setTitle:@"停止录制" forState:UIControlStateNormal];
        [self startCapture];
    }
    else
    {
        [button setTitle:@"开始录制" forState:UIControlStateNormal];
        [self stopCapture];
    }
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate
//AV Foundation 获取到视频流
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    NSLog(@"didOutputSampleBuffer:%@",sampleBuffer);
    //开始视频录制，获取到摄像头的视频帧，传入encode 方法中
    dispatch_sync(cEncodeQueue, ^{
        [self encode:sampleBuffer];
    });
}

@end
