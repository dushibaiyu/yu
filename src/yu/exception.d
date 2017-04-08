module yu.exception;

public import std.exception : basicExceptionCtors;

mixin template ExceptionBuild(string name, string parent = "") {
    enum buildStr = "class " ~ name ~ "Exception : " ~ parent ~ "Exception { \n\t" ~ "mixin basicExceptionCtors;\n }";
    mixin(buildStr);
}

mixin ExceptionBuild!("Yu");

mixin template ThrowExceptionBuild() {
    ///Note:from GC
    pragma(inline, true) void throwExceptionBuild(string name = "")(string msg = "",
        string file = __FILE__, size_t line = __LINE__) {
        mixin("throw new " ~ name ~ "Exception(msg,file,line);");
    }
}

pragma(inline) void showException(bool gcfree = false, int line = __LINE__,
    string file = __FILE__, string funcName = __FUNCTION__)(Exception e) nothrow {
    import std.experimental.logger;
    import std.exception;

    collectException(error!(line, file, funcName)(e.toString));
    static if (gcfree) {
        import yu.memory.gc;

        collectException(gcFree(e));
    }

}

string buildErroCodeException(T)() if (is(T == enum)) {
    string str = "mixin ExceptionBuild!(\"" ~ T.stringof ~ "\");\n";
    foreach (memberName; __traits(derivedMembers, T)) {
        str ~= "mixin ExceptionBuild!(\"" ~ memberName ~ "\", \"" ~ T.stringof ~ "\");\n";
    }
    return str;
}

bool yuCathException(bool gcfree, E)(lazy E expression) nothrow {
    import std.experimental.logger;
    import std.exception : collectException;
    import std.stdio;

    try {
        expression();
        return true;
    }
    catch (Exception e) {
        showException!(gcfree)(e);
    }
    catch (Error e) {
        collectException({ error(e.toString); writeln(e.toString()); }());
        import core.stdc.stdlib;

        exit(-1);
    }
    return false;
}

bool yuCathException(bool gcfree, E, T)(lazy E expression, ref T value) nothrow {
    import std.experimental.logger;
    import std.exception : collectException;
    import std.stdio;

    try {
        value = expression();
        return true;
    }
    catch (Exception e) {
        showException!(gcfree)(e);
    }
    catch (Error e) {
        collectException({ error(e.toString); writeln(e.toString()); }());
        import core.stdc.stdlib;

        exit(-1);
    }
    return false;
}

version (unittest) {
    enum Test {
        MyTest1,
        MyTest2,
    }
    //mixin ExceptionBuild!"MyTest1";
    //mixin ExceptionBuild!"MyTest2";
    mixin(buildErroCodeException!Test());
    mixin ThrowExceptionBuild;
}

unittest {
    import std.stdio;
    import std.exception;

    auto e = collectException!TestException(throwExceptionBuild!"Test"("test Exception"));
    assert(e !is null);
    auto e1 = collectException!MyTest1Exception(throwExceptionBuild!"MyTest1"("test Exception"));
    assert(e1 !is null);
    auto e2 = collectException!MyTest2Exception(throwExceptionBuild!"MyTest2"("test Exception"));
    assert(e2 !is null);
}
