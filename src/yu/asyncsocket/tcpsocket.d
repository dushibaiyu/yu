module yu.asyncsocket.tcpsocket;

import core.stdc.errno;

import std.socket;
import std.functional;
import std.exception;

import yu.eventloop;
import yu.asyncsocket.transport;
import yu.exception;
import std.string;

alias TCPWriteCallBack = void delegate(ubyte[] data, size_t writeSzie);
alias TCPReadCallBack = void delegate(ubyte[] buffer);

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
            _iocpBuffer.len = TCP_READ_BUFFER_SIZE;
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

    pragma(inline) void write(ubyte[] data, TCPWriteCallBack cback) {
        if (!alive) {
            warning("tcp socket write on close!");
            if (cback)
                cback(data, 0);
            return;
        }
        auto buffer = yNew!WriteSite(data, cback);

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

    pragma(inline, true) void setKeepAlive(int time, int interval) @trusted {
        return _socket.setKeepAlive(forward!(time, interval));
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
            auto buffer = _writeQueue.front;
            if (_event.writeLen > 0) {
                try {
                    if (buffer.add(_event.writeLen)) {
                        auto buf = _writeQueue.deQueue();
                        buf.doCallBack();
                        yDel(buf);
                    }
                    if (!_writeQueue.empty)
                        buffer = _writeQueue.front;
                    else
                        return;
                }
                catch (Exception e) {
                    showException(e);
                }
            }
            _event.writeLen = 0;
            auto data = buffer.data;
            _iocpWBuf.len = data.length;
            _iocpWBuf.buf = cast(char*) data.ptr;
            doWrite();
        } else {
            try {
                import core.stdc.string;

                while (alive && !_writeQueue.empty) {
                    auto buffer = _writeQueue.front;
                    auto len = _socket.send(buffer.data);
                    if (len > 0) {
                        if (buffer.add(len)) {
                            auto buf = _writeQueue.deQueue();
                            buf.doCallBack();
                            yDel(buf);
                        }
                        continue;
                    } else {
                        if (errno == EAGAIN || errno == EWOULDBLOCK) {
                            return;
                        } else if (errno == 4) {
                            warning("Interrupted system call the socket fd : ", fd);
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
            yuCathException!false(unActive());
    }

    override void onRead() nothrow {
        static if (IOMode == IO_MODE.iocp) {
            yuCathException!false({
                if (_event.readLen > 0) {
                    _readCallBack(_readBuffer[0 .. _event.readLen]);
                } else {
                    onClose();
                    return;
                }
            }());
            _event.readLen = 0;
            if (alive)
                doRead();

        } else {
            try {
                import core.stdc.string;

                while (alive) {
                    auto len = _socket.receive(_readBuffer);
                    if (len > 0) {
                        yuCathException!false(_readCallBack(_readBuffer[0 .. len]));
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
            _iocpBuffer.len = TCP_READ_BUFFER_SIZE;
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
                    yuCathException!false(error("WSARecv failed with error: ", dwLastError));
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
                    yuCathException!false(error("WSASend failed with error: ", dwLastError));
                    onClose();
                    return false;
                }
            }
            return true;
        }
    }

    final void clearWriteQueue() nothrow {
        while (!_writeQueue.empty) {
            auto buf = _writeQueue.deQueue();
            buf.doCallBack();
            yuCathException!false({ yDel(buf); }());
        }
    }

protected:
    import std.experimental.allocator.gc_allocator;

    Socket _socket;
    WriteSiteQueue _writeQueue;
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
struct WriteSite {
    this(ubyte[] data, TCPWriteCallBack cback = null) {
        _data = data;
        _site = 0;
        _cback = cback;
    }

    pragma(inline) bool add(size_t size) //如果写完了就返回true。
    {
        _site += size;
        if (_site >= _data.length)
            return true;
        else
            return false;
    }

    pragma(inline, true) @property size_t length() const {
        return (_data.length - _site);
    }

    pragma(inline, true) @property data() {
        return _data[_site .. $];
    }

    pragma(inline) void doCallBack() nothrow {

        if (_cback) {
            yuCathException!false(_cback(_data, _site));
        }
        _cback = null;
        _data = null;
    }

private:
    size_t _site = 0;
    ubyte[] _data;
    TCPWriteCallBack _cback;
    WriteSite* _next;
}

struct WriteSiteQueue {
    WriteSite* front() nothrow {
        return _frist;
    }

    bool empty() nothrow {
        return _frist is null;
    }

    void enQueue(WriteSite* wsite) nothrow
    in {
        assert(wsite);
    }
    body {
        if (_last) {
            _last._next = wsite;
        } else {
            _frist = wsite;
        }
        wsite._next = null;
        _last = wsite;
    }

    WriteSite* deQueue() nothrow
    in {
        assert(_frist && _last);
    }
    body {
        WriteSite* wsite = _frist;
        _frist = _frist._next;
        if (_frist is null)
            _last = null;
        return wsite;
    }

private:
    WriteSite* _last = null;
    WriteSite* _frist = null;
}
