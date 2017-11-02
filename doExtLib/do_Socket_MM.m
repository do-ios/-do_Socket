//
//  do_Socket_MM.m
//  DoExt_MM
//
//  Created by @userName on @time.
//  Copyright (c) 2015年 DoExt. All rights reserved.
//

#import "do_Socket_MM.h"
#import "doScriptEngineHelper.h"
#import "doIScriptEngine.h"
#import "doInvokeResult.h"
#import "doJsonHelper.h"
#import "doIOHelper.h"
#import "doIPage.h"
#import "doIApp.h"
#import "doServiceContainer.h"
#import "doLogEngine.h"
#import "doJsonHelper.h"
#import "GCDAsyncSocket.h"

@interface do_Socket_MM()<GCDAsyncSocketDelegate,NSStreamDelegate>
@property(nonatomic,strong)NSString     *callBackName;
@property (nonatomic,strong) id<doIScriptEngine>        curScriptEngine;
@end

@implementation do_Socket_MM
{
    long dataTag;
    GCDAsyncSocket *_socket;
    NSInputStream *inputStream;
    dispatch_queue_t serialQueue;
    dispatch_semaphore_t semaphore;
}
#pragma mark - 注册属性（--属性定义--）
/*
 [self RegistProperty:[[doProperty alloc]init:@"属性名" :属性类型 :@"默认值" : BOOL:是否支持代码修改属性]];
 */
-(void)OnInit
{
    [super OnInit];
    //注册属性
    serialQueue = dispatch_queue_create("com.do.Socket", DISPATCH_QUEUE_SERIAL);
    semaphore = dispatch_semaphore_create(1);
}

