module yu.memory.allocator;

public import std.experimental.allocator;
import std.traits;
import std.range;
import std.compiler;

static if(version_minor > 74) {
    alias YuAlloctor = shared RCISharedAllocator;
} 

shared static this() {
    _yuAlloctor = processAllocator;
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

void yDel(T)(T* p) {
    dispose!(YuAlloctor, T)(_yuAlloctor, p);
}

void yDel(T)(T p) if (is(T == class) || is(T == interface)) {
    dispose!(YuAlloctor, T)(_yuAlloctor, p);
}

void yDel(T)(T[] array) {
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

private:
__gshared YuAlloctor _yuAlloctor;
