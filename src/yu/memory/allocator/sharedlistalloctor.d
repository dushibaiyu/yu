module yu.memory.allocator.sharedlistalloctor;

import std.experimental.allocator;
import std.experimental.allocator.building_blocks.free_list;

class SharedListAllocator(ParentAllocator, size_t minSize,
    size_t maxSize = minSize, size_t approxMaxNodes = unbounded) : IAllocator {
    import std.traits : hasMember;
    import std.typecons;

    alias MySharedFreeList = SharedFreeList!(ParentAllocator, minSize, maxSize, unbounded);
    private shared MySharedFreeList _alloc;

    override @property uint alignment() {
        return MySharedFreeList.alignment;
    }

    override size_t goodAllocSize(size_t s) {
        return _alloc.goodAllocSize(s);
    }

    override void[] allocate(size_t s, TypeInfo ti = null) {
        return _alloc.allocate(s);
    }

    override void[] alignedAllocate(size_t s, uint a) {
        static if (hasMember!(MySharedFreeList, "alignedAllocate"))
            return _alloc.alignedAllocate(s, a);
        else
            return null;
    }

	override bool alignedReallocate(ref void[] b, size_t size, uint alignment) {
        return false;
    }

    override Ternary owns(void[] b) {
        static if (hasMember!(MySharedFreeList, "owns"))
            return _alloc.owns(b);
        else
            return Ternary.unknown;
    }

    override bool expand(ref void[] b, size_t s) {
        static if (hasMember!(MySharedFreeList, "expand"))
            return _alloc.expand(b, s);
        else
            return s == 0;
    }

    override bool reallocate(ref void[] b, size_t s) {
        return false;
    }

    override bool deallocate(void[] b) {
        return _alloc.deallocate(b);
    }

    override bool deallocateAll() {
        return _alloc.deallocateAll();
    }

    override Ternary empty() {

        return Ternary.unknown;

    }

    override Ternary resolveInternalPointer(void* p, ref void[] result) {
        return Ternary.unknown;
    }

    override void[] allocateAll() {
        return null;
    }
}
