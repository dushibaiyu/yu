module yu.memory;

public import yu.memory.gc;
public import std.experimental.allocator;
import std.traits;
import std.range;
import std.compiler;
import std.experimental.allocator.gc_allocator;
import std.experimental.allocator.mallocator;
public import yu.memory.allocator : StaticAlloc;


@trusted:

alias YuAlloctor = shared ISharedAllocator;
alias CAlloctor = Mallocator.instance;


shared static this() {
	import yu.memory.allocator;
    _yuAlloctor = CAlloctor.make!(GCSharedAllocator)();
}

@property YuAlloctor yuAlloctor() {
    return _yuAlloctor;
}

@property void yuAlloctor(YuAlloctor alloctor) {
    _yuAlloctor = alloctor;
}

auto yNew(T, A...)(A args) {
    return make!(T, YuAlloctor, A)(_yuAlloctor, args);
}

void yDel(T)(auto ref T* p) {
    dispose!(YuAlloctor, T)(_yuAlloctor, p);
}

void yDel(T)(auto ref T p) if (is(T == class) || is(T == interface)) {
    dispose!(YuAlloctor, T)(_yuAlloctor, p);
}

void yDel(T)(auto ref T[] array) {
    dispose!(YuAlloctor, T)(_yuAlloctor, array);
}

T[] yNewArray(T)(size_t length) {
    return makeArray!(T, YuAlloctor)(_yuAlloctor, length);
}

T[] yNewArray(T)(size_t length, auto ref T init) {
    return makeArray!(T)(_yuAlloctor, length, init);
}

Unqual!(ElementEncodingType!R)[] yNewArray(R)(R range) if (isInputRange!R && !isInfinite!R) {
    return makeArray!(YuAlloctor, R)(_yuAlloctor, range);
}

T[] yNewArray(T, R)(R range) if (isInputRange!R && !isInfinite!R) {
    return makeArray!(T, YuAlloctor, R)(_yuAlloctor, range);
}

bool yuExpandArray(T)(ref T[] array,size_t delta) {
	return expandArray!(T,YuAlloctor)(_yuAlloctor,array,delta);
}



auto cNew(T, A...)(A args) {
    return CAlloctor.make!(T)(args);
}

void cDel(T)(auto ref T* p) {
    CAlloctor.dispose(p);
}

void cDel(T)(auto ref T p) if (is(T == class) || is(T == interface)) {
    CAlloctor.dispose(p);
}

void cDel(T)(auto ref T[] array) {
    CAlloctor.dispose(array);
}

T[] cNewArray(T)(size_t length) {
    return CAlloctor.makeArray!(T)(length);
}

T[] cNewArray(T)(size_t length, auto ref T init) {
    return CAlloctor.makeArray!(T)(length, init);
}

Unqual!(ElementEncodingType!R)[] cNewArray(R)(R range) if (isInputRange!R && !isInfinite!R) {
    return CAlloctor.makeArray!(Mallocator,R)(range);
}

T[] cNewArray(T, R)(R range) if (isInputRange!R && !isInfinite!R) {
    return CAlloctor.makeArray!(T,Mallocator,R)(range);
}

bool cExpandArray(T)(ref T[] array,size_t delta) {
	return CAlloctor.expandArray(array,delta);
}


private:
__gshared YuAlloctor _yuAlloctor;
