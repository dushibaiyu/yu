module yu.asyncsocket.tcpsocket;

import core.stdc.errno;

import std.socket;
import std.functional;
import std.exception;

import yu.eventloop;
import yu.asyncsocket.transport;
import yu.exception;
import std.string;

alias TCPWriteCallBack = void delegate(const(ubyte)[] data, size_t writeSzie) nothrow;
alias TCPReadCallBack = void delegate(in ubyte[] buffer) nothrow;

abstract class TCPWriteBuffer
{
    // todo Send Data;
    const(ubyte)[] data() nothrow;
    // add send offiset and return is empty
    bool popSize(size_t size) nothrow;
    // do send finish
    void doFinish() nothrow;
private:
    TCPWriteBuffer _next;
}

@trusted class TCPSocket : AsyncTransport, EventCallInterface {
    this(EventLoop loop, bool isIpV6 = false) {
        auto family = isIpV6 ? AddressFamily.INET6 : AddressFamily.INET;
        _socket = yNew!Socket(family, SocketType.STREAM, ProtocolType.TCP);
        this(loop, _socket);
    }

    this(EventLoop loop, AddressFamily family) {
        _socket = yNew!Socket(family, SocketType.STREAM, ProtocolType.TCP);
        this(loop, _socket);
    }

    this(EventLoop loop, Socket sock)
    in {
        assert(sock.addressFamily == AddressFamily.INET
            || sock.addressFamily == AddressFamily.INET6,
            "the AddressFamily must be AddressFamily.INET or AddressFamily.INET6");
    }
    body {
        super(loop, TransportType.TCP);
        _socket = sock;
        _socket.blocking = false;
        _readBuffer = makeArray!ubyte(yuAlloctor, TCP_READ_BUFFER_SIZE);
        _event = AsyncEvent(AsynType.TCP, this, _socket.handle, true, true, true);
        static if (IO_MODE.iocp == IOMode) {
            _iocpBuffer.len = cast(uint)TCP_READ_BUFFER_SIZE;
            _iocpBuffer.buf = cast(char*) _readBuffer.ptr;
            _iocpread.event = &_event;
            _iocpwrite.event = &_event;
            _iocpwrite.operationType = IOCP_OP_TYPE.write;
            _iocpread.operationType = IOCP_OP_TYPE.read;
        }
    }

    ~this() {
        clearWriteQueue();
        yDel(_socket);
        yDel(_readBuffer);
        _readBuffer = null;
    }

    final override @property int fd() {
        return cast(int) _socket.handle();
    }

    override bool start() {
        if (_event.isActive || !_socket.isAlive() || !_readCallBack)
            return false;
        _event = AsyncEvent(AsynType.TCP, this, _socket.handle, true, true, true);
        static if (IOMode == IO_MODE.iocp) {
            _loop.addEvent(&_event);
            return doRead();
        } else {
            return _loop.addEvent(&_event);
        }
    }

    final override void close() {
        if (alive) {
            onClose();
        } else if (_socket.isAlive()) {
            Linger optLinger;
            optLinger.on = 1;
            optLinger.time = 0;
            _socket.setOption(SocketOptionLevel.SOCKET, SocketOption.LINGER, optLinger);
            _socket.close();
        }
    }

    override @property bool isAlive() @trusted nothrow {
        return alive();
    }

    void write(const(ubyte)[] data, TCPWriteCallBack cback) {
        if (!alive) {
            warning("tcp socket write on close!");
            if (cback)
                cback(data, 0);
            return;
        }
        auto buffer = yNew!WriteSite(data, cback);
        write(buffer);
    }

    void write(TCPWriteBuffer buffer)
    {
         if (!alive) {
            warning("tcp socket write on close!");
            buffer.doFinish();
            return;
        }
        static if (IOMode == IO_MODE.iocp) {
            bool dowrite = _writeQueue.empty;
        }
        _writeQueue.enQueue(buffer);
        static if (IOMode == IO_MODE.iocp) {
            trace("do write: ", dowrite);
            if (dowrite) {
                _event.writeLen = 0;
                onWrite();
            }
        } else {
            onWrite();
        }
    }

