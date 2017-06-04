module yu.container.vector;

import core.memory;
import std.exception;
import std.experimental.allocator;
import std.experimental.allocator.mallocator;
import std.experimental.allocator.gc_allocator;
import std.traits;
import core.stdc.string : memset, memcpy;
import yu.container.common;

template ShouleNotCOW(T) 
{
    enum ShouleNotCOW = (hasIndirections!T || (is(T == struct) && hasElaborateCopyConstructor!T));
}

@trusted struct Vector(T, Allocator = GCAllocator, bool addInGC = true) if(ShouleNotCOW!T){
    enum addToGC = addInGC && hasIndirections!T && !is(Unqual!Allocator == GCAllocator);
    enum shouldInit = hasIndirections!T || hasElaborateDestructor!T;
    static if (hasIndirections!T)
        alias InsertT = T;
    else
        alias InsertT = const T;

    static if (StaticAlloc!Allocator) {
        this(size_t size) {
            reserve(size);
        }

        this(InsertT[] data) {
            insertBack(data);
        }
    } else {
        @disable this();
        this(InsertT[] data, Allocator alloc) {
            this._alloc = alloc;
            insertBack(data);
        }

        this(size_t size, Allocator alloc) {
            this._alloc = alloc;
            reserve(size);
        }

        this(Allocator alloc) {
            this._alloc = alloc;
        }
    } 
    @disable this(this);

    ~this() {
        if (_data.ptr) {
           clear();
            static if (addToGC)
                GC.removeRange(_data.ptr);
            _alloc.deallocate(_data);
            _data = null;
        }
    }

    void insertBack(InsertT value) {
        if (full)
            exten();
        _data[_len] = value;
        ++_len;
    }

    void insertBack(InsertT[] value) {
        if (_data.length < (_len + value.length))
            exten(value.length);
        auto len = _len + value.length;
        _data[_len .. len] = value[];
        _len = len;
    }

    alias put = insertBack;
    alias pushBack = insertBack;

    size_t removeBack(size_t howMany = 1) {
        if (howMany >= _len) {
            clear();
            return _len;
        }
        auto size = _len - howMany;
        _data[size .. _len] = T.init;
        _len = size;
        return howMany;
    }

    void removeSite(size_t site) {
        assert(site < _len);
        --_len;
        for (size_t i = site; i < _len; ++i) {
            _data[i] = _data[i + 1];
        }
        _data[_len] = T.init;
    }

    alias removeIndex = removeSite;

    void removeOne(InsertT value) {
        for (size_t i = 0; i < _len; ++i) {
            if (_data[i] == value) {
                removeSite(i);
                return;
            }
        }
    }

    void removeAny(InsertT value) {
        auto len = _len;
        size_t rm = 0;
        size_t site = 0;
        for (size_t j = site; j < len; ++j) {
            if (_data[j] != value) {
                _data[site] = _data[j];
                site++;
            } else {
                rm++;
            }
        }
        len -= rm;
        _data[len .. _len] = T.init;
        _len = len;
    }

    pragma(inline) @property ptr() {
        return _data.ptr;
    }

    pragma(inline) @property T[] dup() {
        auto list = new T[length];
        list[0 .. length] = _data[0 .. length];
        return list;
    }

    pragma(inline) T[] data(bool rest = false) {
        auto list = _data[0 .. length];
        if (rest) {
            _data = null;
            _len = 0;
        }
        return list;
    }

    pragma(inline) ref inout(T) opIndex(size_t i) inout {
        assert(i < _len);
        return _data[i];
    }

    pragma(inline) size_t opDollar() const {
        return _len;
    }

    pragma(inline) void opOpAssign(string op)(InsertT value) if (op == "~") {
        insertBack(value);
    }

    pragma(inline) void opOpAssign(string op)(InsertT[] value) if (op == "~") {
        insertBack(value);
    }

    pragma(inline) void opOpAssign(string op)(typeof(this) s) if (op == "~") {
        insertBack(s.data);
    }

