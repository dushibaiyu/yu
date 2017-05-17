module yu.tools.buffer;

interface IBuffer
{
    @property bool eof() const;

	size_t read(size_t size, scope void delegate(in ubyte[]) cback);

	size_t write(in ubyte[] data);

	void rest(size_t size = 0);

	@property size_t length() const;

	size_t readLine(scope void delegate(in ubyte[]) cback); //回调模式，数据不copy
	
	size_t readAll(scope void delegate(in ubyte[]) cback);
	
	size_t readUtil(in ubyte[] data, scope void delegate(in ubyte[]) cback);

	size_t readPos();
}

final class Buffer(Alloc) : IBuffer
{
    import yu.bytes;
    import yu.container.vector;
    import std.experimental.allocator.common;

    alias BufferStore = Vector!(ubyte,Alloc,false); 

	static if (stateSize!(Alloc) != 0)
	{
		this(Alloc alloc)
		{
			_store = BufferStore(1024,alloc);
		}
		
		@property allocator(){return _store.allocator;}
		
	} else {
		this()
		{
			_store = BufferStore(1024);
		}
	}

	~this(){
		destroy(_store);
	}

    pragma(inline,true) void reserve(size_t elements)
	{
		_store.reserve(elements);
	}

	pragma(inline,true) void clear()
	{
		_rsize = 0;
		_store.clear();
	}
	
	override @property bool eof() const
	{
		return (_rsize >= _store.length);
	}

	override size_t read(size_t size,scope  void delegate(in ubyte[]) cback)
	{
		size_t len = _store.length - _rsize;
		len = size < len ? size : len;
		ubyte[] _data = _store.data(false);
		size = _rsize;
		_rsize += len;
		if (len > 0)
			cback(_data[size .. _rsize]);

		return len;
	}
	
	override size_t write(in ubyte[] dt)
	{
		size_t len = _store.length;
		_store.insertBack(cast(ubyte[])dt);
		return _store.length - len;
	}
	
	override void rest(size_t size = 0){
		_rsize = size;
	}
	
	override size_t readPos() {
		return _rsize;
	}
	
	ubyte[] data(bool all = false)
	{
		ubyte[] _data = _store.data(false);
		if (all){
			return _data;
		} else {
			return _data[_rsize .. $];
		}
	}
	
	override @property size_t length() const { return _store.length; }
	
	override size_t readLine(scope void delegate(in ubyte[]) cback) //回调模式，数据不copy
	{
		if(eof()) return 0;
		ubyte[] _data = _store.data(false);
		ubyte[] tdata = _data[_rsize..$];
		size_t size = _rsize;
		ptrdiff_t index = findCharByte(tdata,cast(ubyte)'\n');
		if(index < 0){
			_rsize += tdata.length;
			cback(tdata);
		} else {
			_rsize += (index + 1);
			size += 1;
			if(index > 0){
				size_t ts = index -1;
				if(tdata[ts] == cast(ubyte)'\r') {
					index = ts;
				}
			}
			cback(tdata[0..index]);
		}
		
		return _rsize - size;
	}
	
	override size_t readAll(scope void delegate(in ubyte[]) cback)
	{
		if(eof()) return 0;
		ubyte[] _data = _store.data(false);
		ubyte[] tdata = _data[_rsize..$];
		_rsize = _store.length;
		cback(tdata);
		return data.length;
	}
	
	override size_t readUtil(in ubyte[] chs, scope void delegate(in ubyte[]) cback)
	{
		if(eof()) return 0;
		ubyte[] _data = _store.data(false);
		ubyte[] tdata = _data[_rsize..$];
		size_t size = _rsize;
		ptrdiff_t index = findCharBytes(tdata,chs);
		if(index < 0){
			_rsize += tdata.length;
			cback(tdata);
		} else {
			_rsize += (index + chs.length);
			size += chs.length;
			cback(tdata[0..index]);
		}
		return _rsize - size;
	}
	
private:
	BufferStore _store;
	size_t _rsize = 0;
}

unittest
{
	import std.stdio;
	import std.experimental.allocator.mallocator;
	string data = "hello world. hello world.\n hello world. hello world. hello \nworld. hello\r\n world. hello world. hello world. hello world. hello world. hello world. hello world. hello world.";
	auto buf = new Buffer!Mallocator();
	writeln("buffer write :", buf.write(cast(ubyte[]) data));
	writeln("buffer  size:", buf.length);
	assert(buf.length == data.length);
	ubyte[] dt;
	dt.length = 13;
	writeln("buffer read size =", buf.read(13,(in ubyte[] data2){dt[] = data2[];}));
	writeln("buffer read data =", cast(string) dt);
	
	buf.rest();
	string datat;
	buf.readLine((in ubyte[] data2){datat ~= (cast(string)data2);});
	writeln("line is : ", datat);
	assert(datat == "hello world. hello world.");	
}