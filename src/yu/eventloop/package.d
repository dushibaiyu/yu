module yu.eventloop;

import core.thread;
import core.memory;

import std.exception;
import std.datetime;
import std.variant;
import std.algorithm.mutation;
import std.stdio;
import std.string;
import std.exception;
import std.experimental.allocator;
import std.experimental.allocator.gc_allocator;

public import yu.eventloop.common;
import yu.memory.allocator;
import yu.task;
import yu.exception;


/** 网络I/O处理的事件循环类
 */

@trusted final class EventLoopImpl(T) //用定义别名的方式
{
    this()
    {
		_poll.initer();
        _run = false;
        static if (CustomTimer)
			_timeWheel = yNew!ETimerWheel(CustomTimerWheelSize,yuAlloctor);
		_evlist = AsyncEvent(AsynType.EVENT, null);
    }

    ~this()
    {
        static if (CustomTimer)
			if(_timeWheel)
				yDel(_timeWheel);
    }

    /** 开始执行事件等待。
	 @param :timeout = 无事件的超时等待时间。单位：毫秒,如果是用CustomTimer， 这个超时时间将无效。
	 @note : 此函数可以多线程同时执行，实现多个线程共用一个事件调度
	 */
    void run(int timeout = 100)
    {
        _thID = Thread.getThis.id();
        _run = true;
        static if (CustomTimer)
            _nextTime = (Clock.currStdTime() / 10000) + CustomTimerTimeOut;
        while (_run)
        {
            static if (CustomTimer)
                timeout = doWheel();
            _poll.wait(timeout);
            if (!_taskList.empty){
				doTaskList();
            }
        }
        _thID = ThreadID.init;
        _run = false;
    }

    void weakUp() nothrow
    {
        _poll.weakUp();
    }

    bool isRuning() nothrow
    {
        return _run;
    }

    void stop()
    {
        if (isRuning())
        {
            _run = false;
            weakUp();
        }
    }

    bool isInLoopThread()
    {
        if (!isRuning())
            return true;
        return _thID == Thread.getThis.id;
    }

    void post(bool MustInQueue = false)(CallBack cback)
	in{
		assert(cback);
	}body{
		static if(!MustInQueue) {
	        if (isInLoopThread())
	        {
	            cback();
	            return;
	        }
		}
        synchronized (this)
        {
			_taskList.enQueue(makeTask(yuAlloctor,cback));
        }
        weakUp();
    }

	void post(bool MustInQueue = true)(AbstractTask task)
	{
		static if(!MustInQueue) {
			if (isInLoopThread())
			{
				task.job();
                yDel(task);
				return;
			}
		}
		synchronized (this)
		{
			_taskList.enQueue(task);
		}
		weakUp();
	}

    bool addEvent(AsyncEvent* event) nothrow
    {
        if (event == null)
            return false;
		addEventList(event);
        static if (CustomTimer)
        {
            if (event.type() == AsynType.TIMER)
            {
                try
                {
                    CWheelTimer timer = yNew!CWheelTimer(event);
                    _timeWheel.addNewTimer(timer, timer.wheelSize());
                    event.timer = timer;
                    event.isActive(true);
                }
                catch(Exception e)
                {
                    collectException(error("new CWheelTimer error!!! : ", e.toString));
                    return false;
                }
                return true;
            }
        }
        return _poll.addEvent(event);
    }

    bool modEvent(AsyncEvent* event) nothrow
    {
        if (event == null)
            return false;
		addEventList(event);
        static if (CustomTimer)
        {
            if (event.type() == AsynType.TIMER)
                return false;
        }
        return _poll.modEvent(event);
    }

    bool delEvent(AsyncEvent* event) nothrow
    {
        if (event == null)
            return false;
		event.rmNextPrev();
        static if (CustomTimer)
        {
            if (event.type() == AsynType.TIMER)
            {
				return rmCustomTimer(event);
            }
        }
        return _poll.delEvent(event);
    }

	static if (CustomTimer)
	{
		@property ETimerWheel timerWheel(){return _timeWheel;}

		private bool rmCustomTimer(AsyncEvent* event) nothrow
		{
			event.isActive(false);
			event.timer.stop();
			yDel(event.timer);
			event.timer = null;
			return true;
		}
	}

protected:
    void doTaskList()
    {
        import std.algorithm : swap;

		TaskQueue tmp;
        synchronized (this){
			swap(tmp, _taskList);
        }
        while (!tmp.empty)
        {
			import yu.exception;
			auto fp = tmp.deQueue();
			yuCathException!false(fp.job());
            yDel(fp);
        }
    }

	pragma(inline,true)
	void addEventList(AsyncEvent * event) nothrow
	{
		event.rmNextPrev();
		if(_evlist.next){
			_evlist.next.prev = event;
			event.next = _evlist.next;
		}
		_evlist.next = event;
		event.prev = &_evlist;
	}

private:
    T _poll;
	TaskQueue _taskList;
    bool _run;
    ThreadID _thID;
	AsyncEvent  _evlist;
    static if (CustomTimer)
    {
		ETimerWheel _timeWheel;
        long _nextTime;

        int doWheel()
        {
            auto nowTime = (Clock.currStdTime() / 10000);
            while (nowTime >= _nextTime)
            {
                _timeWheel.prevWheel();
                _nextTime += CustomTimerTimeOut;
                nowTime = (Clock.currStdTime() / 10000);
            }
            nowTime = _nextTime - nowTime;
            return cast(int) nowTime;
        }
    }
}

static if (IOMode == IO_MODE.kqueue)
{
    import yu.eventloop.selector.kqueue;

    alias EventLoop = EventLoopImpl!(KqueueLoop);
}
else static if (IOMode == IO_MODE.epoll)
{
	import yu.eventloop.selector.epoll;

    alias EventLoop = EventLoopImpl!(EpollLoop);
}
else static if (IOMode == IO_MODE.iocp)
{
	public import yu.eventloop.selector.iocp;

    alias EventLoop = EventLoopImpl!(IOCPLoop);
}
else
{
	static assert(0, "not suport this  platform !");
}

static if (CustomTimer)
{
    pragma(msg, "use CustomTimer!!!!");
private:
	@trusted final class CWheelTimer : EWheelTimer
    {
        this(AsyncEvent* event)
        {
            _event = event;
            auto size = event.timeOut / CustomTimerTimeOut;
            auto superfluous = event.timeOut % CustomTimerTimeOut;
            size += superfluous > CustomTimer_Next_TimeOut ? 1 : 0;
            size = size > 0 ? size : 1;
            _wheelSize = cast(uint) size;
            _circle = _wheelSize / CustomTimerWheelSize;
            trace("_wheelSize = ", _wheelSize, " event.timeOut = ", event.timeOut);
        }

        override void onTimeOut() nothrow
        {
            _now++;
            if (_now >= _circle)
            {
                _now = 0;
                rest(_wheelSize);
                _event.obj().onRead();
            }
        }

        pragma(inline, true) @property wheelSize()
        {
            return _wheelSize;
        }

    private:
        uint _wheelSize;
        uint _circle;
        uint _now = 0;
        AsyncEvent* _event;
    }
}



