module yu.utils.buffer.poolfixedbuffer;

import yu.container.nextqueue;
import yu.thread;

/****
固定大小的缓存队列。侵入时，nogc
***/

struct PoolFixedBuffer(uint preSize,bool locker = false,bool yield = true)
{
	@nogc nothrow:
	struct FixedItem
	{
		ubyte[preSize] data;
		uint length = 0;
		FixedItem * next = null;
	}

	alias  Queue = NextQueue!(FixedItem);

	this(ulong initSize,ulong maxCache = 0){
		_maxCacheSize = maxCache;
		Queue queue;
		for(ulong i = 0;i < initSize ; ++i){
            queue.enQueue(Queue.make());
        }
		closeItem(queue);
	}
	~this(){
		while(true){
			auto ptr = _queue.deQueue();
			if(ptr == null)
				return;
			Queue.del(ptr);
		}
	}

	@property ulong size() {return _queue.size ;}
	@property ref ulong maxCacheSize()  {return _maxCacheSize;}

	FixedItem * openItem(){
		static if(locker){
			_locker.lock();
			scope(exit) _locker.unlock();
		}
		if(_queue.isEmpty){
			return Queue.make();
		}
		return _queue.deQueue();
	}

	void closeItem(FixedItem * item){
        if(item == null) return;
        auto size = size() + 1;
        if(_maxCacheSize > 0 && size > _maxCacheSize){
            Queue.del(item);
            return;
        }
		static if(locker){
			_locker.lock();
			scope(exit) _locker.unlock();
		}
        _queue.enQueue(item);
    }

    void closeItem(ref Queue queue)
    {
        ulong size = _queue.size() + queue.size();
        while(_maxCacheSize > 0 && size > _maxCacheSize){
            auto item = queue.deQueue();
            if(item == null){
                return;
            }
            Queue.del(item);
            size -- ;
        }
		static if(locker){
			_locker.lock();
			scope(exit) _locker.unlock();
		}
       _queue.enQueue(queue);
    }

private:
	Queue _queue;
    ulong _maxCacheSize; // @suppress(dscanner.style.number_literals)
	static if(locker)
		SpinLock!(yield) _locker;
}

unittest
{
	import std.stdio;
	auto pool = PoolFixedBuffer!(256)(10);
	auto item = pool.openItem();
	item.data[1] = 'u';
	// writeln("pool size is ==============  ",pool.size);
	assert(pool.size == 9);
	pool.closeItem(item);
	assert(pool.size == 10);
}
