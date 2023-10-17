module yu.memory.allocator;
import std.experimental.allocator;
import std.typecons;
import std.experimental.allocator.mallocator;




template StaticAlloc(ALLOC)
{
    enum StaticAlloc = (stateSize!ALLOC == 0);
}

alias SharedMallocator = StaticSharedAllocatorImpl!Mallocator;

class StaticSharedAllocatorImpl(Allocator) : ISharedAllocator
	 if(StaticAlloc!Allocator)
{
	private int size = 0;
    import std.traits : hasMember;

	this(){
		size  = 0;
	}
    /**
    The implementation is available as a public member.
    */
     alias impl = Allocator.instance;
nothrow:
    /// Returns `impl.alignment`.
    override @property uint alignment() shared
    {
        return impl.alignment;
    }

    /**
    Returns `impl.goodAllocSize(s)`.
    */
    override size_t goodAllocSize(size_t s) shared
    {
        return impl.goodAllocSize(s);
    }

    /**
    Returns `impl.allocate(s)`.
    */
    override void[] allocate(size_t s, TypeInfo ti = null) shared
    {
        return impl.allocate(s);
    }

    /**
    If `impl.alignedAllocate` exists, calls it and returns the result.
    Otherwise, always returns `null`.
    */
    override void[] alignedAllocate(size_t s, uint a) shared
    {
        static if (hasMember!(Allocator, "alignedAllocate"))
            return impl.alignedAllocate(s, a);
        else
            return null;
    }

    /**
    If `Allocator` implements `owns`, forwards to it. Otherwise, returns
    `Ternary.unknown`.
    */
    override Ternary owns(void[] b) shared
    {
        static if (hasMember!(Allocator, "owns")) return impl.owns(b);
        else return Ternary.unknown;
    }

    /// Returns $(D impl.expand(b, s)) if defined, `false` otherwise.
    override bool expand(ref void[] b, size_t s) shared
    {
        static if (hasMember!(Allocator, "expand"))
            return impl.expand(b, s);
        else
            return s == 0;
    }

    /// Returns $(D impl.reallocate(b, s)).
    override bool reallocate(ref void[] b, size_t s) shared
    {
        return impl.reallocate(b, s);
    }

    /// Forwards to `impl.alignedReallocate` if defined, `false` otherwise.
    bool alignedReallocate(ref void[] b, size_t s, uint a) shared
    {
        static if (!hasMember!(Allocator, "alignedAllocate"))
        {
            return false;
        }
        else
        {
            return impl.alignedReallocate(b, s, a);
        }
    }

    // Undocumented for now
    Ternary resolveInternalPointer(const void* p, ref void[] result) shared
    {
        static if (hasMember!(Allocator, "resolveInternalPointer"))
        {
            return impl.resolveInternalPointer(p, result);
        }
        else
        {
            return Ternary.unknown;
        }
    }

    /**
    If `impl.deallocate` is not defined, returns `false`. Otherwise it forwards
    the call.
    */
    override bool deallocate(void[] b) shared
    {
        static if (hasMember!(Allocator, "deallocate"))
        {
            return impl.deallocate(b);
        }
        else
        {
            return false;
        }
    }

    /**
    Calls `impl.deallocateAll()` and returns the result if defined,
    otherwise returns `false`.
    */
    override bool deallocateAll() shared
    {
        static if (hasMember!(Allocator, "deallocateAll"))
        {
            return impl.deallocateAll();
        }
        else
        {
            return false;
        }
    }

    /**
    Forwards to `impl.empty()` if defined, otherwise returns `Ternary.unknown`.
    */
    override Ternary empty() shared
    {
        static if (hasMember!(Allocator, "empty"))
        {
            return Ternary(impl.empty);
        }
        else
        {
            return Ternary.unknown;
        }
    }

    /**
    Returns `impl.allocateAll()` if present, `null` otherwise.
    */
    override void[] allocateAll() shared
    {
        static if (hasMember!(Allocator, "allocateAll"))
        {
            return impl.allocateAll();
        }
        else
        {
            return null;
        }
    }

    @nogc nothrow pure @safe
    override void incRef() shared
    {

    }

    @nogc nothrow pure @trusted
    override bool decRef() shared
    {
        return true;
    }
}




