module yu.memory.allocator.smartgcalloctor;

struct SmartGCAllocator
{
	import core.memory : GC;
	
	enum uint alignment = platformAlignment;
	
	pure nothrow @trusted void[] allocate(size_t bytes) shared
	{
		if (!bytes) return null;
		auto p = GC.malloc(bytes);
		return p ? p[0 .. bytes] : null;
	}
	
	@system bool expand(ref void[] b, size_t delta) shared
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
	
	pure nothrow @system bool reallocate(ref void[] b, size_t newSize) shared
	{
		import core.exception : OutOfMemoryError;
		try
		{
			auto p = cast(ubyte*) GC.realloc(b.ptr, newSize);
			b = p[0 .. newSize];
		}
		catch (OutOfMemoryError)
		{
			// leave the block in place, tell caller
			return false;
		}
		return true;
	}
	
	
	pure nothrow void[] resolveInternalPointer(void* p) shared
	{
		auto r = GC.addrOf(p);
		if (!r) return null;
		return r[0 .. GC.sizeOf(r)];
	}
	
	
	pure nothrow @system bool deallocate(void[] b) shared
	{
		GC.free(b.ptr);
		return true;
	}
	
	
	size_t goodAllocSize(size_t n) shared
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
	
	
	static shared SmartGCAllocator instance;
	
	nothrow @trusted void collect() shared
	{
		GC.collect();
	}
	
	auto make(T,A...)(auto ref A args) shared
	{
		auto construct()
		{
			static if (is(T == class) || is(T == struct)) return new T(args);
			else 
			{
				import std.algorithm.comparison : max;
				import std.conv : emplace;
				auto m = this.allocate(max(stateSize!T, 1));
				if (!m.ptr) return null;
				scope(failure){
					() @trusted { this.deallocate(m); }();
				}
				// Assume cast is safe as allocation succeeded for `stateSize!T`
				auto p = () @trusted { return cast(T*)m.ptr; }();
				emplace!T(p, args);
				return p;
			}
		}
		
		return construct();
	}
	
}
