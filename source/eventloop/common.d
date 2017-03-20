/*
 * Collie - An asynchronous event-driven network framework using Dlang development
 *
 * Copyright (C) 2015-2016  Shanghai Putao Technology Co., Ltd 
 *
 * Developer: putao's Dlang team
 *
 * Licensed under the Apache-2.0 License.
 *
 */
module collie.socket.common;

//import core.memory;

public import std.experimental.logger;
public import collie.common;
import std.experimental.allocator;

enum IO_MODE
{
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

version (FreeBSD)
{
    enum IO_MODE IOMode = IO_MODE.kqueue;
    enum CustomTimer = false;
}
else version (OpenBSD)
{
    enum IO_MODE IOMode = IO_MODE.kqueue;
    enum CustomTimer = false;
}
else version (NetBSD)
{
    enum IO_MODE IOMode = IO_MODE.kqueue;
    enum CustomTimer = false;
}
else version (OSX)
{
    enum IO_MODE IOMode = IO_MODE.kqueue;
    enum CustomTimer = false;
}
else version (linux)
{
    enum IO_MODE IOMode = IO_MODE.epoll;
    enum CustomTimer = false;
}
else version (Windows)
{
    enum IO_MODE IOMode = IO_MODE.iocp;
    enum CustomTimer = true;
}
else
{
    static_assert(0,"not support platm");
    enum CustomTimer = true;
}

alias CallBack = void delegate();

enum AsynType
{
    ACCEPT,
    TCP,
    UDP,
    EVENT,
    TIMER
}

interface EventCallInterface
{
    void onWrite() nothrow;
    void onRead() nothrow;
    void onClose() nothrow;
}

struct AsyncEvent
{
    import std.socket;

    this(AsynType type, EventCallInterface obj, socket_t fd = socket_t.init,
        bool enread = true, bool enwrite = false, bool etMode = false, bool oneShot = false)
    {
        this._type = type;
        this._obj = obj;
        this.fd = fd;
        this.enRead = enread;
        this.enWrite = enwrite;
        this.etMode = etMode;
        this.oneShot = oneShot;
    }

    pragma(inline, true) @property obj()
    {
        return _obj;
    }

    pragma(inline, true) @property type()
    {
        return _type;
    }

    socket_t fd;

    bool enRead = true;
    bool enWrite = false;
    bool etMode = false;
    bool oneShot = false;

    pragma(inline) static AsyncEvent* create(AsynType type,
        EventCallInterface obj, socket_t fd = socket_t.init, bool enread = true,
        bool enwrite = false, bool etMode = false, bool oneShot = false)
    {
        import core.memory;

        AsyncEvent* pevent = collieAllocator.make!AsyncEvent(type, obj, fd, enread, enwrite, etMode,
            oneShot);
       // GC.setAttr(pevent, GC.BlkAttr.NO_MOVE);
        return pevent;
    }

    pragma(inline) static void free(AsyncEvent* event)
    {
       // import core.memory;
        dispose(collieAllocator,event);
        //GC.free(event);
    }

    pragma(inline, true) @property isActive()
    {
        return _isActive;
    }
package:
    pragma(inline) @property isActive(bool active)
    {
        _isActive = active;
    }

    static if (IOMode == IOMode.kqueue || CustomTimer)
    {
        long timeOut;
    }
    static if (IOMode == IOMode.iocp)
    {
        uint readLen;
        uint writeLen;
    }
    static if (CustomTimer)
    {
        import collie.utils.timingwheel;

        WheelTimer timer;
    }

private:
    EventCallInterface _obj;
    AsynType _type;
    bool _isActive = false;
}

static if (CustomTimer)
{
    enum CustomTimer_Next_TimeOut = cast(long)(CustomTimerTimeOut * (2.0 / 3.0));
}
