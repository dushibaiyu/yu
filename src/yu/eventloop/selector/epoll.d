module yu.eventloop.selector.epoll;

import yu.eventloop.common;
import yu.memory.allocator;

version (linux)  : package(yu) : import core.time;
import core.stdc.errno;
import core.memory;

import core.sys.posix.sys.types; // for ssize_t, size_t
import core.sys.posix.netinet.tcp;
import core.sys.posix.netinet.in_;
import core.sys.posix.time : itimerspec, CLOCK_MONOTONIC;
import core.sys.posix.unistd;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.format;
import std.socket;
import std.experimental.logger;

import yu.exception : yuCathException;

/** 系统I/O事件处理类，epoll操作的封装
 */
struct EpollLoop {
    void initer() {
        if (_event)
            return;
        _efd = epoll_create1(0);
        errnoEnforce((_efd >= 0), "epoll_create1 failed");
        _event = yNew!EventChannel();
        addEvent(_event.event);
    }

    /** 析构函数，释放epoll。
	 */
    ~this() {
        if (_event) {
            .close(_efd);
            yDel(_event);
        }
    }

    /** 添加一个Channel对象到事件队列中。
	 @param   socket = 添加到时间队列中的Channel对象，根据其type自动选择需要注册的事件。
	 @return true 添加成功, false 添加失败，并把错误记录到日志中.
	 */
    bool addEvent(AsyncEvent * event) nothrow {
        if (event.fd == socket_t.init) {
            event.isActive = false;
            return false;
        }

        mixin(mixinModEvent());
        if ((epoll_ctl(_efd, EPOLL_CTL_ADD, event.fd,  & ev)) != 0) {
            if (errno != EEXIST)
                return false;
        }
        event.isActive = true;
        return true;
    }

    bool modEvent(AsyncEvent * event) nothrow {
        if (event.fd == socket_t.init) {
            event.isActive = false;
            return false;
        }
        mixin(mixinModEvent());

        if ((epoll_ctl(_efd, EPOLL_CTL_MOD, event.fd,  & ev)) != 0) {
            return false;
        }
        event.isActive = true;
        return true;
    }

    /** 从epoll队列中移除Channel对象。
	 @param socket = 需要移除的Channel对象
	 @return (true) 移除成功, (false) 移除失败，并把错误输出到控制台.
	 */
    bool delEvent(AsyncEvent * event) nothrow {
        if (event.fd == socket_t.init) {
            event.isActive = false;
            return false;
        }
        epoll_event ev;
        if ((epoll_ctl(_efd, EPOLL_CTL_DEL, event.fd,  & ev)) != 0) {
            yuCathException!false(error("EPOLL_CTL_DEL erro! ", event.fd));
            return false;
        }
        event.isActive = false;
        return true;
    }

    /** 调用epoll_wait。
	 *    @param    timeout = epoll_wait的等待时间
	 *    @param    eptr   = epoll返回时间的存储的数组指针
	 *    @param    size   = 数组的大小
	 *    @return 返回当前获取的事件的数量。
	 */

    void wait(int timeout)  nothrow  {
        epoll_event[64] events;
        auto len = epoll_wait(_efd, events.ptr, 64, timeout);
        if(len < 1) return;
        foreach(i;0..len){
            AsyncEvent * ev = cast(AsyncEvent * )(events[i].data.ptr);

            if (isErro(events[i].events)) {
                ev.obj.onClose();
                continue;
            }
            if (isWrite(events[i].events)) ev.obj.onWrite();

            if (isRead(events[i].events))  ev.obj.onRead();
        }
    }

    void weakUp() nothrow {
        _event.doWrite();
    }

    protected : pragma(inline, true) bool isErro(uint events)  nothrow {
        return (events & (EPOLLHUP | EPOLLERR | EPOLLRDHUP)) != 0;
    }
    pragma(inline, true) bool isRead(uint events)  nothrow {
        return (events & EPOLLIN) != 0;
    }
    pragma(inline, true) bool isWrite(uint events)  nothrow  {
        return (events & EPOLLOUT) != 0;
    }

    private :  /** 存储 epoll的fd */
    int _efd;
    EventChannel _event;
}

static this() {
    import core.sys.posix.signal;

    signal(SIGPIPE, SIG_IGN);
}

enum EPOLL_EVENT : short {
    init =  - 5
}

final class EventChannel : EventCallInterface {
    this() {
        _fd = cast(socket_t) eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
        _event = AsyncEvent(AsynType.EVENT, this, _fd, true, false, false);
    }
    ~this() {
        .close(_fd);
    }

    void doWrite() nothrow {
        ulong ul = 1;
        core.sys.posix.unistd.write(_fd,  & ul, ul.sizeof);
    }
    override void onRead() nothrow {
        ulong ul = 1;
        size_t len = read(_fd,  & ul, ul.sizeof);
    }

    override void onWrite() nothrow {
    }

    override void onClose() nothrow {
    }

    @property AsyncEvent * event() {
        return  & _event;
    }

    socket_t _fd;
    AsyncEvent _event;
}

string mixinModEvent() {
    return q{
        epoll_event ev;
        ev.data.ptr = event;
        ev.events = EPOLLRDHUP | EPOLLERR | EPOLLHUP;
        if (event.enRead)
            ev.events |= EPOLLIN;
        if (event.enWrite)
            ev.events |= EPOLLOUT;
        if (event.oneShot)
            ev.events |= EPOLLONESHOT;
        if (event.etMode)
            ev.events |= EPOLLET;
    };
}

extern (C) : @system : nothrow : enum {
    EFD_SEMAPHORE = 0x1,
    EFD_CLOEXEC = 0x80000,
    EFD_NONBLOCK = 0x800
};

enum {
    EPOLL_CLOEXEC = 0x80000,
    EPOLL_NONBLOCK = 0x800
}

enum {
    EPOLLIN = 0x001,
    EPOLLPRI = 0x002,
    EPOLLOUT = 0x004,
    EPOLLRDNORM = 0x040,
    EPOLLRDBAND = 0x080,
    EPOLLWRNORM = 0x100,
    EPOLLWRBAND = 0x200,
    EPOLLMSG = 0x400,
    EPOLLERR = 0x008,
    EPOLLHUP = 0x010,
    EPOLLRDHUP = 0x2000, // since Linux 2.6.17
    EPOLLONESHOT = 1u << 30,
    EPOLLET = 1u << 31
}

/* Valid opcodes ( "op" parameter ) to issue to epoll_ctl().  */
enum {
    EPOLL_CTL_ADD = 1, // Add a file descriptor to the interface.
    EPOLL_CTL_DEL = 2, // Remove a file descriptor from the interface.
    EPOLL_CTL_MOD = 3, // Change file descriptor epoll_event structure.
}

align(1) struct epoll_event {
    align(1) : uint events;
    epoll_data_t data;
}

union epoll_data_t {
    void * ptr;
    int fd;
    uint u32;
    ulong u64;
}

int epoll_create(int size);
int epoll_create1(int flags);
int epoll_ctl(int epfd, int op, int fd, epoll_event * event);
int epoll_wait(int epfd, epoll_event * events, int maxevents, int timeout);

int eventfd(uint initval, int flags);

//timerfd

int timerfd_create(int clockid, int flags);
int timerfd_settime(int fd, int flags, const itimerspec * new_value, itimerspec * old_value);
int timerfd_gettime(int fd, itimerspec * curr_value);

enum TFD_TIMER_ABSTIME = 1 << 0;
enum TFD_CLOEXEC = 0x80000;
enum TFD_NONBLOCK = 0x800;
