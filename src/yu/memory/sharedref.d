module yu.memory.sharedref;

import core.atomic;
import std.experimental.allocator;
import std.experimental.allocator.mallocator : Mallocator;
import std.experimental.allocator.building_blocks.free_list : SharedFreeList;

static import std.algorithm;
static import std.algorithm.mutation;
import std.traits;
import yu.traits : isInheritClass, Pointer;

struct ISharedRef(Allocator, T, bool Shared = true) {
    enum isSaticAlloc = (stateSize!Allocator == 0);
    static if (isSaticAlloc)
        alias Alloc = typeof(Allocator.instance);
    else
        alias Alloc = Allocator;

    enum isShared = Shared || is(T == shared);
    enum isSharedRef = true;
    alias ValueType = Pointer!T;
    alias Deleter = void function(ref Alloc, ValueType);
    alias Data = ExternalRefCountData!(Alloc, isShared);
    alias DataWithDeleter = ExternalRefCountDataWithDeleter!(Alloc, ValueType, isShared);
    alias TWeakRef = IWeakRef!(Allocator, T, Shared);
    alias TSharedRef = ISharedRef!(Allocator, T, Shared);

    static if (isSaticAlloc) {
        this(ValueType ptr) {
            internalConstruct(ptr, &defaultDeleter);
        }

        this(ValueType ptr, Deleter deleter) {
            internalConstruct(ptr, deleter);
        }
    } else {
        this(Alloc alloc, ValueType ptr) {
            _alloc = alloc;
            internalConstruct(ptr, &defaultDeleter);
        }

        this(Alloc alloc, ValueType ptr, Deleter deleter) {
            _alloc = alloc;
            internalConstruct(ptr, deleter);
        }

        @property Alloc allocator() nothrow {
            return _alloc;
        }
    }

    this(ref scope ISharedRef rhs) {
        _dd = rhs._dd;
        _ptr = rhs._ptr;
        if (_dd) {
            _dd.strongRef();
            _dd.weakRef();
        }
        static if (!isSaticAlloc) {
            _alloc = rhs._alloc;
        }
    }

    this(WEAK)(auto ref WEAK wptr)
        if(is(WEAK == struct) && WEAK.isWeakRef && __traits(isSame, WEAK.Data, Data))
    {
        internalSet(wptr._dd, wptr._alloc, cast(ValueType)wptr._ptr);
    }

    ~this() {
        deref();
    }

    alias data this;

    @property ValueType data() nothrow {
        return _ptr;
    }

    @property bool isNull() const nothrow {
        return (_ptr is null);
    }

    pragma(inline) void swap(ref TSharedRef tref) {
        std.algorithm.mutation.swap(tref._dd, this._dd);
        std.algorithm.mutation.swap(tref._ptr, this._ptr);
        static if (!isSaticAlloc)
            std.algorithm.mutation.swap(tref._alloc, this._alloc);
    }

    pragma(inline, true) void rest() {
        clear();
    }

    pragma(inline) void clear() {
        TSharedRef copy = TSharedRef.init;
        swap(copy);
    }

    static if (isSaticAlloc) {
        pragma(inline, true) void rest()(ValueType ptr) {
            TSharedRef copy = TSharedRef(ptr);
            swap(copy);
        }

        pragma(inline, true) void rest()(ValueType ptr, Deleter deleter) {
            TSharedRef copy = TSharedRef(ptr, deleter);
            swap(copy);
        }
    } else {
        pragma(inline, true) void rest()(Alloc alloc, ValueType ptr) {
            TSharedRef copy = TSharedRef(alloc, ptr);
            swap(copy);
        }

        pragma(inline, true) void rest()(Alloc alloc, ValueType ptr, Deleter deleter) {
            TSharedRef copy = TSharedRef(alloc, ptr, deleter);
            swap(copy);
        }
    }

    TWeakRef toWeakRef() {
        return TWeakRef(this);
    }

