module yu.timer.timingwheeltimer;

import yu.memory.allocator.smartgcalloctor;

alias TimingWheel = ITimingWheel!SmartGCAllocator;
alias WheelTimer = TimingWheel.WheelTimer;
alias NullWheelTimer = TimingWheel.NullWheelTimer;
/**
    Timing Wheel manger Class
*/
@trusted final class ITimingWheel(Allocator)
{
	alias WheelTimer = IWheelTimer!Allocator;
	alias NullWheelTimer = INullWheelTimer!Allocator;
	/**
        constructor
        Params:
            wheelSize =  the Wheel's element router.
    */
	static if (stateSize!Allocator == 0){
		this(uint wheelSize){
			_init(wheelSize);
		}
	} else {
		this(uint wheelSize,Allocator alloc){
			_alloc = alloc;
			_init(wheelSize);
		}
	}
	
	~this(){
		foreach(ref NullWheelTimer tm ; _list){
			_alloc.dispose(tm);
			tm = null;
		}
		_alloc.dispose(_list);
	}
	
	/**
        add a Timer into the Wheel
        Params:
            tm  = the timer.
    */
	pragma(inline) void addNewTimer(WheelTimer tm, size_t wheel = 0) nothrow
	{
		size_t index;
		if (wheel > 0)
			index = nextWheel(wheel);
		else
			index = getPrev();
		NullWheelTimer timer = _list[index];
		tm._next = timer._next;
		tm._prev = timer;
		if (timer._next)
			timer._next._prev = tm;
		timer._next = tm;
		tm._manger = this;
	}
	
	/**
        The Wheel  go forward
        Params:
            size  = forward's element size;
        Notes:
            all forward's element will timeout.
    */
	void prevWheel(uint size = 1) nothrow
	{
		if (size == 0)
			return;
		foreach (i; 0 .. size)
		{
			NullWheelTimer timer = doNext();
			timer.onTimeOut();
		}
	}
	
protected:
	/// get next wheel times 's Wheel
	pragma(inline) size_t nextWheel(size_t wheel) nothrow
	{
		auto next = wheel % _list.length;
		return (_now + next) % _list.length;
	}
	
	/// get the index whitch is farthest with current index.
	size_t getPrev() const nothrow
	{
		if (_now == 0)
			return (_list.length - 1);
		else
			return (_now - 1);
	}
	/// go forward a element,and return the element.
	pragma(inline) NullWheelTimer doNext() nothrow
	{
		++_now;
		if (_now == _list.length)
			_now = 0;
		return _list[_now];
	}
	/// rest a timer.
	pragma(inline) void rest(WheelTimer tm, size_t next) nothrow
	{
		remove(tm);
		addNewTimer(tm, next);
	}
	/// remove the timer.
	pragma(inline) void remove(WheelTimer tm) nothrow
	{
		tm._prev._next = tm._next;
		if (tm._next)
			tm._next._prev = tm._prev;
		tm._manger = null;
		tm._next = null;
		tm._prev = null;
	}
	
private:
	void _init(uint wheelSize){
		if (wheelSize == 0)
			wheelSize = 2;
		_list = ()@trusted{return makeArray!NullWheelTimer(_alloc,wheelSize);}();
		for (int i = 0; i < wheelSize; ++i)
			_list[i] = _alloc.make!NullWheelTimer();
	}
	NullWheelTimer[] _list;
	size_t _now;
	static if (stateSize!Allocator == 0)
		alias _alloc = Allocator.instance;
	else
		Allocator _alloc;
}

/**
    The timer parent's class.
*/
@trusted abstract class IWheelTimer(Allocator)
{
	alias TimerWheel = ITimingWheel!Allocator;
	alias WheelTimer = IWheelTimer!Allocator;
	
	~this()
	{
		stop();
	}
	/**
        the function will be called when the timer timeout.
    */
	void onTimeOut() nothrow;
	
	/// rest the timer.
	pragma(inline) final void rest(size_t next = 0) nothrow
	{
		if (_manger)
		{
			_manger.rest(this, next);
		}
	}
	
	/// stop the time, it will remove from Wheel.
	pragma(inline) final void stop() nothrow
	{
		if (_manger)
		{
			_manger.remove(this);
		}
	}
	
	/// the time is active.
	pragma(inline, true) final bool isActive() const nothrow
	{
		return _manger !is null;
	}
	
	/// get the timer only run once.
	pragma(inline, true) final @property oneShop()
	{
		return _oneShop;
	}
	/// set the timer only run once.
	pragma(inline) final @property oneShop(bool one)
	{
		_oneShop = one;
	}
	
private:
	WheelTimer _next = null;
	WheelTimer _prev = null;
	TimerWheel _manger = null;
	bool _oneShop = false;
}

private:

/// the Header Timer in the wheel.
@safe class INullWheelTimer(Allocator) : IWheelTimer!Allocator
{
	override void onTimeOut() nothrow
	{
		WheelTimer tm = _next;
		while (tm)
		{
			auto timer = tm._next;
			if (tm.oneShop())
			{
				tm.stop();
			}
			tm.onTimeOut();
			tm = timer;
		}
	}
}

unittest
{
	import std.datetime;
	import std.stdio;
	import std.conv;
	import core.thread;
	import std.exception;
	
	@trusted class TestWheelTimer : WheelTimer
	{
		this()
		{
			time = Clock.currTime();
		}
		
		override void onTimeOut() nothrow
		{
			collectException(writeln("\nname is ", name, " \tcutterTime is : ",
					Clock.currTime().toSimpleString(), "\t new time is : ", time.toSimpleString()));
		}
		
		string name;
	private:
		SysTime time;
	}
	
	writeln("start");
	TimingWheel wheel = new TimingWheel(5);
	TestWheelTimer[] timers = new TestWheelTimer[5];
	foreach (tm; 0 .. 5)
	{
		timers[tm] = new TestWheelTimer();
	}
	
	int i = 0;
	foreach (timer; timers)
	{
		timer.name = to!string(i);
		wheel.addNewTimer(timer);
		writeln("i  = ", i);
		++i;
		
	}
	writeln("prevWheel(5) the _now  = ", wheel._now);
	wheel.prevWheel(5);
	Thread.sleep(2.seconds);
	timers[4].stop();
	writeln("prevWheel(5) the _now  = ", wheel._now);
	wheel.prevWheel(5);
	Thread.sleep(2.seconds);
	writeln("prevWheel(3) the _now  = ", wheel._now);
	wheel.prevWheel(3);
	assert(wheel._now == 3);
	timers[2].rest();
	timers[4].rest();
	writeln("rest prevWheel(2) the _now  = ", wheel._now);
	wheel.prevWheel(2);
	assert(wheel._now == 0);
	
	foreach (u; 0 .. 20)
	{
		Thread.sleep(2.seconds);
		writeln("prevWheel() the _now  = ", wheel._now);
		wheel.prevWheel();
	}
	
}