module yu.container.common;

import core.atomic;
import std.experimental.allocator;


template StaticAlloc(ALLOC)
{
    enum StaticAlloc = (stateSize!ALLOC == 0);
}

mixin template AllocDefine(ALLOC)
{
    static if (StaticAlloc!ALLOC)
        alias _alloc = ALLOC.instance;
    else {
        private ALLOC _alloc;
        public @property ALLOC allocator() {
            return _alloc;
        }
    }
}

package:

struct RefCount
{
    pragma(inline,true)
    uint refCnt()
    {
        return atomicOp!("+=")(_count, 1);
    }

    pragma(inline,true)
    uint derefCnt()
    {
        return atomicOp!("-=")(_count, 1);
    }

    pragma(inline,true)
    uint count()
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
    @disable this(this);
    private RefCount _count;
}