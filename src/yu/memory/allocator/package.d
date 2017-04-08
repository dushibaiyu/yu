module yu.memory.allocator;

public import std.experimental.allocator;
import std.traits;
import std.range;

shared static this() {
    _yuAlloctor = processAllocator;
}

@property IAllocator yuAlloctor() {
    return _yuAlloctor;
}

@property void yuAlloctor(IAllocator alloctor) {
    _yuAlloctor = alloctor;
}

auto yNew(T, A...)(A args) {
    return make!(T, IAllocator, A)(_yuAlloctor, args);
}

void yDel(T)(T* p) {
    dispose!(IAllocator, T)(_yuAlloctor, p);
}

void yDel(T)(T p) if (is(T == class) || is(T == interface)) {
    dispose!(IAllocator, T)(_yuAlloctor, p);
}

void yDel(T)(T[] array) {
    dispose!(IAllocator, T)(_yuAlloctor, array);
}

T[] yNewArray(T, Allocator)(size_t length) {
    return makeArray!(T, IAllocator)(_yuAlloctor, length);
}

T[] yNewArray(T)(size_t length, auto ref T init) {
    return makeArray!(T)(_yuAlloctor, length, init);
}

Unqual!(ElementEncodingType!R)[] yNewArray(R)(R range) if (isInputRange!R && !isInfinite!R) {
    return makeArray!(IAllocator, R)(_yuAlloctor, range);
}

T[] yNewArray(T, R)(R range) if (isInputRange!R && !isInfinite!R) {
    return makeArray!(T, IAllocator, R)(_yuAlloctor, range);
}

private:
__gshared IAllocator _yuAlloctor;
