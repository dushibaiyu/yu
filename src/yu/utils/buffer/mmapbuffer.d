 module yu.utils.buffer.mmapbuffer;
import yu.container.string;
import yu.memory;
import core.stdc.string : memcpy;

import std.mmfile;

struct MmapBuffer
{
	this(ref String file,uint size = 0,bool autoTruncate = false)
	{
		_cacheFile = file;
		_autoTruncate = autoTruncate;
		_maxSize = size;
		if(size < 4096)
			_maxSize = 4096;
		_mfile = cNew!MmFile(_cacheFile.stdString,MmFile.Mode.readWriteNew,_maxSize,null,0);
		_basePtr = cast(ubyte *)(_mfile[0..1].ptr);
	}

	this(string file,uint size = 0,bool autoTruncate = false)
	{
		_cacheFile = file;
		_autoTruncate = autoTruncate;
		_maxSize = size;
		if(size < 4096)
			_maxSize = 4096;
		_mfile = cNew!MmFile(_cacheFile.stdString,MmFile.Mode.readWriteNew,_maxSize,null,0);
		_basePtr = cast(ubyte *)(_mfile[0..1].ptr);
	}

	~this()
	{
		cDel(_mfile);
	}

	@disable this(ref MmapBuffer);
	pragma(inline)
	@property String fileName()  {return _cacheFile;}
	pragma(inline)
	@property uint maxSize() {return _maxSize;}
	pragma(inline)
	@property uint canRead() {return _writePos - _readPos;}
	pragma(inline)
	@property uint canWrite() {return _maxSize - _writePos;}
	pragma(inline)
	@property uint writePos() const {return  _writePos;}
	pragma(inline)
	@property uint readPos() const {return _readPos;}

	@property ubyte * dataPtr(){return _basePtr;}

	@property uint length(){return _writePos;}

	uint write(in ubyte[] buf){
		 auto wd = write(buf,_writePos);
		_writePos += wd;
		return wd;
	}
	uint write(in ubyte[] buf,uint offset){
		auto size = cast(uint)buf.length;
		if(offset >= _maxSize) return 0;
		auto can = _maxSize - offset;
		if(can < size)  size = can;
		auto now = _basePtr + offset;
		memcpy(now,buf.ptr,size);
		return size;
	}

	uint read(ref scope ubyte[] buffer){
		auto rd = read(buffer,_readPos);
		_readPos += rd;
		return rd;
	}

	uint read(ref scope ubyte[] buffer,uint offset){
		if(offset >= _writePos) return 0;
		auto size = cast(uint)buffer.length;
		auto can = _writePos - offset;
		if(can < size)
			size = can;
		auto now = _basePtr + offset;
		memcpy(buffer.ptr,now,size);
		return size;
	}

	void restWrite(uint offset = 0) {
        if(offset > _maxSize) _writePos = _maxSize;
        else _writePos = offset;
    }

	void restRead(uint offset = 0) {
        if(offset > _maxSize) _readPos = _maxSize;
        else _readPos = offset;
    }

	void flush(){
		_mfile.flush();
	}

private:
	MmFile _mfile;
	String _cacheFile;
	bool _autoTruncate;
	ubyte * _basePtr = null;
	uint _maxSize = 0;
	uint _readPos = 0;
	uint _writePos = 0;
}


unittest
{
    import std.file;
    auto name = "./addd.tp";
    scope(exit) std.file.remove(name);
	MmapBuffer mmf = MmapBuffer(name);
	auto dt = mmf.dataPtr;
	string  testData = "77889910232384638748234";
	mmf.write(cast(const ubyte[])(testData));
	auto p = cast(string) dt[0 .. testData.length];
	assert(p == testData);
	ubyte[] t = new ubyte[testData.length];
	mmf.write(cast(const ubyte[])(testData));
	auto tlen = cast(ulong)mmf.read(t);
	assert(tlen == t.length);
	assert(cast(string)(t) == testData);
	tlen = cast(ulong)mmf.read(t);
	assert(tlen == t.length);
	assert(cast(string)(t) == testData);
	mmf.restRead(0);
	tlen = cast(ulong)mmf.read(t);
	assert(tlen == t.length);
	assert(cast(string)(t) == testData);
	tlen = cast(ulong)mmf.read(t);
	assert(tlen == t.length);
	assert(cast(string)(t) == testData);
}
