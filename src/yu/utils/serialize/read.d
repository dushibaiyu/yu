module yu.utils.serialize.read;

import std.bitmanip;

import yu.utils.serialize.types;
import yu.utils.serialize.status;
import yu.utils.serialize.exception;

import yu.traits;
import yu.utils.buffer;
import yu.memory;

@trusted struct ReadStream
{
	@disable this();
    @disable this(ref ReadStream);

	this(const(ubyte)[] data)
	{
		_data = data;
	}

    ~this()
	{
		StatusNode * node = _status.pop();
        while(node){
            yDel(node);
            node = _status.pop();
        }
	}

	Types nextType()
	{
		return cast(Types)(_data[_currt]);
	}

	Types arrayType()
	{
		myAssert(_data[_currt] == Types.Array, "check Array type erro");
		return cast(Types)(_data[_currt + 1]);
	}

	// return len.
	uint startReadArray()
	{
		myAssert(_data[_currt] == Types.Array,"check Array type erro");
		StatusNode * state = yNew!StatusNode();
		state.state = Status.InArray;
		state.type = cast(Types)_data[_currt+1];
		_status.push(state);

		_currt += 2;
		size_t start = _currt;
		_currt += 4;
		ubyte[4] data;
		data[] = _data[start.._currt];
		return bigEndianToNative!(uint,uint.sizeof)(data);
	}

	void endReadArray()
	{
        auto node = _status.front();
        if(node is null || node.state != Status.InArray)
            throw new ReadException("Not in A array!");
        _currt ++;
        _status.pop();
        yDel(node);
	}

	void startReadStruct()
	{
		myAssert(_data[_currt] == Types.Struct,"check struct type erro");
		_currt ++;

		StatusNode * state = yNew!StatusNode();
		state.state = Status.InStruct;
		state.type = Types.Struct;
		_status.push(state);
	}

	void endReadStruct() // TODO:  read to end
	{
        auto node = _status.front();
        if(node is null || node.state != Status.InStruct)
            throw new ReadException("Not in A Struct!");
        while(nextType() != Types.End){
                skipType();
        }
        _currt ++;
        _status.pop();
        yDel(node);
	}

	auto read(X)() if(isBasicSupport!(X).isNum)
	{
		typePrev(dtTypes!X);
		size_t start = _currt;
		_currt += X.sizeof;
		ubyte[X.sizeof] data = _data[start.._currt];
		return bigEndianToNative!(X,X.sizeof)(data);
	}

	auto read(X)() if(isBasicSupport!(X).isChar)
	{
		typePrev(dtTypes!X);
		X v = _data[_currt];
		++_currt;
		return v;
	}

	bool read(X:bool)()
	{
		typePrev(dtTypes!X);
		ubyte v = _data[_currt];
		++_currt;
		return v > 0;
	}

	DateTime read(X:DateTime)()
	{
		typePrev(dtTypes!X);
		DateTime dt;
		size_t start = _currt;
		_currt += 2;
		ubyte[2] data = _data[start.._currt];
		dt.year(bigEndianToNative!(short)(data));
		dt.month(cast(Month)(_data[_currt]));
		++_currt;
		dt.day(_data[_currt]);
		++_currt;

		dt.hour(_data[_currt]);
		++_currt;
		dt.minute(_data[_currt]);
		++_currt;
		dt.second(_data[_currt]);
		++_currt;

		return dt;
	}

	Date read(X:Date)()
	{
		typePrev(dtTypes!X);
		Date dt;
		size_t start = _currt;
		_currt += 2;
		ubyte[2] data = _data[start.._currt];
		dt.year(bigEndianToNative!(short)(data));
		dt.month(cast(Month)(_data[_currt]));
		++_currt;
		dt.day(_data[_currt]);
		++_currt;

		return dt;
	}

	Time read(X:Time)()
	{
		typePrev(dtTypes!X);
		Time tm;
		tm.hour = _data[_currt];
		++_currt;
		tm.minute = _data[_currt];
		++_currt;
		tm.second = _data[_currt];
		++_currt;

		size_t start = _currt;
		_currt += 2;
		ubyte[2] data = _data[start.._currt];
		tm.msecond = bigEndianToNative!(ushort)(data);

		return tm;
	}

	ubyte[] read(X:ubyte[])()
	{
		myAssert(Types.Array == _data[_currt], "read check type erro : " ~ X.stringof);
		myAssert(Types.UByte == _data[_currt + 1] , "read check type erro : " ~ X.stringof);

		uint len = startReadArray();
		size_t start = _currt;
		_currt += len;
		auto data = _data[start.._currt];
		endReadArray();
		return cast(ubyte[])data;
	}

	string read(X: string)()
	{
		myAssert(Types.Array == _data[_currt],"read check type erro : " ~ X.stringof);
		myAssert(Types.Char == _data[_currt + 1],"read check type erro : " ~ X.stringof);

		uint len = startReadArray();
		size_t start = _currt;
		_currt += len;
		auto data = _data[start.._currt];
		endReadArray();
		return cast(string)data;
	}

private:
	void typePrev(Types ty)
	{
		StatusNode * state2 = _status.front();
		if(state2 is null)
		{
			myAssert(ty == _data[_currt],"read check type erro  " );
			++_currt;
		}
		else if(state2.state != Status.InArray)
		{
			myAssert(ty == _data[_currt],"read check type erro  " );
			++_currt;
		}
		else
		{
			myAssert(ty == state2.type,"read check type erro  " );
		}
	}

    void skipType()
    {
		Types type = nextType();
		switch(type) with(Types){
            case Char:
            case UChar:
            case Bool:
                _currt += 2;
            break;
            case Short:
            case UShort:
                _currt += 3;
            break;
            case Int:
            case UInt:
            case Float:
            case Date:
             _currt += 5;
            break;
            case Time:
            _currt += 6;
            break;
            case DateTime:
            	_currt += 8;
            break;
            case Long:
            case ULong:
            case Double:
            	_currt += 9;
            break;
            case Array:
				skipArray();
            break;
            case Struct:
				skipStruct();
            break;
			default:
				throw new ReadException("Read in Array type Error");
        }
    }

    void skipArray()
    {
        Types type = arrayType();
        uint len = startReadArray();
        switch(type) with(Types){
            case Char:
            case UChar:
            case Bool:
                _currt += len;
            break;
            case Short:
            case UShort:
                _currt += (len * 2);
            break;
            case Int:
            case UInt:
            case Float:
            case Date:
             _currt += (len * 4);
            break;
            case Time:
            _currt += (len * 5);
            break;
            case DateTime:
            	_currt += (len * 7);
            break;
            case Long:
            case ULong:
            case Double:
            	_currt += (len * 8);
            break;
            case Array:
				foreach(i; 0..len){
					skipArray();
				}
            break;
            case Struct:
				foreach(i; 0..len){
					skipStruct();
				}
            break;
			default:
				throw new ReadException("Read in Array type Error");
        }
        endReadArray();
    }

    void skipStruct()
    {
        startReadStruct();
        endReadStruct();
    }
private:
	const(ubyte)[] _data;
	size_t _currt;

	StatusStack _status;
}

private:
pragma(inline)
void myAssert(string file = __FILE__, int line = __LINE__)(bool erro, lazy string msg = string.init)
{
	if(!erro)
		throw new ReadException(msg,file,line);
}
