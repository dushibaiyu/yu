module yu.thread;

public import core.thread;
import yu.exception;

pragma(inline) Thread currentThread() nothrow @trusted {
    auto th = Thread.getThis();
    if (th is null) {
        yuCathException(thread_attachThis(), th);
    }
    return th;
}



shared struct SpinLock(bool yield = true)
{
	import core.atomic;
	@disable this(ref SpinLock);
	@nogc nothrow:
	void lock() {
		while (!cas(&locked, false, true)) {
			static if(yield) {
				Thread.yield();
			} else {
				core.atomic.pause();

			}
		}
	}
	void unlock() {
		atomicStore!(MemoryOrder.rel)(locked, false);
	}
private:
	bool locked = false;
}


unittest {
    import std.stdio;

    writeln("currentThread().id ------------- ", currentThread().id);
}
