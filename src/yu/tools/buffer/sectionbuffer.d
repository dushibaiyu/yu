module yu.tools.buffer.sectionbuffer;

import yu.tools.buffer;
import yu.bytes;
import std.experimental.allocator.common;
import std.algorithm : swap;
import core.stdc.string;

@trusted final class SectionBuffer(Alloc) : IBuffer
{
    import yu.container.vector;
    alias BufferVector = Vector!(ubyte[], Alloc, false);

    static if (stateSize!(Alloc) != 0)
    {
        alias ALLOC = Alloc;
        this(uint sectionSize, Alloc alloc)
        {
            _alloc = clloc;
            _sectionSize = sectionSize;
            _buffer = BufferVector(4, alloc);
            _buffer.destroyFun = &destroyBuffer;
        }

        @property allocator()
        {
            return _store.allocator;
        }

        private Alloc _alloc;
    }
    else
    {
        alias ALLOC = typeof(Alloc.instance);
        this(uint sectionSize)
        {
            _sectionSize = sectionSize;
            _buffer = BufferVector(4);
            _buffer.destroyFun = &destroyBuffer;
        }

        alias _alloc = Alloc.instance;
    }

    static void destroyBuffer(ref ALLOC alloc, ref ubyte[] data) nothrow{
        import std.exception;
        if(data.length > 0)
            collectException( _alloc.deallocate(data));
    }

    void reserve(size_t size)
    {
        assert(size > 0);
        size_t sec_size = size / _sectionSize;
        if (sec_size < _buffer.length)
        {
            _buffer.removeBack(_buffer.length - sec_size);
        }
        else if (_buffer.length < sec_size)
        {
            size_t a_size = sec_size - _buffer.length;
            for (size_t i = 0; i < a_size; ++i)
            {
                _buffer.insertBack(cast(ubyte[]) _alloc.allocate(_sectionSize)); //new ubyte[_sectionSize]);//
            }
        }
        size_t lsize = size - (_buffer.length * _sectionSize);
        _buffer.insertBack(cast(ubyte[]) _alloc.allocate(lsize)); //new ubyte[lsize]);
        _rSize = 0;
        _wSize = 0;
    }

    size_t maxSize()
    {
        if (_buffer.empty())
            return size_t.max;
        size_t leng = _buffer[_buffer.length - 1].length;
        if (leng == _sectionSize)
            return size_t.max;
        else
        {
            return (_buffer.length - 1) * _sectionSize + leng;
        }
    }

    @property void clearWithMemory()
    {
        _buffer.clear();

        _rSize = 0;
        _wSize = 0;
    }

    pragma(inline) @property void clear()
    {
        if (maxSize() != size_t.max)
        {
            _buffer.removeBack();
        }
        _rSize = 0;
        _wSize = 0;
    }

    pragma(inline) size_t swap(ref BufferVector uarray)
    {
        auto size = _wSize;
        .swap(uarray, _buffer);
        _rSize = 0;
        _wSize = 0;
        return size;
    }

    override @property bool eof() const
    {
        return isEof;
    }

    override void rest(size_t size = 0)
    {
        _rSize = size;
    }

    override @property size_t length() const
    {
        return _wSize;
    }

    pragma(inline, true) @property size_t stectionSize()
    {
        return _sectionSize;
    }

    pragma(inline) size_t read(ubyte[] data)
    {
        size_t rlen = 0;
        return read(data.length, delegate(in ubyte[] dt) {
            auto len = rlen;
            rlen += dt.length;
            data[len .. rlen] = dt[];

        });

    }

    override size_t read(size_t size, scope void delegate(in ubyte[]) cback) //回调模式，数据不copy
    {
        size_t len = _wSize - _rSize;
        size_t maxlen = size < len ? size : len;
        size_t rcount = readCount();
        size_t rsite = readSite();
        size_t rlen = 0, tlen;
        while (rcount < _buffer.length)
        {
            ubyte[] by = cast(ubyte[])(_buffer[rcount]);
            tlen = maxlen - rlen;
            len = by.length - rsite;
            if (len >= tlen)
            {
                cback(by[rsite .. (tlen + rsite)]);
                rlen += tlen;
                _rSize += tlen;
                break;
            }
            else
            {
                cback(by[rsite .. $]);
                _rSize += len;
                rlen += len;
                rsite = 0;
                ++rcount;
            }
        }
        //_rSize += maxlen;
        return maxlen;
    }