//销毁所有的全局对象
-(void)Dispose
{
    //(self)类销毁时会调用递归调用该方法，在该类中主动生成的非原生的扩展对象需要主动调该方法使其销毁
    _socket.delegate = nil;
    if (_socket.isConnected) {
        [_socket disconnect];
    }
    _socket = nil;
}
#pragma mark -
#pragma mark - 同步异步方法的实现
//同步
- (void)close:(NSArray *)parms
{
    if ([_socket isConnected]) {
        _socket.delegate = nil;
        [_socket disconnect];
    }
    
    _socket = nil;
}
//异步
- (void)connect:(NSArray *)parms
{
    [self close:nil];
    //异步耗时操作，但是不需要启动线程，框架会自动加载一个后台线程处理这个函数
    NSDictionary *_dictParas = [parms objectAtIndex:0];
    //参数字典_dictParas
    self.curScriptEngine = [parms objectAtIndex:1];
    self.callBackName = [parms objectAtIndex:2];
    //自己的代码实现
    NSString *_socketIP= [doJsonHelper GetOneText:_dictParas :@"ip" :@""];
    NSString *_socketPort= [doJsonHelper GetOneText:_dictParas :@"port" :@""];
    if ((_socketIP != nil && ![_socketIP isEqualToString:@""]) && (_socketPort != nil && ![_socketPort isEqualToString:@""]))
    {
        NSError *error;
        _socket = [[GCDAsyncSocket alloc]initWithDelegate:self delegateQueue: serialQueue];
       [_socket connectToHost:_socketIP onPort:[_socketPort integerValue] error:&error];
        if (error) {
            doInvokeResult *result = [[doInvokeResult alloc] init];
            [result SetResultBoolean:false];
            [self.curScriptEngine Callback:self.callBackName :result];
            [[doServiceContainer Instance].LogEngine WriteError:[NSException exceptionWithName:@"do_Socket" reason:error.description userInfo:nil] :nil];
            return;
        }
        
    }else {
        doInvokeResult *result = [[doInvokeResult alloc] init];
        [result SetResultBoolean:false];
        [self.curScriptEngine Callback:self.callBackName :result];
        return;
    }
}
- (void)send:(NSArray *)parms
{
    if (_socket == nil) {
        [[doServiceContainer Instance].LogEngine WriteError:nil :@"socket未连接或已关闭连接，请先开启连接"];
        return;
    }
    //异步耗时操作，但是不需要启动线程，框架会自动加载一个后台线程处理这个函数
    NSDictionary *_dictParas = [parms objectAtIndex:0];
    //参数字典_dictParas
    self.curScriptEngine = [parms objectAtIndex:1];
    self.callBackName = [parms objectAtIndex:2];
    
    //自己的代码实现
    NSString *type = [doJsonHelper GetOneText:_dictParas :@"type" :@""].lowercaseString;
    NSString *_msg = _dictParas[@"content"];
    NSData *contentData;
    if ([type isEqualToString:@"file"]) {
        NSString *filePath = [doIOHelper GetLocalFileFullPath:self.curScriptEngine.CurrentPage.CurrentApp :_msg];
        [self setUpStreamForFile:filePath];
        return;//文件单独处理
    }
    else if([type isEqualToString:@"gbk"])
    {
        NSStringEncoding enc = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
        contentData = [_msg dataUsingEncoding:enc];
    }
    else if([type isEqualToString:@"utf-8"])
    {
        contentData = [[NSData alloc]initWithBytes:[_msg UTF8String] length:[_msg lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];
    }
    else if ([type isEqualToString:@"hex"])
    {
        contentData = [self convertHexStrToData:_msg];
    }
    else
    {
        [[doServiceContainer Instance].LogEngine WriteError:nil :@"编码格式错误"];
        return;
    }
    [_socket writeData:contentData withTimeout:-1 tag:dataTag];
    dataTag ++;
}
#pragma mark - 私有方法
- (NSData *)convertHexStrToData:(NSString *)str {
    if (!str || [str length] == 0) {
        return nil;
    }
    
    NSMutableData *hexData = [[NSMutableData alloc] initWithCapacity:8];
    NSRange range;
    if ([str length] % 2 == 0) {
        range = NSMakeRange(0, 2);
    } else {
        range = NSMakeRange(0, 1);
    }
    for (NSInteger i = range.location; i < [str length]; i += 2) {
        unsigned int anInt;
        NSString *hexCharStr = [str substringWithRange:range];
        NSScanner *scanner = [[NSScanner alloc] initWithString:hexCharStr];
        
        [scanner scanHexInt:&anInt];
        NSData *entity = [[NSData alloc] initWithBytes:&anInt length:1];
        [hexData appendData:entity];
        
        range.location += range.length;
        range.length = 2;
    }
    return hexData;
}

- (void)setUpStreamForFile:(NSString *)path
{
    inputStream = [[NSInputStream alloc] initWithFileAtPath:path];
    inputStream.delegate = self;
    [inputStream scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    [inputStream open];
    
}
//得到二进制字符串
-(NSString *)getHexStr:(NSData *)data
{
    Byte *testByte = (Byte *)[data bytes];
    NSString *hexStr=@"";
    for(int i=0;i<[data length];i++)
    {
        NSString *newHexStr = [NSString stringWithFormat:@"%x",testByte[i]&0xff];///16进制数
        if([newHexStr length]==1)
        {
            hexStr = [NSString stringWithFormat:@"%@0%@",hexStr,newHexStr];
        }
        else
        {
            hexStr = [NSString stringWithFormat:@"%@%@",hexStr,newHexStr];
        }
    }
    return hexStr;
}
#pragma mark - inputStreame代理回调
- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
    switch (eventCode) {
        case NSStreamEventEndEncountered:
        {
            [aStream removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
            break;
        }
        case NSStreamEventHasBytesAvailable:
        {
            dispatch_async(serialQueue, ^{
                dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
                NSMutableData *fileData = [NSMutableData data];//fileData
                uint8_t buf[4096];
                unsigned long len = 0;
                len = [(NSInputStream *)aStream read:buf maxLength:4096];  // 读取数据
                if (len) {
                    [fileData appendBytes:(const void *)buf length:len];
                    [_socket writeData:fileData withTimeout:-1 tag:0];
                }
                dispatch_semaphore_signal(semaphore);
            });
            
            
            break;
        }
            
    }
}
#pragma mark - socket回调

- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port
{
    //回调函数名_callbackName
    doInvokeResult *_invokeResult = [[doInvokeResult alloc] init];
    //_invokeResult设置返回值
    [_invokeResult SetResultBoolean:YES];
    [self.curScriptEngine Callback:self.callBackName :_invokeResult];
    [_socket readDataWithTimeout:-1 tag:dataTag];
}
- (void)socketDidCloseReadStream:(GCDAsyncSocket *)sock
{
    NSLog(@"close");
}
- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err
{
    doInvokeResult *_invokeResult = [[doInvokeResult alloc] init];
    //_invokeResult设置返回值
    [_invokeResult SetResultBoolean:NO];
    [self.curScriptEngine Callback:self.callBackName :_invokeResult];
    if (err) {
        NSMutableDictionary *node = [NSMutableDictionary dictionary];
        NSString *localizedDescription = err.localizedDescription;
        if (!localizedDescription || localizedDescription.length==0) {
            localizedDescription = @"close";
        }
        [node setObject:@(err.code) forKey:@"key"];
        [node setObject:localizedDescription forKey:@"message"];
        doInvokeResult *invokeResult = [[doInvokeResult alloc]init];
        [invokeResult SetResultNode:node];
        [self.EventCenter FireEvent:@"error" :invokeResult];
        [_socket disconnect];
        _socket = nil;
    }
    
}
//- sock
// 发送成功回到
- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag
{
    doInvokeResult *_invokeResult = [[doInvokeResult alloc] init];
    //_invokeResult设置返回值
    [_invokeResult SetResultBoolean:YES];
    [self.curScriptEngine Callback:self.callBackName :_invokeResult];
}
//收到消息回调
- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag
{
    doInvokeResult *invokeResult = [[doInvokeResult alloc]init];
    [invokeResult SetResultValue:[self getHexStr:data]];
    [self.EventCenter FireEvent:@"receive" :invokeResult];
    [_socket readDataWithTimeout:-1 tag:dataTag];
}

@end
