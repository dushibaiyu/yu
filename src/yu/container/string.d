module yu.container.string;

import yu.container.common;

// The Cow String
struct StringImpl(Char, Allocator)
{
    alias Data = StringData!(Char,Allocator);
    static if(StaticAlloc!Allocator){
        this(const Char[] data)
        {}
    } else {
        @disable this();
        this(const Char[] data, auto ref Allocator alloc)
        {
            _alloc = alloc;
        }

        this( auto ref Allocator alloc){
            _alloc = alloc;
        }
    }

    this(this){
        Data.inf(_data);
    }

    ~this(){
        Data.deInf(_alloc,_data);
    }

    mixin AllocDefine!Allocator;
private:
    Data * _data;
    Char[] _str;
}

private:
/// String Cow Data
struct StringData(CHAR, Allocator)
{
    ~this()
    {
        if (data)
            _alloc.deallocate(data);
    }

    mixin AllocDefine!Allocator;
    CHAR[] data;

    mixin Refcount!();
}