    void opAssign(typeof(this) s) {
        clear();
        insertBack(s.data);
        static if (!StaticAlloc!Allocator)
            this._alloc = s._alloc;
    }

    pragma(inline) void opAssign(T[] data) {
        clear();
        insertBack(data);
    }

    pragma(inline, true) T at(size_t i) {
        assert(i < _len);
        return _data[i];
    }

    pragma(inline, true) const @property bool empty() {
        return (_len == 0);
    }

    pragma(inline, true) const @property size_t length() {
        return _len;
    }

    pragma(inline, true) void clear() {
        static if (shouldInit){
            if (_len > 0) _data[0 .. _len] = T.init;
        }
        _len = 0;
    }

    void reserve(size_t elements) {
        if (elements <= _data.length)
            return;
        size_t len = _alloc.goodAllocSize(elements * T.sizeof);
        elements = len / T.sizeof;
        auto ptr = cast(T*) enforce(_alloc.allocate(len).ptr);
        T[] data = ptr[0 .. elements];
        memset(ptr, 0, len);
        if (_len > 0) {
            memcpy(ptr, _data.ptr, (_len * T.sizeof));
        }
        static if (addToGC) {
            GC.addRange(ptr, len);
            if (_data.ptr) {
                GC.removeRange(_data.ptr);
                _alloc.deallocate(_data);
            }
        } else {
            if (_data.ptr) {
                _alloc.deallocate(_data);
            }
        }
        _data = data;
    }

    mixin AllocDefine!Allocator;
private:
    pragma(inline, true) bool full() {
        return length >= _data.length;
    }

    pragma(inline) void exten(size_t len = 0) {
        auto size = _data.length + len;
        if (size > 0)
            size = size > 128 ? size + ((size / 3) * 2) : size * 2;
        else
            size = 32;
        reserve(size);
    }

private:
    size_t _len = 0;
    T[] _data = null;
}

@trusted struct Vector(T, Allocator = Mallocator) if(!ShouleNotCOW!T)
{
    enum bool shouleInit = hasElaborateDestructor!T;
    alias Data =  ArrayCOWData!(T, Allocator);

    static if (StaticAlloc!Allocator)
    {
        this(size_t size)
        {
            reserve(size);
        }

        this(const T[] data)
        {
            assign(data);
        }
    }
    else
    {
        @disable this();
        this(size_t size,Allocator alloc)
        {
            _alloc = alloc;
            reserve(size);
        }

        this(const T[] data,Allocator alloc)
        {
            _alloc = alloc;
            assign(data);
        }

        this(Allocator alloc)
        {
            _alloc = alloc;
        }
    }

    this(this)
    {
        Data.inf(_data);
    }

    ~this()
    {
        Data.deInf(_alloc, _data);
    }

    void append(S)(auto ref S value) if(is(Unqual!S == T) || is(S : const T[]))
    {
        this.opOpAssign!("~",S)(value);
    }

    alias insertBack = append;
    alias put = append;
    alias pushBack = append;

   size_t removeBack(size_t howMany = 1) {
        if(howMany == 0 ) 
            return 0;
        if (howMany >= _array.length) {
            size_t len = _array.length;
            clear();
            return len;
        }
        auto size = _array.length - howMany;
        static if(shouleInit) 
            _array[size .. $] = T.init;
        _array = _array[0 .. size];
        return howMany;
    }

    void removeSite(size_t site) 
    in {
        assert(site < _array.length);
    } body{
        if(_array.length == 0) 
            return;
        doCOW(0);
        const size_t len = _array.length - 1;
        for (size_t i = site; i < len; ++i) {
            _array[i] = _array[i + 1];
        }
        static if(shouleInit) _array[len] = T.init;
        _array = _array[0..len];
    }

    bool removeOne(S)(auto ref S value) if(is(Unqual!S == T)) {
        doCOW(0);
        for (size_t i = 0; i < _array.length; ++i) {
            if (_array[i] == value) {
                removeSite(i);
                return true;
            }
        }
        return false;
    }