    mixin TransportSocketOption;

    pragma(inline) void setKeepAlive(int time, int interval) @trusted {
        _socket.setKeepAlive(forward!(time, interval));
    }

    pragma(inline) final void setReadCallBack(TCPReadCallBack cback) {
        _readCallBack = cback;
    }

    pragma(inline) final void setCloseCallBack(CallBack cback) {
        _unActive = cback;
    }

protected:
    pragma(inline, true) final @property bool alive() @trusted nothrow {
        return _event.isActive && _socket.handle() != socket_t.init;
    }

    override void onWrite() nothrow {
        static if (IOMode == IO_MODE.iocp) {
            if (!alive || _writeQueue.empty)
                return;
            TCPWriteBuffer buffer = _writeQueue.front;
            if (_event.writeLen > 0) {
                if (buffer.popSize(_event.writeLen)) {
                    _writeQueue.deQueue();
                    buffer.doFinish();
                }
            }
            while (!_writeQueue.empty){
                buffer = _writeQueue.front;
                _event.writeLen = 0;
                auto data = buffer.data;
                if(data.length == 0){
                    _writeQueue.deQueue();
                    buffer.doFinish();
                    continue;
                }
                _iocpWBuf.len = cast(uint)data.length;
                _iocpWBuf.buf = cast(char*) data.ptr;
                doWrite();
                return;
            }
        } else {
            try {
                import core.stdc.string;
                while (alive && !_writeQueue.empty) {
                    TCPWriteBuffer buffer = _writeQueue.front;
                    auto data =  buffer.data;
                    if(data.length == 0){
                        _writeQueue.deQueue();
                        buffer.doFinish();
                        continue;
                    }
                    auto len = _socket.send(data);
                    if (len > 0) {
                        if (buffer.popSize(len)) {
                            _writeQueue.deQueue();
                            buffer.doFinish();
                        }
                        continue;
                    } else {
                        if (errno == EAGAIN || errno == EWOULDBLOCK) {
                            return;
                        } else if (errno == 4) {
                            continue;
                        }
                    }
                    error("write size: ", len,
                        " \n\tDo Close the erro code : ", errno,
                        "  erro is : ", fromStringz(strerror(errno)), " \n\tthe socket fd : ",
                        fd);
                    onClose();
                    return;
                }
            }
            catch (Exception e) {
                showException(e);
                onClose();
            }
        }
    }

    override void onClose() nothrow {
        if (!alive)
            return;
        eventLoop.delEvent(&_event);
        clearWriteQueue();
        try {
            _socket.shutdown(SocketShutdown.BOTH);
            _socket.close();
        }
        catch (Exception e) {
            showException(e);
        }
        auto unActive = _unActive;
        _readCallBack = null;
        _unActive = null;
        if (unActive)
            unActive();
    }

    override void onRead() nothrow {
        static if (IOMode == IO_MODE.iocp) {
            if (_event.readLen > 0) {
                _readCallBack(_readBuffer[0 .. _event.readLen]);
            } else {
                onClose();
                return;
            }
            _event.readLen = 0;
            if (alive)
                doRead();

        } else {
            try {
                import core.stdc.string;

                while (alive) {
                    auto len = _socket.receive(_readBuffer);
                    if (len > 0) {
                        _readCallBack(_readBuffer[0 .. len]);
                        continue;
                    } else if (len < 0) {
                        if (errno == EAGAIN || errno == EWOULDBLOCK) {
                            return;
                        } else if (errno == 4) {
                            continue;
                        }
                        error("Do Close the erro code : ", errno,
                            "  erro is : ", fromStringz(strerror(errno)),
                            " \n\tthe socket fd : ", fd);
                    }
                    onClose();
                    return;
                }
            }
            catch (Exception e) {
                showException(e);
                onClose();
            }
        }
    }

