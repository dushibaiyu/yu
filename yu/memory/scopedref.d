module yu.memory.scopedref;

import std.experimental.allocator;
import std.exception;
import std.traits : isPointer;

import yu.traits;

struct IScopedRef(Alloc,T)
{
	alias ValueType = Pointer!T;
	enum isSaticAlloc = (stateSize!Alloc == 0);
	alias Deleter = void function(ref Alloc,ValueType) nothrow;

	static if(isSaticAlloc) {
		this(ValueType ptr){
			this(ptr,&defaultDeleter);
		}
		this(ValueType ptr,Deleter deleter){
			_d = ptr;
			resetDeleter(deleter);
		}
	} else {
		this(Alloc alloc ,ValueType ptr){
			this(alloc,ptr,&defaultDeleter);
		}
		this(Alloc alloc ,ValueType ptr,Deleter deleter){
			_alloc = alloc;
			_d = ptr;
			resetDeleter(deleter);
		}
		
		@property Alloc allocator(){return _alloc;}
	}

	~this(){
		release();
	}

	void swap(typeof(this) other){
		static import std.algorithm.mutation;
		std.algorithm.mutation.swap(other._d,this._d);
		std.algorithm.mutation.swap(other._deleter,this._deleter);
		static if(!isSaticAlloc)
			std.algorithm.mutation.swap(other._alloc,this._alloc);
	}

	@property ValueType data() 
	{
		return _d;
	}

	alias data this;
	
	bool isNull() 
	{
		return (_d is null);
	}

	void resetDeleter(Deleter dele)
	in {assert(dele,"Deleter Function must be not null");}
	body{
		_deleter = dele;
	}

	void reset(ValueType v){
		release();
		_d = v;
	}

	static if(isSaticAlloc) {
		void reset(ValueType v, Alloc alloc){
			release();
			_alloc = alloc;
			_d = v;
		}
	}

	static if (isPointer!ValueType) {
		ref T opUnary(string op)()
			if (op == "*")
		{
			return *_d;
		}
	}

	ValueType take(){
		ValueType ret = _d;
		_d = null;
		return ret;
	}

	void release(){
		if(_d && _deleter){
			_deleter(_alloc,_d);
		}
		_d = null;
		_deleter = &defaultDeleter;
	}

	@disable this(this);
private:
	static void defaultDeleter(ref Alloc alloc, ValueType value) nothrow {
		collectException( alloc.dispose(value) );
	}

	ValueType _d;
	static if(!isSaticAlloc)
		Alloc _alloc ;
	else
		alias _alloc = Alloc.instance;
	Deleter _deleter = &defaultDeleter;
}