    size_t removeAny(S)(auto ref S value) if(is(Unqual!S == T)) {
        doCOW(0);
       // auto len = _array.length;
        size_t rm = 0;
        size_t site = 0;
        for (size_t j = site; j < _array.length; ++j) {
            if (_array[j] != value) {
                if(site != j) _array[site] = _array[j];
                site++;
            } else {
                rm++;
            }
        }
        if(rm > 0)
            removeBack(rm);
        return rm;
    }

    alias removeIndex = removeSite;

    void clear(){
        if(_data !is null && _data.count > 1){
            Data.deInf(_alloc,_data);
            _data = null;
        } else {
            static if(shouleInit) 
                _array[] = T.init;
        }
        _array = null;
    }

    void opIndexAssign(S)(auto ref S value,size_t index) if(is(Unqual!S == T))
    in{
        assert(index < _array.length);
    }body{
        doCOW(0);
        _array[index] = value;
    }

    T opIndex(size_t index) const
    in{
        assert(index < _array.length);
    } body{
        return _array[index];
    }

    bool opEquals(S)(S other) const 
		if(is(S == Unqual!(typeof(this))) || is(S : const T[]))
	{
		if(_array.length == other.length){
            for(size_t i = 0; i < _array.length; ++ i) {
                if(_array[i] != other[i]) 
                    return false;
            }
            return true;
        } else
            return false;
    }

    size_t opDollar(){return _array.length;}

     mixin AllocDefine!Allocator;

    void opAssign(typeof(this) n) {
		if(n._data !is _data){
            Data.deInf(_alloc,_data);
            _data = n._data;
            Data.inf(_data);
        }
        _array = n._array;
    }

    void opAssign(const T[] input) {
		assign(input);
    }

    @property bool empty() const nothrow {
            return _array.length == 0;
    }

    @property size_t length()const nothrow {return _array.length;}

    int opApply(scope int delegate(ref T) dg)
    {
        int result = 0;

        for (size_t i = 0; i < _array.length; i++)
        {
            result = dg(_array[i]);
            if (result)
                break;
        }
        return result;
    }

    int opApply(scope int delegate(size_t, ref T) dg)
    {
        int result = 0;

        for (size_t i = 0; i < _array.length; i++)
        {
            result = dg(i, _array[i]);
            if (result) break;
        }
        return result;
    }

    @property typeof(this) dup() {
		typeof(this) ret = this;
        if(this._data !is null)
            ret.doCOW(0);
        return ret;
    }

    T[] idup(){
        return _array.dup;
    }

    immutable (T)[] data()
    {
        return cast(immutable (T)[])_array;
    }

    @property const(T) * ptr() const {
        return _array.ptr;
    }

    typeof(this) opBinary(string op,S)(auto ref S other) 
		if((is(S == Unqual!(typeof(this))) || is(S : const T[])) && op == "~")
	{
		typeof(this) ret = this;
        ret ~= other;
        return ret;
    }

    void opOpAssign(string op,S)(auto ref S other) 
        if((is(S == Unqual!(typeof(this))) || is(S : const T[]) || is(Unqual!S == T)) && op == "~") 
    {
        static if(is(Unqual!S == T)){
            const size_t tmpLength = 1;
        } else {
            if(other.length == 0) return;
            const size_t tmpLength = other.length;
        }
        doCOW(tmpLength);
        T * tptr = _data.data.ptr + _array.length;
        static if(is(Unqual!S == T)){
            tptr[0] = other;
        } else {
            memcpy(tptr, other.ptr, (tmpLength * T.sizeof));
        }
        tptr = _data.data.ptr;
        size_t len = _array.length + tmpLength;
        _array = tptr[0..len];
    }
    
     void reserve(size_t elements) {
         if(elements < _array.length)
            removeBack(_array.length - elements);
        else if(elements > _array.length)
            doCOW(elements - _array.length);
     }

private:
    void assign(const T[] input)
    {
        if(input.length == 0){
            clear();
            return;
        }
        auto data = buildData();
        Data.deInf(_alloc,data);
        _data.reserve(input.length);
        size_t len = input.length * T.sizeof;
        memcpy(_data.data.ptr, input.ptr, len);
        _array = _data.data[0..input.length];
    }

