module yu.string;

import std.array;
import std.string;
import std.traits;
import std.range;
import yu.memory;
import core.stdc.string : memcpy;

 @trusted  void splitNameValue(TChar, Char, bool caseSensitive = true)(TChar[] data,
    in Char pDelim, in Char vDelim, scope bool delegate(TChar[], TChar[]) callback) if (
        isSomeChar!(Unqual!TChar) && isSomeChar!(Unqual!Char))  {
    enum size_t blen = 1;
    enum size_t elen = 1;
    const dchar pairDelim = pDelim;
    const dchar valueDelim = vDelim;

    mixin(TSplitNameValue!());
}

 @trusted  void splitNameValue(TChar, Char, bool caseSensitive = true)(TChar[] data,
    const(Char)[] pairDelim, const(Char)[] valueDelim, scope bool delegate(TChar[],
    TChar[]) callback) if (isSomeChar!(Unqual!TChar) && isSomeChar!(Unqual!Char)) {
    const size_t blen = pairDelim.length;
    const size_t elen = valueDelim.length;

    mixin(TSplitNameValue!());

}

 @trusted  bool isSameIngnoreLowUp(TChar)(TChar[] s1, TChar[] s2) if (isSomeChar!(Unqual!TChar)) {
    import std.uni;

    if (s1.length != s2.length)
        return false;
    for (size_t i = 0; i < s1.length; ++i) {
        dchar c1 = toLower(s1[i]);
        dchar c2 = toLower(s2[i]);
        if (c1 != c2)
            return false;
    }
    return true;
}

@trusted struct CStr{
@nogc nothrow:
    @disable this();
    @disable this(ref CStr);

	this(string str) {
		setString(str);
	}

    ~this() {
        if (_data.ptr !is null)
            cDel(_data);
    }

    @property const(char*) ptr() const nothrow{
        return _data.ptr;
    }

    @property length() const nothrow {
        return _data.length - 1;
    }

private:
    void setString(string str) {
        if (str.length == 0)
            return;
        size_t size = str.length + 1;
        _data = cNewArray!char(size);
        if (_data.length == 0)
            return;
        memcpy(_data.ptr, str.ptr, str.length);
        _data[str.length] = '\0';
    }
    char[] _data;
}


@safe ubyte formHex(in char[2] chs) {
    import std.uri;

    @safe pure ubyte charToByte(dchar ch) {
        switch (ch) {
        case '0':
            return 0x00;
        case '1':
            return 0x01;
        case '2':
            return 0x02;
        case '3':
            return 0x03;
        case '4':
            return 0x04;
        case '5':
            return 0x05;
        case '6':
            return 0x06;
        case '7':
            return 0x07;
        case '8':
            return 0x08;
        case '9':
            return 0x09;
        case 'A':
            return 0x0A; // 10
        case 'B':
            return 0x0B; // 11
        case 'C':
            return 0x0C; // 12
        case 'D':
            return 0x0D; // 13
        case 'E':
            return 0x0E; // 14
        case 'F':
            return 0x0F; // 15
        default:
            throw new StringException("Hex char is inVaild!");
        }
    }

    import std.uni;

    dchar ch = toUpper(chs[0]);
    ubyte frist = charToByte(ch);
    ch = toUpper(chs[1]);
    ubyte seced = charToByte(ch);
    return cast(ubyte)((frist << 4) | seced);
}


private template TSplitNameValue() {
    enum TSplitNameValue = q{
		static if(caseSensitive)
			enum thecaseSensitive = CaseSensitive.yes;
		else
			enum thecaseSensitive = CaseSensitive.no;
		while(data.length > 0)
		{
			auto index = data.indexOf(pairDelim,thecaseSensitive);
			string keyValue;
			if(index < 0){
				keyValue = data;
				data.length = 0;
			} else {
				keyValue = data[0..index];
				data = data[(index + blen) .. $];
			}
			if(keyValue.length == 0)
				continue;
			auto valueDelimPos = keyValue.indexOf(valueDelim,thecaseSensitive);
			if(valueDelimPos < 0){
				if(!callback(keyValue,string.init))
					return;
			} else {
				auto name = keyValue[0..valueDelimPos];
				auto value = keyValue[(valueDelimPos + elen)..$];
				if(!callback(name,value))
					return;
			}
		}
	};
}

unittest {
    import std.stdio;

    string hh = "ggujg=wee&ggg=ytgy&ggg0HH&hjkhk=00";
    string hh2 = "ggujg$=wee&$ggg=ytgy&$ggg0HH&hjkhk$=00";

    splitNameValue!(immutable char, char)(hh, '&', '=', (string key, string value) {
        writeln("1.   ", key, "  ", value);
        return true;
    });

    splitNameValue!(immutable char, char)(hh2, "&$", "$=", (string key, string value) {
        writeln("2.   ", key, "  ", value);
        return true;
    });

    writeln(isSameIngnoreLowUp("AAA12345", "aaa12345"));
}