    override size_t write(in ubyte[] data)
    {
        size_t len = maxSize() - _wSize;
        size_t maxlen = data.length < len ? data.length : len;
        size_t wcount = writeCount();
        size_t wsite = writeSite();
        size_t wlen = 0, tlen;
        size_t maxSize = maxSize;
        while (_wSize < maxSize)
        {
            if (wcount == _buffer.length)
            {
                _buffer.insertBack(cast(ubyte[]) _alloc.allocate(_sectionSize)); //new ubyte[_sectionSize]);//
            }
            ubyte[] by = cast(ubyte[])_buffer[wcount];
            tlen = maxlen - wlen;
            len = by.length - wsite;
            if (len >= tlen)
            {
                by[wsite .. (wsite + tlen)] = data[wlen .. (wlen + tlen)];
                break;
            }
            else
            {
                by[wsite .. (wsite + len)] = data[wlen .. (wlen + len)];
                wlen += len;
                wsite = 0;
                ++wcount;
            }
        }
        _wSize += maxlen;
        return maxlen;
    }

    override size_t set(size_t pos, in ubyte[] data)
	{
		import core.stdc.string : memcpy;
		if(pos >= _wSize || data.length == 0) return 0;
		size_t len = _wSize - pos;
		len = len > data.length ? data.length : len;
        auto sect =  pos / _sectionSize;
        auto ssite = pos % _sectionSize;
        ubyte[] by = cast(ubyte[])_buffer[sect];
        if(ssite + len < by.length){
            ubyte * ptr = by.ptr + ssite;
            memcpy(ptr, data.ptr, len);
        } else {
            auto tlen = by.length - ssite;
            ubyte * ptr = by.ptr + ssite;
            memcpy(ptr, data.ptr, tlen);
            by = cast(ubyte[])_buffer[sect + 1];
            memcpy(by.ptr,(data.ptr + tlen),(len -tlen));
        }
        return len;
	}

    /*
	 * 会自动跳过找到的\r\n字段
	**/
    override size_t readLine(scope void delegate(in ubyte[]) cback) //回调模式，数据不copy
    {
        if (isEof())
            return 0;
        size_t size = _rSize;
        size_t wsite = writeSite();
        size_t wcount = writeCount();
        ubyte[] byptr, by;
        while (!isEof())
        {
            size_t rcount = readCount();
            size_t rsite = readSite();
            by = _buffer[rcount];
            if (rcount == wcount)
            {
                byptr = by[rsite .. wsite];
            }
            else
            {
                byptr = by[rsite .. $];
            }
            ptrdiff_t site = findCharByte(byptr, cast(ubyte) '\n');
            if (site < 0)
            {
                cback(byptr);
                rsite = 0;
                ++rcount;
                _rSize += byptr.length;
            }
            else
            {
                auto tsize = (_rSize + site);
                if (site > 0)
                {
                    size_t ts = site - 1;
                    if (byptr[ts] == cast(ubyte) '\r')
                    {
                        site = ts;
                    }
                }
                cback(byptr[0 .. site]);

                _rSize = tsize + 1;
                size += 1;
                break;
            }

        }
        return _rSize - size;
    }

    override size_t readAll(scope void delegate(in ubyte[]) cback) //回调模式，数据不copy
    {
        size_t maxlen = _wSize - _rSize;
        size_t rcount = readCount();
        size_t rsite = readSite();
        size_t wcount = writeCount();
        size_t wsize = writeSite();
        ubyte[] rbyte;
        while (rcount <= wcount && !isEof())
        {
            ubyte[] by = _buffer[rcount];
            if (rcount == wcount)
            {
                rbyte = by[rsite .. wsize];
            }
            else
            {
                rbyte = by[rsite .. $];
            }
            cback(rbyte);
            _rSize += rbyte.length;
            rsite = 0;
            ++rcount;
        }
        return _wSize - _rSize;
    }

    /*
	 * 会自动跳过找到的data字段
	**/
    override size_t readUtil(in ubyte[] data, scope void delegate(in ubyte[]) cback) //data.length 必须小于分段大小！
    {
        if (data.length == 0 || isEof() || data.length >= _sectionSize)
            return 0;
        auto ch = data[0];

        size_t size = _rSize;
        size_t wsite = writeSite();
        size_t wcount = writeCount();
        ubyte[] byptr, by;
        while (!isEof())
        {
            size_t rcount = readCount();
            size_t rsite = readSite();
            by = _buffer[rcount];
            if (rcount == wcount)
            {
                byptr = by[rsite .. wsite];
            }
            else
            {
                byptr = by[rsite .. $];
            }
            ptrdiff_t site = findCharByte(byptr, ch);
            if (site == -1)
            {
                cback(byptr);
                rsite = 0;
                ++rcount;
                _rSize += byptr.length;
            }
            else
            {
                auto tsize = (_rSize + site);
                size_t i = 1;
                size_t j = tsize + 1;
                for (; i < data.length && j < _wSize; ++i, ++j)
                {
                    if (data[i] != this[j])
                    {
                        cback(byptr[0 .. site + 1]);
                        _rSize = tsize + 1;
                        goto next; //没找对，进行下次查找
                    }
                } //循环正常执行完毕,表示
                cback(byptr[0 .. site]);
                _rSize = tsize + data.length;
                size += data.length;
                break;

            next:
                continue;
            }
        }
        return (_rSize - size);
    }

