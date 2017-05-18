module yu.tools.sharedlib;

import yu.string : CStr;
import std.traits : isFunctionPointer;
import std.experimental.allocator.mallocator : Mallocator;

@trusted struct SharedLib
{
nothrow:
@nogc:
    version(Posix)
    {
        import core.sys.posix.dlfcn;
        alias LibHandle = void *;
    }
    else version(Windows)
    {
         import core.sys.windows.windows;
         alias LibHandle = HMODULE;
    }
    else 
        static assert(0, "Unsupported operating system");
    
    this(string name){loadLib(name);}

    ~this(){unloadLib();}

    @property handle(){return _handle;}

    @property bool isValid() const { return _handle !is null; }

    void loadLib(string name)
    {
        unloadLib();
        if(name.length == 0) 
            return;
        version(Posix){
            auto str = CStr!Mallocator(name);
             _handle = dlopen(str.ptr,RTLD_LAZY);
        } else {
            auto len = MultiByteToWideChar(CP_UTF8, 0, name.ptr, cast(int)name.length, null, 0);
            if (len == 0) return;
            auto buf =  Mallocator.allocate((len+1) * wchar_t.sizeof);
            if (buf.ptr is null) return;
            scope(exit) Mallocator.deallocate(buf);
            len = MultiByteToWideChar(CP_UTF8, 0, name.ptr, cast(int)name.length, buf, len);
            if (len == 0) return;
            buf[len] = '\0';
            _handle = LoadLibraryW(buf.ptr);
        }
    }

    void unloadLib()
    {
        if(_handle is null) return;
        scope(exit) _handle = null; 
        version(Posix)
            dlclose(_handle);
        else 
            FreeLibrary(_handle);
    }

    auto getFunction(T)(string symbol) if(isFunctionPointer!T)
    {
        return cast(T)dllSymbol(symbol);
    }

    void * dllSymbol(string symbol)
    {
        if(symbol.length == 0) return null;
        auto str = CStr!Mallocator(symbol);
        version (Posix)
            return  dlsym(_handle, str.ptr);
        else
            return GetProcAddress(_handle, str.ptr);
    }

private:
    @disable this(this);
    @disable void opAssign();
    LibHandle _handle = null;
}


unittest
{
    import std.stdio;
    import std.string;

    alias getVersion = char * function() @nogc nothrow;
    
    auto lib = SharedLib("libcurl.so");
	writeln("is load : ", lib.isValid);
	if(lib.isValid){
		auto ver = lib.getFunction!getVersion("curl_version");
		writeln(fromStringz(ver()));
	}
}