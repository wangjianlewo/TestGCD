//
//  ViewController.m
//  TestGCD
//
//  Created by eunice on 2018/3/29.
//

#import "ViewController.h"
#import <AssetsLibrary/AssetsLibrary.h>
@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    [self testTimer];
}
#pragma mark - 10秒后执行某个任务
- (void)testAfterDo
{
    NSLog(@"begin %@",[NSThread currentThread]);
    
    dispatch_block_t block1 = dispatch_block_create(0, ^{
        NSLog(@"5秒后执行block1 %@",[NSThread currentThread]);
    });
    dispatch_block_t block2 = dispatch_block_create(0, ^{
        NSLog(@"10秒后执行block2 %@",[NSThread currentThread]);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(),block1 );
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)), dispatch_get_main_queue(),block2 );

    dispatch_block_cancel(block1);//ios8之后支持
    
    NSLog(@"end %@",[NSThread currentThread]);
}

#pragma mark - GCD 实现一个timer
- (void)testTimer
{
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(0, 0));
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC, 1 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer, ^{
        NSLog(@"timer 开始执行，%@",timer);
        dispatch_source_cancel(timer);//ios4之后支持
    });
    //timer被取消时，可以设置回调方法
    dispatch_source_set_cancel_handler(timer, ^{
        NSLog(@"此timer被取消了，%@",timer);
    });
    dispatch_resume(timer);
}

#pragma mark - 任务依赖
- (void)testDependency
{
    NSLog(@"begin %@",[NSThread currentThread]);

    //同dispatch_queue_create函数生成的concurrent Dispatch Queue队列一起使用
    dispatch_queue_t queue = dispatch_queue_create("12312312", DISPATCH_QUEUE_CONCURRENT);
    
    dispatch_async(queue, ^{
        sleep(6.0);
        NSLog(@"----1-----%@", [NSThread currentThread]);
    });
    dispatch_async(queue, ^{
        sleep(4.0);
        NSLog(@"----2-----%@", [NSThread currentThread]);
    });
    
    dispatch_barrier_async(queue, ^{
        NSLog(@"----barrier-----%@", [NSThread currentThread]);
    });
    
    dispatch_async(queue, ^{
        NSLog(@"----3-----%@", [NSThread currentThread]);
    });
  
    NSLog(@"end %@",[NSThread currentThread]);
}

-(void)testDependency2
{
    NSLog(@"begin %@",[NSThread currentThread]);

    dispatch_queue_t queue = dispatch_queue_create("12312312", DISPATCH_QUEUE_CONCURRENT);
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_async(group,queue,
                         ^{
                             sleep(6.0);
                             NSLog(@"----1-----%@", [NSThread currentThread]);
                         });
    dispatch_group_async(group,queue,
                         ^{
                             sleep(4.0);
                             NSLog(@"----2-----%@", [NSThread currentThread]);
                         });
    //queue,可替换为mainQueue，使任务3在主线程执行
    dispatch_group_notify(group, queue, ^{
        NSLog(@"----3-----%@", [NSThread currentThread]);
    });
    NSLog(@"end %@",[NSThread currentThread]);
}

#pragma mark - dispatchIO

- (void)testDispatchIO
{
    NSString *desktop = @"/Users/baidu/Desktop/TestGCD/TestGCD/";
    NSString *path = [desktop stringByAppendingPathComponent:@"AppDelegate.m"];

    dispatch_queue_t queue = dispatch_queue_create("queue", DISPATCH_QUEUE_CONCURRENT);
    dispatch_fd_t fd = open(path.UTF8String, O_RDONLY);
    dispatch_io_t io = dispatch_io_create(DISPATCH_IO_RANDOM, fd, queue, ^(int error) {
        close(fd);
    });
    
    off_t beginSize = 200;//从文件200字节处开始读取
    size_t offset = 100;//每次读取字节数
    long long fileSize = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil].fileSize;//文件大小
    NSLog(@"文件大小为 %lld",fileSize);
    
    dispatch_group_t group = dispatch_group_create();
    NSMutableData *totalData = [NSMutableData data];
    
    dispatch_group_enter(group);
    dispatch_io_read(io, beginSize, offset, queue, ^(bool done, dispatch_data_t  _Nullable data, int error) {
        if (error == 0) {
            size_t len = dispatch_data_get_size(data);
            if (len > 0) {
                const void *bytes = NULL;
                (void)dispatch_data_create_map(data, (const void **)&bytes, &len);
                [totalData appendBytes:bytes length:len];
            }
        }
        if (done) {
            dispatch_group_leave(group);
        }
    });
    
    dispatch_group_notify(group, queue, ^{
        NSString *str = [[NSString alloc] initWithData:totalData encoding:NSUTF8StringEncoding];
        NSLog(@"读取的数据：  ---   %@", str);
    });
    
}
#pragma mark - 死锁和打印
- (void)testSync
{
    NSLog(@"111");
    dispatch_queue_t queue = dispatch_queue_create("com.testGCD.dispatchQueue", NULL);
    dispatch_sync(queue, ^{
        NSLog(@"block");
    });
    NSLog(@"222");
}

- (void)testAsync
{
    //主线程，异步
    NSLog(@"111");
    dispatch_queue_t queue = dispatch_queue_create("com.testGCD.dispatchQueue", NULL);
    dispatch_async(queue, ^{
        sleep(2.0);
        NSLog(@"block");
    });
    NSLog(@"222");
}

#pragma mark - 设置最大并发数
-(void)testMaxCount
{
    //创建执行任务的并发队列，也可用dispatch_group_t代替
    dispatch_queue_t workConcurrentQueue = dispatch_queue_create("cccccccc", DISPATCH_QUEUE_CONCURRENT);
    //创建存放任务的串行队列
    dispatch_queue_t serialQueue = dispatch_queue_create("sssssssss",DISPATCH_QUEUE_SERIAL);
    //创建 最大并发数为5
    int count = 2;
    //创建对应并发数的信号量
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(count);
    
    //往执行任务的串行队列中，加入10个异步任务
    for (NSInteger i = 0; i < 5; i++) {
        dispatch_async(serialQueue, ^{
            //当信号总量少于或等于0的时候就会一直等待，否则就可以正常的执行，并让信号总量-1。
            //当添加到第count个任务时，信号量变为0，进入等待，直到有其他任务完成，发送信号量+1 则，继续执行任务
            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
            dispatch_async(workConcurrentQueue, ^{
                NSLog(@"thread:%@开始执行%d",[NSThread currentThread],(int)i);
                sleep(1);
                NSLog(@"thread:%@结束执行%d",[NSThread currentThread],(int)i);
                //发送一个信号，信号总量会加1
                dispatch_semaphore_signal(semaphore);
                
            });
        });
    }
    NSLog(@"主线程...!");
}

#pragma mark - 异步转同步
- (NSInteger)testAsyncToSync
{
    NSLog(@"testAsyncToSync 开始");
    __block NSInteger result = 0;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    [self methodAsync:^(NSInteger value) {
        result = value;
        dispatch_semaphore_signal(sema);
    }];
    // 这里本来同步方法会立即返回，但信号量=0使得线程阻塞
    // 当异步方法回调之后，发送信号，信号量变为1，这里的阻塞将被解除，从而返回正确的结果
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    NSLog(@"testAsyncToSync 结束 result:%ld", (long)result);
    return result;
}
// 异步方法
- (void)methodAsync:(void(^)(NSInteger result))callBack
{
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSLog(@"methodAsync 异步开始");
        sleep(2);
        NSLog(@"methodAsync 异步结束");
        if (callBack) {
            callBack(5);
        }
    });
}

@end
