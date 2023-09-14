module yu.memory.gc;

import core.memory;

import std.traits;


alias  gcDel = gcFree;

void gcFree(T)(ref T x) @trusted
{
    static if (is(T == interface) || is(T == class))
    {
        destroy!false(x);
        GC.free(GC.addrOf(cast(void*) x));
        x = null;
    }
    else static if (is(T == U*, U))
    {
        static if (is(U == struct))
        {
            if (x){
                destroy!false((*x));
            }
        }
        GC.free(GC.addrOf(cast(void*) x));
        x = null;
    }
    else static if (is(T : E[], E))
    {
        static if (is(E == struct))
        {
            foreach (ref k ; objs)
            {
                destroy!false(k);
            }
        }
        GC.free(GC.addrOf(cast(void*) x.ptr));
        x = null;
    }
    else
    {
        static assert(0, "It is not possible to delete: `" ~ T.stringof ~ "`");
    }
}