shared class GCSharedAllocator : ISharedAllocator
{
	private int size = 0;
    import std.traits : hasMember;
	import core.memory;


	this(){
		size  = 0;
	}
    /**
    The implementation is available as a public member.
    */

nothrow:
    /// Returns `impl.alignment`.
    override @property uint alignment() shared
    {
        return platformAlignment;
    }

    /**
    Returns `impl.goodAllocSize(s)`.
    */
    override size_t goodAllocSize(size_t n) shared
    {
        if (n == 0)
            return 0;
        if (n <= 16)
            return 16;

        import core.bitop : bsr;

        auto largestBit = bsr(n-1) + 1;
        if (largestBit <= 12) // 4096 or less
            return size_t(1) << largestBit;

        // larger, we use a multiple of 4096.
        return ((n + 4095) / 4096) * 4096;
    }

    /**
    Returns `impl.allocate(s)`.
    */
    override void[] allocate(size_t bytes, TypeInfo ti = null) shared
    {
        if (!bytes) return null;
        auto p = GC.malloc(bytes,0,ti);
        return p ? p[0 .. bytes] : null;
    }

    /**
    If `impl.alignedAllocate` exists, calls it and returns the result.
    Otherwise, always returns `null`.
    */
    override void[] alignedAllocate(size_t s, uint a) shared
    {
            return null;
    }

    /**
    If `Allocator` implements `owns`, forwards to it. Otherwise, returns
    `Ternary.unknown`.
    */
    override Ternary owns(void[] b) shared
    {
        return Ternary.unknown;
    }

    /// Returns $(D impl.expand(b, s)) if defined, `false` otherwise.
    override bool expand(ref void[] b, size_t delta) shared
    {
        if (delta == 0) return true;
        if (b is null) return false;
        immutable curLength = GC.sizeOf(b.ptr);
        assert(curLength != 0); // we have a valid GC pointer here
        immutable desired = b.length + delta;
        if (desired > curLength) // check to see if the current block can't hold the data
        {
            immutable sizeRequest = desired - curLength;
            immutable newSize = GC.extend(b.ptr, sizeRequest, sizeRequest);
            if (newSize == 0)
            {
                // expansion unsuccessful
                return false;
            }
            assert(newSize >= desired);
        }
        b = b.ptr[0 .. desired];
        return true;
    }

    /// Returns $(D impl.reallocate(b, s)).
    override bool reallocate(ref void[] b, size_t s) shared
    {
        import core.exception : OutOfMemoryError;
        try
        {
            auto p = cast(ubyte*) GC.realloc(b.ptr, s);
            b = p[0 .. s];
        }
        catch (OutOfMemoryError)
        {
            // leave the block in place, tell caller
            return false;
        }
        return true;
    }

    /// Forwards to `impl.alignedReallocate` if defined, `false` otherwise.
    bool alignedReallocate(ref void[] b, size_t s, uint a) shared
    {

        return false;
    }

    // Undocumented for now
    Ternary resolveInternalPointer(const void* p, ref void[] result) shared
    {
        return Ternary.unknown;

    }

    /**
    If `impl.deallocate` is not defined, returns `false`. Otherwise it forwards
    the call.
    */
    override bool deallocate(void[] b) shared
    {
        GC.free(b.ptr);
        return true;
    }

    /**
    Calls `impl.deallocateAll()` and returns the result if defined,
    otherwise returns `false`.
    */
    override bool deallocateAll() shared
    {
        GC.collect();
        return false;

    }

    /**
    Forwards to `impl.empty()` if defined, otherwise returns `Ternary.unknown`.
    */
    override Ternary empty() shared
    {

        return Ternary.unknown;

    }

    /**
    Returns `impl.allocateAll()` if present, `null` otherwise.
    */
    override void[] allocateAll() shared
    {

        return null;

    }

    @nogc nothrow pure @safe
    override void incRef() shared
    {

    }

    @nogc nothrow pure @trusted
    override bool decRef() shared
    {
        return true;
    }
}
