module yu.container.common;

import core.atomic;
import std.traits : Unqual,hasFunctionAttributes;
import std.experimental.allocator;

public import yu.memory.allocator : StaticAlloc;

mixin template AllocDefine(ALLOC)
{
    static if (StaticAlloc!ALLOC) {
        alias _alloc = ALLOC.instance;
        alias Alloc = typeof(ALLOC.instance);
    } else {
        alias Alloc = ALLOC;
        private ALLOC _alloc;
        public @property ALLOC allocator() {
            return _alloc;
        }
    }
}

struct RefCount
{
    @disable this(ref RefCount);
    pragma(inline)
    uint refCnt() shared nothrow @nogc
    {
        return atomicOp!("+=")(_count, 1);
    }

    pragma(inline)
    uint derefCnt()  shared nothrow @nogc
    {
        return atomicOp!("-=")(_count, 1);
    }

    pragma(inline)
    uint count()  shared nothrow @nogc
    {
        return atomicLoad(_count);
    }

private:
    shared uint _count = 1;
}

mixin template Refcount()
{
     static typeof(this) * allocate(ALLOC)(auto ref ALLOC alloc){
        return alloc.make!(typeof(this))();
    }

    static void deallocate(ALLOC)(auto ref ALLOC alloc, typeof(this) * dd){
        alloc.dispose(dd);
    }

    static void inf(typeof(this) * dd)
    {
        if(dd is null) return;
        dd._count.refCnt();
    }

    static typeof(this) * deInf(ALLOC)(auto ref ALLOC alloc, typeof(this) * dd)
    {
        if(dd is null) return dd;
        if(dd._count.derefCnt() == 0){
            deallocate!ALLOC(alloc,dd);
            return null;
        }
        return dd;
    }
    @property uint count(){return _count.count();}

    private shared RefCount _count;
}

/// Array Cow Data
struct ArrayCOWData(T, Allocator,bool inGC = false)  if(is(T == Unqual!T))
{
	// static if(!inGC && StaticAlloc!Allocator){
	static if(hasFunctionAttributes!(Allocator.deallocate, "@nogc") && hasFunctionAttributes!(Allocator.allocate, "@nogc")) {
		@nogc:
	}
    import core.memory : GC;
    import core.stdc.string : memcpy;
    import yu.array : fillWithMemcpy;
	import core.exception : onOutOfMemoryError;


    ~this()
    {
        destoryBuffer();
    }

    bool reserve(size_t elements) {
        if (elements <= data.length)
            return false;
        size_t len = _alloc.goodAllocSize(elements * T.sizeof);
        elements = len / T.sizeof;
        void[] varray = _alloc.allocate(len);
		if(null == varray.ptr)
			onOutOfMemoryError();
        auto ptr = cast(T*)(varray.ptr);
        size_t bleng = (data.length * T.sizeof);
        if (data.length > 0) {
            memcpy(ptr, data.ptr, bleng);
        }
        varray = varray[bleng.. len];
        fillWithMemcpy!T(varray,T.init);
        static if(inGC){
            GC.addRange(ptr, len);
        }
        destoryBuffer();
        data = ptr[0 .. elements];
        return true;
    }

    pragma(inline, true)
    void destoryBuffer(){
        if (data.ptr) {
            static if(inGC)
                GC.removeRange(data.ptr);
            _alloc.deallocate(data);
        }
    }

    static if (StaticAlloc!Allocator)
        alias _alloc = Allocator.instance;
    else
        Allocator _alloc;
    T[] data;

    mixin Refcount!();
}