    auto castTo(U)() {
        ISharedRef!(Alloc, U, isShared) result;
        if (isNull)
            return result;
        alias CastType = Pointer!U;
        CastType u = cast(CastType) _ptr;
        if (u !is null)
            result.internalSet(_dd, _alloc, u);
        return result;
    }

    void opAssign(THIS)(auto ref THIS rv)if(is(THIS : typeof(this))){
        if(rv._dd is _dd) return;
        auto copy = cast(typeof(this))rv;
        swap(copy);
    }

    void opAssign(WEAK)(auto ref WEAK rhs)
        if(is(WEAK == struct) && WEAK.isWeakRef && __traits(isSame, WEAK.Data, Data))
    {
        internalSet(rhs._dd, rhs._alloc, cast(ValueType)rhs._ptr);
    }

    static if (isPointer!ValueType) {
        ref T opUnary(string op)() if (op == "*") {
            return *_ptr;
        }
    }

private:

    static void defaultDeleter(ref Alloc alloc, ValueType value)  {
        alloc.dispose(value);
    }

    void deref() {
        _ptr = null;
        deref(_dd, _alloc);
    }

    static void deref(ref Data dd, ref Alloc alloc) {
        if (!dd)
            return;
        if (!dd.strongDef()) {
            dd.free(alloc);
        }
        if (!dd.weakDef()) {
            scope(exit) dd = null;
            sharedRefAllocator.dispose(dd);
        }
    }

    void internalConstruct(ValueType ptr, Deleter deleter) {
        _ptr = ptr;
        if (ptr !is null) {
            _dd = sharedRefAllocator.make!(DataWithDeleter)(ptr, deleter);
            static if(hasMember!(T,"__InitializeFromSharedPointer")) {
                auto tpytr = cast(Unqual!ValueType)(_ptr);
                tpytr.__InitializeFromSharedPointer(this);
            }
        }
    }

    void internalSet(Data o, ref Alloc alloc, ValueType ptr) {
        static if (!isSaticAlloc) {
            Alloc tmpalloc = _alloc;
            _alloc = alloc;
        } else {
            alias tmpalloc = Alloc.instance;
        }
        if (o) {
            if (o.strongref > 0) {
                o.strongRef();
                o.weakRef();
                _ptr = ptr;
            } else {
                _ptr = null;
                o = null;
            }
        }
        std.algorithm.mutation.swap(_dd, o);
        deref(o, tmpalloc);
    }

    ValueType _ptr; //
    Data _dd;
    static if (!isSaticAlloc)
        Alloc _alloc;
    else
        alias _alloc = Alloc.instance;
}

struct IWeakRef(Allocator, T, bool Shared = true) {
    enum isSaticAlloc = (stateSize!Allocator == 0);
    static if (isSaticAlloc)
        alias Alloc = typeof(Allocator.instance);
    else
        alias Alloc = Allocator;
    enum isShared =  Shared || is(T == shared);
    enum isWeakRef = true;
    alias ValueType = Pointer!T;
    alias Data = ExternalRefCountData!(Alloc, isShared);
    alias TWeakRef = IWeakRef!(Allocator, T, Shared);
    alias TSharedRef = ISharedRef!(Allocator,T, Shared);

    this(SHARED)(auto ref SHARED tref)
        if(is(SHARED == struct) && SHARED.isSharedRef && __traits(isSame, SHARED.Data, Data))
    {
        this._ptr = cast(ValueType)tref._ptr;
        this._dd = tref._dd;
        if (_dd)
            _dd.weakRef();
        static if (!isSaticAlloc)
            this._alloc = tref._alloc;
    }

    this(ref scope IWeakRef rhs) {
        _dd = rhs._dd;
        _ptr = rhs._ptr;
        if (_dd)
            _dd.weakRef();
        static if (!isSaticAlloc) {
            _alloc = rhs._alloc;
        }
    }

    pragma(inline, true) bool isNull() nothrow {
        return (_dd is null || _ptr is null || _dd.strongref == 0);
    }

