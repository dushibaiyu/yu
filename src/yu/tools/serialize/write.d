module yu.tools.serialize.write;

import std.bitmanip;

import yu.tools.serialize.types;
import yu.tools.serialize.status;
import yu.tools.serialize.exception;

import yu.traits;
import yu.tools.buffer;
import yu.memory.allocator;


@trusted struct WriteStream
{
    @disable this();
    @disable this(this);

	this(IWriteBuffer buffer)
	{
		_buffer = buffer;
	}

	~this()
	{
		StatusNode * node = _status.pop();
        while(node){
            yDel(node);
            node = _status.pop();
        }
	}

    @property buffer(){return _buffer;}

	void write(X)(X value) if(isBasicSupport!(X).isNum)
	{
		doIsArray(dtTypes!X);
		ubyte[X.sizeof] data = nativeToBigEndian!X(value);
		append(data);
	}

	void write(X)(X value) if(isBasicSupport!(X).isChar)
	{
		doIsArray(dtTypes!X);
		append(cast(ubyte)value);
	}

	void write(X:bool)(X value) 
	{
		doIsArray(dtTypes!X);
		ubyte a = value ? 0x01 : 0x00;
		append(a);
	}

	void write(X:DateTime)(ref X value) 
	{
		doIsArray(dtTypes!X);
		ubyte[2] data;
		data = nativeToBigEndian!short(value.year());
		append(data);
		append(value.month());
		append(value.day());
		append(value.hour());
		append(value.minute());
		append(value.second());
	}

	void write(X:Date)(ref X value) 
	{
		doIsArray(dtTypes!X);
		ubyte[2] data;
		data = nativeToBigEndian!short(value.year());
		append(data);
		append(value.month());
		append(value.day());
	}

	void write(X:Time)(ref X value) 
	{
		doIsArray(dtTypes!X);
		append(value.hour);
		append(value.minute);
		append(value.second);
		ubyte[2] data;
		data = nativeToBigEndian!ushort(value.msecond);
		append(data);
	}


	void write(X:char[])(ref X value)
	{
		writeRawArray(Types.Char,cast(ubyte[])value);
	}

	void write(X:byte[])(ref X value)
	{
		writeRawArray(Types.Byte,cast(ubyte[])value);
	}

	void write(X:ubyte[])(ref X value)
	{
		writeRawArray(Types.UByte,value);
	}

	void write(X: string)(ref X value)
	{
		writeRawArray(Types.Char,cast(ubyte[])value);
	}

	void write(X)(ref X value) if(isArray!(X) && isBasicSupport!(X).isBSupport && !isStruct!X)
	{
		startArray!(ForeachType!X)();
		scope(success)endArray();
		foreach(ref v ; value)
		{
			write(v);
		}
	}

	void startArray(X)() if(isBasicSupport!(X).isBSupport)
	{
		Types ty = dtTypes!X;
		StatusNode * state = yNew!StatusNode();
		state.state = Status.InArray;
		state.type = ty;
		_status.push(state);
		append(Types.Array);
		append(ty);
		state.begin = _buffer.length;
		ubyte[4] data;
		append(data);
	}

	void endArray()
	{
		StatusNode * state = _status.pop();
		if(state is null || state.state != Status.InArray)
			throw new WriteException("not in Array!!!");

		scope(exit)yDel(state);
		ubyte[4] data = nativeToBigEndian!uint(state.len);
		//_data[state.begin..(state.begin + 4)] = data; //写入数组长度
		_buffer.set(state.begin, data[]);
		//append(data[]);
		append(Types.End);

		StatusNode * state2 = _status.front();
		if(state2 !is null && state2.state == Status.InArray)
		{
			if(state2.type == Types.Array) {
				state2.len ++;
			}
		}
	}

	void startStruct()
	{
		StatusNode * state = yNew!StatusNode();
		state.state = Status.InStruct;
		state.type = Types.Struct;
		_status.push(state);
		append(Types.Struct);
	}

	void endStruct()
	{
		StatusNode * state = _status.pop();

		if(state is null || state.state != Status.InStruct)
			throw new WriteException("not in struct!!!");
		scope(exit)yDel(state);
		append(Types.End);
		StatusNode * state2 = _status.front();
		if(state2 !is null && state2.state == Status.InArray)
		{
			if(state2.type == Types.Struct) {
				state2.len ++;
			}
		}
	}

	pragma(inline) void append(ubyte value)
	{
        ubyte * ptr = &value;
		_buffer.write(ptr[0..1]);
	}

	pragma(inline) void append(in ubyte[] value)
	{
		_buffer.write(value);
	}

private:
	//pragma(inline, true) 
	void writeRawArray(Types ty, ubyte[] data)
	{
		append(Types.Array);
		append(ty);
		uint leng = cast(uint)data.length;
		ubyte[4] dt = nativeToBigEndian!uint(leng);
		append(dt[]);
		
		append(data);
		append(Types.End);
	}

	//pragma(inline, true) 
	void doIsArray(Types ty)
	{
		StatusNode * state = _status.front();
		if(state !is null && state.state == Status.InArray)
		{
			if(state.type == ty) {
				state.len ++;
			}else {
				endArray();
				append(ty);
			}
		}else{
			append(ty);
		}
	}

private:
    IWriteBuffer _buffer;
	StatusStack _status;
}