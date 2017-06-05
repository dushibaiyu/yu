module yu.container.vector;

import core.memory;
import std.exception;
import std.experimental.allocator;
import std.experimental.allocator.mallocator;
import std.experimental.allocator.gc_allocator;
import std.traits;
import core.stdc.string : memcpy;
import yu.container.common;

/**
* copy  有三种类型：
    1. COW： 对于不含有引用类型的值类型， 并且没有自定义 赋值函数 和 copy赋值函数
    2. 深Copy： 对于有自定义 赋值函数 和 copy赋值函数的值类型
    2. 不允许copy： 对于引用类型或者含有引用类型的值类型
*/

@trusted struct Vector(T, Allocator = Mallocator, bool addInGC = true) //if(!(hasIndirections!T))
{
    enum addToGC = addInGC && hasIndirections!T && !is(Unqual!Allocator == GCAllocator);
    enum shouleInit = hasIndirections!T || hasElaborateDestructor!T;
    alias Data =  ArrayCOWData!(T, Allocator,addToGC);
    static if (hasIndirections!T)
        alias InsertT = T;
    else
        alias InsertT = const T;

    static if (StaticAlloc!Allocator)
    {
        this(size_t size)
        {
            reserve(size);
        }

        this(S)(S[] data) if(is(S : InsertT))
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

        this(S)(S[] data,Allocator alloc)  if(is(S : InsertT))
        {
            _alloc = alloc;
            assign(data);
        }

        this(Allocator alloc)
        {
            _alloc = alloc;
        }
    }
    mixin AllocDefine!Allocator;
    static if(hasIndirections!T){
        alias DestroyFun = void function(ref Alloc alloc,ref T) nothrow;
        private DestroyFun _fun;
        @property void destroyFun(DestroyFun fun){_fun = fun;}
        @property DestroyFun destroyFun(){return _fun;}

        private void doDestroy(ref T d){
            if(_fun)
                _fun(_alloc, d);
        }
        private void doDestroy(T[] d){
            if(_fun) {
                for(size_t i  = 0; i < d.length; ++i)
                _fun(_alloc, d[i]);
            }
        }
    } else {
        this(this)
        {
            Data.inf(_data);
            static if(hasElaborateCopyConstructor!T || hasElaborateAssign!T)
                doCOW(0);
        }
    }

    ~this()
    {
        Data.deInf(_alloc, _data);
    }

    void append(S)(auto ref S value) if(is(S : InsertT) || is(S : InsertT[]))
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
        static if(hasIndirections!T) doDestroy(_array[size .. $]);
        static if(shouleInit) _array[size .. $] = T.init;
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
        static if(hasIndirections!T) doDestroy(_array[len]);
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
            static if(hasIndirections!T) doDestroy(_array);
            static if(shouleInit)_array[] = T.init;
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

    auto opIndex(size_t index) const
    in{
        assert(index < _array.length);
    } body{
        return _array[index];
    }

    auto opIndex(size_t index)
    in{
        assert(index < _array.length);
    } body{
        return _array[index];
    }

    bool opEquals(S)(S other) const 
		if(is(S == Unqual!(typeof(this))) || is(S : InsertT[]))
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

    void opAssign(S)(auto ref S n) if((is(S == Unqual!(typeof(this))) && !(hasIndirections!T)) || is(S : InsertT[]))
    {
        static if(is(S : InsertT[])){
            assign(n);
        } else {
            if(n._data !is _data){
                Data.deInf(_alloc,_data);
                _data = n._data;
                Data.inf(_data);
            }
            _array = n._array;
            static if(hasElaborateCopyConstructor!T || hasElaborateAssign!T)
                doCOW(0);
        }
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
		if((is(S == Unqual!(typeof(this))) || is(S : InsertT[])) && op == "~")
	{
		typeof(this) ret = this;
        ret ~= other;
        return ret;
    }

    void opOpAssign(string op,S)(auto ref S other) 
        if((is(S == Unqual!(typeof(this))) || is(S : InsertT[]) || is(S : InsertT)) && op == "~") 
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
    void assign(S)(S[] input) if(is(S : InsertT))
    {
        clear();
        if(input.length == 0) return;
        auto data = buildData();
        Data.deInf(_alloc,data);
        _data.reserve(input.length);
        assign(_data.data.ptr,input);
        _array = _data.data[0..input.length];
    }

    pragma(inline)
    void assign(S)(T * array,S[] data)if(is(S : InsertT))
    {
        static if(hasElaborateCopyConstructor!T || hasElaborateAssign!T){
            for(size_t i  = 0; i < data.length; ++i)
                array[i] = data[i];
        } else {
            memcpy(array, data.ptr, (data.length * T.sizeof));
        }
    }

    void doCOW(size_t tmpLength = 0)
    {
        auto data = buildData();
        if(data !is null) {
            _data.reserve(extenSize(tmpLength));
            if(_array.length > 0){
                assign(_data.data.ptr, _array);
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