    pragma(inline, true) ValueType data() nothrow {
        return isNull() ? null : _ptr;
    }

    pragma(inline) void clear() {
        TWeakRef copy = TWeakRef.init;
        swap(copy);
    }

    pragma(inline) void swap(ref TWeakRef tref) {
        std.algorithm.mutation.swap(tref._dd, this._dd);
        std.algorithm.mutation.swap(tref._ptr, this._ptr);
        static if (!isSaticAlloc)
            std.algorithm.mutation.swap(tref._alloc, this._alloc);
    }

    pragma(inline, true) TSharedRef toStrongRef() {
        return TSharedRef(this);
    }

    void opAssign(THIS)(auto ref THIS rv)if(is(THIS : typeof(this))){
        if(rv._dd is _dd) return;
        auto copy = rv;
        swap(copy);
    }

    void opAssign(SHARED)(auto ref SHARED rhs)
        if(is(SHARED == struct) && SHARED.isSharedRef && __traits(isSame, SHARED.Data, Data))
    {
        internalSet(rhs._dd, rhs._alloc, cast(ValueType)rhs._ptr);
    }

private:
    void deref() {
        _ptr = null;
        if (!_dd) return;
        if (!_dd.weakDef()) {
            scope(exit) _dd = null;
            sharedRefAllocator.dispose(_dd);
        }
    }

    void internalSet(Data o, ref Alloc alloc, ValueType ptr) {
        if (_dd is o)
            return;
        if (o) {
            o.weakRef();
            _ptr = ptr;
        }
        if (_dd && !_dd.weakDef())
            sharedRefAllocator.dispose(_dd);
        _dd = o;
        static if (!isSaticAlloc)
            _alloc = alloc;
    }

    ValueType _ptr; // 只为保留指针在栈中，如果指针是GC分配的内存，而ExternalRefCountData非GC的，则不用把非GC内存添加到GC的扫描列表中
    Data _dd;
    static if (!isSaticAlloc)
        Alloc _alloc;
    else
        alias _alloc = Alloc.instance;
}


private:
static shared SharedFreeList!(Mallocator, chooseAtRuntime) sharedRefAllocator;

abstract class ExternalRefCountData(Alloc, bool isShared) {
    pragma(inline, true) final int strongDef() nothrow {
        static if (isShared)
            return atomicOp!("-=")(_strongref, 1);
        else
            return --_strongref;
    }

    pragma(inline, true) final int strongRef() nothrow {
        static if (isShared)
            return atomicOp!("+=")(_strongref, 1);
        else
            return ++_strongref;
    }

    pragma(inline, true) final int weakDef() nothrow {
        static if (isShared)
            return atomicOp!("-=")(_weakref, 1);
        else
            return --_weakref;
    }

    pragma(inline, true) final int weakRef() nothrow {
        static if (isShared)
            return atomicOp!("+=")(_weakref, 1);
        else
            return ++_weakref;
    }

    pragma(inline, true) final @property int weakref() nothrow {
        static if (isShared)
            return atomicLoad(_weakref);
        else
            return _weakref;
    }

    pragma(inline, true) final @property int strongref() nothrow {
        static if (isShared)
            return atomicLoad(_strongref);
        else
            return _strongref;
    }

    void free(ref Alloc alloc);

    static if (isShared) {
        shared int _weakref = 1;
        shared int _strongref = 1;
    } else {
        int _weakref = 1;
        int _strongref = 1;
    }
}

final class ExternalRefCountDataWithDeleter(Alloc, ValueType, bool isShared)
    : ExternalRefCountData!(Alloc, isShared) {
    //pragma(msg, "is  ahsred " ~ isShared.stringof);
    alias Deleter = void function(ref Alloc, ValueType);

    this(ValueType ptr, Deleter dele) {
        value = ptr;
        deleater = dele;
    }

    override void free(ref Alloc alloc) {
        if (deleater && value)
            deleater(alloc, value);
        deleater = null;
        value = null;
    }

    Deleter deleater;
    ValueType value;
}
