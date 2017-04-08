module yu.eventloop.common;

//import core.memory;

public import std.experimental.logger;
import yu.memory.allocator;

static if (CustomTimer) {
    public import yu.timer.timingwheeltimer;

    alias ETimerWheel = ITimingWheel!IAllocator;
    alias EWheelTimer = ETimerWheel.WheelTimer;
}

enum IO_MODE {
    epoll,
    kqueue,
    iocp,
    select,
    poll,
    port,
    none
}

enum CustomTimerTimeOut = 50; // 50ms 精确
enum CustomTimerWheelSize = 20; // 轮子数量

version (FreeBSD) {
    enum IO_MODE IOMode = IO_MODE.kqueue;
    enum CustomTimer = false;
} else version (OpenBSD) {
    enum IO_MODE IOMode = IO_MODE.kqueue;
    enum CustomTimer = false;
} else version (NetBSD) {
    enum IO_MODE IOMode = IO_MODE.kqueue;
    enum CustomTimer = false;
} else version (OSX) {
    enum IO_MODE IOMode = IO_MODE.kqueue;
    enum CustomTimer = false;
} else version (linux) {
    enum IO_MODE IOMode = IO_MODE.epoll;
    enum CustomTimer = false;
} else version (Windows) {
    enum IO_MODE IOMode = IO_MODE.iocp;
    enum CustomTimer = true;
} else {
    static assert(0, "not suport this  platform !");
}

alias CallBack = void delegate();

enum AsynType {
    ACCEPT,
    TCP,
    UDP,
    EVENT,
    TIMER
}

interface EventCallInterface {
    void onWrite() nothrow;
    void onRead() nothrow;
    void onClose() nothrow;
}

struct AsyncEvent {
    import std.socket;

    this(AsynType type, EventCallInterface obj, socket_t fd = socket_t.init,
        bool enread = true, bool enwrite = false, bool etMode = false, bool oneShot = false) {
        this._type = type;
        this._obj = obj;
        this._fd = fd;
        this.enRead = enread;
        this.enWrite = enwrite;
        this.etMode = etMode;
        this.oneShot = oneShot;
    }

    @disable this();
    @disable this(this);

    ~this() {
        rmNextPrev();
    }

    pragma(inline, true) @property obj() {
        return _obj;
    }

    pragma(inline, true) @property type() {
        return _type;
    }

    pragma(inline, true) @property fd() {
        return _fd;
    }

    bool enRead = true;
    bool enWrite = false;
    bool etMode = false;
    bool oneShot = false;

    pragma(inline, true) @property isActive() {
        return _isActive;
    }

package(yu):
    static if (IOMode == IOMode.kqueue || CustomTimer) {
        long timeOut;
    }
package(yu):
    static if (IOMode == IOMode.iocp) {
        uint readLen;
        uint writeLen;
    }

package(yu.eventloop):
    pragma(inline) @property isActive(bool active) {
        _isActive = active;
    }

    static if (CustomTimer) {
        import yu.timer.timingwheeltimer;
        import std.experimental.allocator;

        EWheelTimer timer;
    }

    @trusted void rmNextPrev() @nogc nothrow {
        if (next)
            next.prev = prev;
        if (prev)
            prev.next = next;
        next = null;
        prev = null;
    }

    AsyncEvent* next = null;
    AsyncEvent* prev = null;

private:
    EventCallInterface _obj;
    AsynType _type;
    socket_t _fd = socket_t.init;
    bool _isActive = false;
}

static if (CustomTimer) {
    enum CustomTimer_Next_TimeOut = cast(long)(CustomTimerTimeOut * (2.0 / 3.0));
}
