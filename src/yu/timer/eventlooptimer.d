module yu.timer.eventlooptimer;

import core.memory;
import core.sys.posix.time;

import std.socket : socket_t;
import std.exception;

import yu.eventloop;

@trusted final class EventLoopTimer : EventCallInterface
{
    this(EventLoop loop)
    {
        _loop = loop;
        _event = AsyncEvent(AsynType.TIMER, this);
    }

    ~this()
    {
		if (isActive){
			onClose();
        }
    }

    pragma(inline, true) @property bool isActive() nothrow
    {
        return _event.isActive;
    }

    pragma(inline) void setCallBack(CallBack cback)
    {
        _callBack = cback;
    }

    bool start(ulong msesc)
    {
        if (isActive() || msesc <= 0)
            return false;
        static if (IOMode == IOMode.kqueue || CustomTimer)
        {
            _event.timeOut = cast(long) msesc;
        }
        else static if (IOMode == IOMode.epoll)
        {
            import yu.eventloop.selector.epoll;

            //  _timeout = msesc;
           auto fd = cast(socket_t) timerfd_create(CLOCK_MONOTONIC, TFD_CLOEXEC | TFD_NONBLOCK);
			_event = AsyncEvent(AsynType.TIMER, this,fd,true);
            itimerspec its;
            ulong sec, nsec;
            sec = msesc / 1000;
            nsec = (msesc % 1000) * 1_000_000;
            its.it_value.tv_sec = cast(typeof(its.it_value.tv_sec)) sec;
            its.it_value.tv_nsec = cast(typeof(its.it_value.tv_nsec)) nsec;
            its.it_interval.tv_sec = its.it_value.tv_sec;
            its.it_interval.tv_nsec = its.it_value.tv_nsec;
            int err = timerfd_settime(_event.fd, 0, &its, null);
            if (err == -1)
            {
                import core.sys.posix.unistd;

                close(_event.fd);
                return false;
            }
        }
        return _loop.addEvent(&_event);
    }

    pragma(inline) void stop()
    {
       onClose();
    }

protected:
    override void onRead() nothrow
    {
        static if (IOMode == IO_MODE.epoll)
        {
            import core.sys.posix.unistd;

            ulong value;
            read(_event.fd, &value, 8);
        }
        if (_callBack)
        {
			collectException(_callBack());
        }
        else
        {
            onClose();
        }
    }

    override void onWrite() nothrow
    {
    }

    override void onClose() nothrow
    {
		if(!isActive) return;
		_loop.delEvent(&_event);
		static if (IOMode == IO_MODE.epoll)
        {
            import core.sys.posix.unistd;
            close(_event.fd);
        } 
    }

private:
    // ulong _timeout;
    CallBack _callBack;
    AsyncEvent _event;
    EventLoop _loop;
}

unittest
{
    import std.stdio;
    import std.datetime;
	import yu.memory.gc;

    EventLoop loop = new EventLoop();

	EventLoopTimer tm = new EventLoopTimer(loop);

    int cout = -1;
    ulong time;

    void timeout()
    {
        writeln("time  : ", Clock.currTime().toSimpleString());
        ++cout;
        if (cout == 0)
        {
            time = Clock.currTime().toUnixTime!long();
            return;
        }

        ++time;
        assert(time == Clock.currTime().toUnixTime!long());

        if (cout > 5)
        {
            writeln("loop stop!!!");
            tm.stop();
            loop.stop();
        }
    }

    tm.setCallBack(&timeout);

    tm.start(1000);

    loop.run();

	gcFree(tm);
	gcFree(loop);
}