    pragma(inline) ref ubyte opIndex(size_t i)
    {
        assert(i < _wSize);
        size_t count = i / _sectionSize;
        size_t site = i % _sectionSize;
        return _buffer[count][site];
    }

    pragma(inline, true) @property readSize() const
    {
        return _rSize;
    }

    override size_t readPos()
    {
        return _rSize;
    }

    pragma(inline, true) @property readCount() const
    {
        return _rSize / _sectionSize;
    }

    pragma(inline, true) @property readSite() const
    {
        return _rSize % _sectionSize;
    }

    pragma(inline, true) @property writeCount() const
    {
        return _wSize / _sectionSize;
    }

    pragma(inline, true) @property writeSite() const
    {
        return _wSize % _sectionSize;
    }

private:
    pragma(inline, true) @property bool isEof() const
    {
        return (_rSize >= _wSize);
    }

    size_t _rSize;
    size_t _wSize;
    size_t _sectionSize;
    BufferVector _buffer;
}

unittest
{
    import std.stdio;
    import std.experimental.allocator.mallocator;

    string data = "hello world. hello world. hello world. hello world. hello world. hello world. hello world. hello world. hello world. hello world. hello world. hello world. hello world.";
    auto buf = new SectionBuffer!Mallocator(5);
    buf.reserve(data.length);
    writeln("buffer max size:", buf.maxSize());
    writeln("buffer  size:", buf.length);
    writeln("buffer write :", buf.write(cast(ubyte[]) data));
    writeln("buffer  size:", buf.length);
    ubyte[] dt;
    dt.length = 13;
    writeln("buffer read size =", buf.read(dt));
    writeln("buffer read data =", cast(string) dt);

    writeln("\r\n");

    auto buf2 = new SectionBuffer!Mallocator(3);
    writeln("buffer2 max size:", buf2.maxSize());
    writeln("buffer2  size:", buf2.length);
    writeln("buffer2 write :", buf2.write(cast(ubyte[]) data));
    writeln("buffer2  size:", buf2.length);
    ubyte[] dt2;
    dt2.length = 13;
    writeln("buffer2 read size =", buf2.read(dt2));
    writeln("buffer2 read data =", cast(string) dt2);

    writeln("\r\nswitch \r\n");

    auto tary = SectionBuffer!Mallocator.BufferVector();
    buf.swap(tary);
    writeln("buffer  size:", buf.length);
    writeln("buffer max size:", buf.maxSize());
    writeln("Array!(ubyte[]) length : ", tary.length);
    size_t len = tary.length < 5 ? tary.length : 5;
    for (size_t i = 0; i < len; ++i)
    {
        write("i = ", i);
        writeln("   ,ubyte[] = ", cast(string) tary[i]);
    }

    buf.reserve(data.length);
    writeln("buffer max size:", buf.maxSize());
    writeln("buffer  size:", buf.length);
    writeln("buffer write :", buf.write(cast(ubyte[]) data));
    writeln("buffer  size:", buf.length);
    writeln("\n 1.");

    /* dt.length = 1;
    writeln("buffer read size =",buf.read(dt));
    writeln("buffer read data =",cast(string)dt);*/

    data = "ewarwaerewtretr54654654kwjoerjopiwrjeo;jmq;lkwejoqwiurwnblknhkjhnjmq1111dewrewrjmqrtee";
    buf = new SectionBuffer!Mallocator(5);
    // buf.reserve(data.length);
    writeln("buffer max size:", buf.maxSize());
    writeln("buffer  size:", buf.length);
    writeln("buffer write :", buf.write(cast(ubyte[]) data));
    writeln("buffer  size:", buf.length);

    foreach (i; 0 .. 4)
    {
        ubyte[] tbyte;
        writeln("\n\nbuffer readutil  size:", buf.readUtil(cast(ubyte[]) "jmq",
                delegate(in ubyte[] data) {
                    //writeln("\t data :", cast(string)data);
                    //writeln("\t read size: ", buf._rSize);
                    tbyte ~= data;
                }));
        if (tbyte.length > 0)
        {
            writeln("\n buffer readutil data:", cast(string) tbyte);
            writeln("\t _Rread size: ", buf._rSize);
            writeln("\t _Wread size: ", buf._wSize);
        }
        else
        {
            writeln("\n buffer readutil data eof");
        }
    }
    //buf.clear();
    //buf2.clear();
    writeln("hahah");
    destroy(buf);
    destroy(buf2);
}
