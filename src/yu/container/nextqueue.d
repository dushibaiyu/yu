module yu.container.nextqueue;

import std.traits;
import yu.memory;



struct NextQueue(T) if(hasMember!(T,"next"))
{
	static if (is(T == interface) || is(T == class))
    {
		alias Item = T;
    } else static if(is(T == struct)){
		alias Item = T *;
	} else {
		static assert(0,"un support type");
	}

	@disable this(ref NextQueue);

	static Item make(Args...)(Args args){
		return cNew!T(args);
	}

	static void del(ref Item item){
		cDel(item);
	}

	~this(){
		clear();
	}

	@property bool isEmpty()  const {return _first == null;}
	@property size_t size() const {return _size;}

    @property  Item frist()  {
        return _first;
    }

    @property  Item last()  {
        return _last;
    }


	void enQueue(Item item){
        if(item == null) return;
        if(_first == null) {
            _first = item;
        }else {
            _last.next = item;
        }
        _last = item;
        _size ++;
    }

	void enQueue(ref NextQueue  item){
        if(item.isEmpty()) return;
        if(_first == null) {
            _first = item.frist;
        } else {
            _last.next = item.frist;
        }
        _last = item.last();
        _last.next = null;
        _size += item.size();
        item.clear();
    }

	void clear(){
        _first = null;
        _last = null;
        _size = 0;
    }

	Item deQueue(){
        Item ret = _first;
        if(_first != null) {
            _first = _first.next;
            if(_first == null) {
                _last = _first;
            }
            ret.next = null;
            --_size;
        }
        return ret;
    }

	void swap(ref NextQueue  queue){
        queue._first = _first;
        queue._last = _last;
        queue._size = _size;
        clear();
    }

private:
	Item _first = null;
    Item _last = null;
    uint _size = 0;
}