    void doCOW(size_t tmpLength = 0)
    {
        auto data = buildData();
        if(data !is null) {
            _data.reserve(extenSize(tmpLength));
            if(_array.length > 0){
                memcpy(_data.data.ptr, _array.ptr, (_array.length * T.sizeof));
                _array = _data.data[0.. _array.length];
            }
            Data.deInf(_alloc,data);
        } else if(tmpLength > 0 && _data.reserve(extenSize(tmpLength))) {
                _array = _data.data[0.. _array.length];
        }
    }

    Data * buildData(){
        Data* data  = null;
        if(_data !is null && _data.count > 1){
            data = _data;
            _data = null;
        }
        if(_data is null) {
            _data = Data.allocate(_alloc);
            static if(!StaticAlloc!Allocator)
                _data._alloc = _alloc;
        }
        return data;
    }

    size_t extenSize(size_t size) {
        size += _array.length;
        if (size > 0)
            size = size > 128 ? size + ((size / 3) * 2) : size * 2;
        else
            size = 32;
        return size;
    }


private:
    Data* _data;
    T[] _array;
}

unittest {
    import std.stdio;
    import std.experimental.allocator.mallocator;
    import std.experimental.allocator;

    Vector!(int) vec; // = Vector!int(5);
    int[] aa = [0, 1, 2, 3, 4, 5, 6, 7];
    vec.insertBack(aa);
    assert(vec.length == 8);

    vec.insertBack(10);
    assert(vec.length == 9);

    Vector!(int) vec21;
    vec21 ~= 15;
    vec21 ~= vec;
    assert(vec21.length == 10);

    assert(vec21.data == [15, 0, 1, 2, 3, 4, 5, 6, 7, 10]);

    vec21[1] = 500;
    assert(vec21.data == [15, 500, 1, 2, 3, 4, 5, 6, 7, 10]);

    vec21.removeBack();
    assert(vec21.length == 9);
    assert(vec21.data == [15, 500, 1, 2, 3, 4, 5, 6, 7]);

    vec21.removeBack(3);
    assert(vec21.length == 6);
    assert(vec21.data == [15, 500, 1, 2, 3, 4]);

    vec21.insertBack(aa);
    assert(vec21.data == [15, 500, 1, 2, 3, 4, 0, 1, 2, 3, 4, 5, 6, 7]);

    vec21.removeSite(1);
    assert(vec21.data == [15, 1, 2, 3, 4, 0, 1, 2, 3, 4, 5, 6, 7]);

    vec21.removeOne(1);
    assert(vec21.data == [15, 2, 3, 4, 0, 1, 2, 3, 4, 5, 6, 7]);

    vec21.removeAny(2);
    assert(vec21.data == [15, 3, 4, 0, 1, 3, 4, 5, 6, 7]);

    Vector!(ubyte[], Mallocator) vec2;
    vec2.insertBack(cast(ubyte[]) "hahaha");
    vec2.insertBack(cast(ubyte[]) "huhuhu");
    assert(vec2.length == 2);
    assert(cast(string) vec2[0] == "hahaha");
    assert(cast(string) vec2[1] == "huhuhu");

    Vector!(int, IAllocator) vec22 = Vector!(int, IAllocator)(allocatorObject(Mallocator.instance));
    int[] aa22 = [0, 1, 2, 3, 4, 5, 6, 7];
    vec22.insertBack(aa22);
    assert(vec22.length == 8);

    vec22.insertBack(10);
    assert(vec22.length == 9);

    vec22.insertBack(aa22);
    vec22.insertBack([0, 1, 2, 1, 212, 1215, 1545, 1212, 154, 51515, 1545,
        1545, 1241, 51, 45, 1215, 12415, 12415, 1545, 12415, 1545, 152415,
        1541515, 15415, 1545, 1545, 1545, 1545, 15454, 0, 54154]);

    vec22 ~=  [0, 1, 2, 1, 212];
}
