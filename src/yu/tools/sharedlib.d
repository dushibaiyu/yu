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

    bool loadLib(string name)
    {
        unloadLib();
        if(name.length == 0) 
            return false;
        version(Posix){
            auto str = CStr!Mallocator(name);
             _handle = dlopen(str.ptr,RTLD_LAZY);
        } else {
            import core.stdc.stddef;
            auto len = MultiByteToWideChar(CP_UTF8, 0, name.ptr, cast(int)name.length, null, 0);
            if (len == 0) return false;
            auto buf =  cast(wchar_t[])Mallocator.instance.allocate((len+1) * wchar_t.sizeof);
            if (buf.ptr is null) return false;
            scope(exit) Mallocator.instance.deallocate(buf);
            len = MultiByteToWideChar(CP_UTF8, 0, name.ptr, cast(int)name.length, buf.ptr, len);
            if (len == 0) return false;
            buf[len] = '\0';
            _handle = LoadLibraryW(buf.ptr);
        }
        return isValid();
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
        return cast(T)getSymbol(symbol);
    }

    void * getSymbol(string symbol)
    {
        return dllSymbol(_handle, symbol);
    }

    static void * dllSymbol(LibHandle handle, string symbol)
    {
        if(handle is null || symbol.length == 0) return null;
        auto str = CStr!Mallocator(symbol);
        version (Posix)
            return dlsym(handle, str.ptr);
        else
            return GetProcAddress(handle, str.ptr);
    }

private:
    @disable this(ref SharedLib);
    LibHandle _handle = null;
}

alias SharedCLib = SharedLib;
alias SharedCPPLib = SharedLib;

import core.demangle : mangleFunc;
import core.runtime;
import yu.exception;

@trusted struct SharedDLib
{
nothrow:    
    this(string name){loadLib(name);}

    ~this(){unloadLib();}

    @property handle(){return _handle;}

    @property bool isValid() const { return _handle !is null; }

    bool loadLib(string name)
    {
        unloadLib();
        if(name.length == 0) 
            return false;
        yuCathException(Runtime.loadLibrary(name),_handle).showException;
        return isValid();
    }

    void unloadLib()
    {
        if(_handle is null) return;
        scope(exit) _handle = null; 
        yuCathException(Runtime.unloadLibrary(_handle)).showException;
    }

    auto getFunction(T)(string symbol) if(isFunctionPointer!T)
    {
        auto mangledName = mangleFunc!FUNC( functionName );
        return SharedDLib.dllSymbol(cast(SharedDLib.LibHandle)_handle, symbol);
    }

private:
    @disable this(ref SharedDLib);
    void * _handle = null;
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