    static if (IOMode == IO_MODE.iocp) {
        bool doRead() nothrow {
            _iocpBuffer.len = cast(uint)TCP_READ_BUFFER_SIZE;
            _iocpBuffer.buf = cast(char*) _readBuffer.ptr;
            _iocpread.event = &_event;
            _iocpread.operationType = IOCP_OP_TYPE.read;

            DWORD dwReceived = 0;
            DWORD dwFlags = 0;

            int nRet = WSARecv(cast(SOCKET) _socket.handle, &_iocpBuffer,
                cast(uint) 1, &dwReceived, &dwFlags, &_iocpread.ol,
                cast(LPWSAOVERLAPPED_COMPLETION_ROUTINE) null);
            if (nRet == SOCKET_ERROR) {
                DWORD dwLastError = GetLastError();
                if (ERROR_IO_PENDING != dwLastError) {
                    yuCathException(error("WSARecv failed with error: ", dwLastError));
                    onClose();
                    return false;
                }
            }
            return true;
        }

        bool doWrite() nothrow {
            DWORD dwFlags = 0;
            DWORD dwSent = 0;
            _iocpwrite.event = &_event;
            _iocpwrite.operationType = IOCP_OP_TYPE.write;
            int nRet = WSASend(cast(SOCKET) _socket.handle(), &_iocpWBuf, 1,
                &dwSent, dwFlags, &_iocpwrite.ol, cast(LPWSAOVERLAPPED_COMPLETION_ROUTINE) null);
            if (nRet == SOCKET_ERROR) {
                DWORD dwLastError = GetLastError();
                if (dwLastError != ERROR_IO_PENDING) {
                    yuCathException(error("WSASend failed with error: ", dwLastError));
                    onClose();
                    return false;
                }
            }
            return true;
        }
    }

    final void clearWriteQueue() nothrow {
        while (!_writeQueue.empty) {
            TCPWriteBuffer buf = _writeQueue.deQueue();
            buf.doFinish();
        }
    }

protected:
    import std.experimental.allocator.gc_allocator;

    Socket _socket;
    WriteBufferQueue _writeQueue;
    AsyncEvent _event;
    ubyte[] _readBuffer;

    CallBack _unActive;
    TCPReadCallBack _readCallBack;

    static if (IO_MODE.iocp == IOMode) {
        IOCP_DATA _iocpread;
        IOCP_DATA _iocpwrite;
        WSABUF _iocpBuffer;
        WSABUF _iocpWBuf;

    }
}

package:

final class WriteSite : TCPWriteBuffer
{
    this(const(ubyte)[] data, TCPWriteCallBack cback = null)
    {
        _data = data;
        _site = 0;
        _cback = cback;
    }

    override const(ubyte)[] data() nothrow
    {
        return _data[_site .. $];
    }
    // add send offiset and return is empty
    override bool popSize(size_t size) nothrow
    {
        _site += size;
        if (_site >= _data.length)
            return true;
        else
            return false;
    }
    // do send finish
    override void doFinish() nothrow
    {
        if (_cback)
        {
			_cback(_data, _site);
        }
        _cback = null;
        _data = null;
        yuCathException({ yDel(this); }());
    }

private:
    size_t _site = 0;
    const(ubyte)[] _data;
    TCPWriteCallBack _cback;
}

struct WriteBufferQueue
{
	TCPWriteBuffer  front() nothrow{
		return _frist;
	}

	bool empty() nothrow{
		return _frist is null;
	}

	void enQueue(TCPWriteBuffer wsite) nothrow
	in{
		assert(wsite);
	}body{
		if(_last){
			_last._next = wsite;
		} else {
			_frist = wsite;
		}
		wsite._next = null;
		_last = wsite;
	}

	TCPWriteBuffer deQueue() nothrow
	in{
		assert(_frist && _last);
	}body{
		TCPWriteBuffer  wsite = _frist;
		_frist = _frist._next;
		if(_frist is null)
			_last = null;
		return wsite;
	}

private:
	TCPWriteBuffer  _last = null;
	TCPWriteBuffer  _frist = null;
}