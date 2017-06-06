Yu(玉)
---------------------------------
        A Dlang's Toolkit. Extend Phobos.

------------------------------

* algorithm
* * snowflkeId.d : Twitter's Snowflke ID generate algorithm.to generate only ID
* container : the container base std.experimental.allocator
* * cirularqueue : Cirular Queue Struct Template.
* * vector : Like as C++'s std::vector
* * string :  The COW string template.
* eventloop :  the io(Net) event loop. support EPOLL, KQUEUE , IOCP.
* asyncsocket : The async socket base std.scoket and yu.eventloop
* * client :  the easy Use TCP client. Has time out and connect try, and mitil-client
* * server :  the easy Use TCP server. Has Time out and auto close .
* * Acceptor  : Tcp listen and accept
* * TCPClient :  Base Tcp client
* * TCPSocket : Base TCP connection
* * UDPSocket :  Base Udp connection
* timer :  Timer
* * eventlooptimer : the timer base yu.eventloop
* * timingwheeltimer :  Time wheel algorithm . base std.experimental.allocator
* memory
* * alloctor : the yuAlloctor and easy make object base yuAlloctor. Base  std.experimental.allocator
* * gc :  gcFree to easy free the memory in GC
* * scopedref :  the Unique Ptr/Ref like C++'s  std::unique_ptr.
* * sharedref : the RC Ptr/Ref like C++'s std::shared_ptr
* * smartref : easy to create the scopedref and sharedref
* array : Extend Phobos's std.array.
* bytes : add find in byte or ubyte.
* exception : Extend Phobos's std.exception.
* functional :  add bind use delegate.
* string : Extend Phobos's std.string.
* task : the task base  std.experimental.allocator
* thread :  auto attach thread
* traits : : Extend Phobos's std.traits.
* tools
* * http1xparser :  the http 1.x and url parser. Base and Port from : [https://github.com/nodejs/http-parser](https://github.com/nodejs/http-parser)
* * buffer : the buffer class.
* * sharedlib : load dll or so, in runing

