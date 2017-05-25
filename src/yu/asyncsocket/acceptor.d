module yu.asyncsocket.acceptor;

import core.memory;
import core.sys.posix.sys.socket;

import std.socket;
import std.functional;
import std.exception;

import yu.eventloop;
import yu.asyncsocket.transport;
import yu.asyncsocket.tcpsocket;
import yu.asyncsocket.exception;
import yu.exception;

alias AcceptCallBack = void delegate(Socket sock);

@trusted final class Acceptor : AsyncTransport, EventCallInterface {
    this(EventLoop loop, bool isIpV6 = false) {
        auto family = isIpV6 ? AddressFamily.INET6 : AddressFamily.INET;
        this(loop, family);
    }

    this(EventLoop loop, AddressFamily family)
    in {
        assert(family == AddressFamily.INET6 || family == AddressFamily.INET,
            "the AddressFamily must be AddressFamily.INET or AddressFamily.INET6");
    }
    body {
        _socket = yNew!Socket(family, SocketType.STREAM, ProtocolType.TCP);
        _socket.blocking = false;
        _event = AsyncEvent(AsynType.ACCEPT, this, _socket.handle, true, false, false,
            false);
        super(loop, TransportType.ACCEPT);
        static if (IOMode == IO_MODE.iocp)
            _buffer = makeArray!ubyte(yuAlloctor, 2048);
    }

    ~this() {
        onClose();
        yDel(_socket);
        static if (IOMode == IO_MODE.iocp)
            yDel(_buffer);
    }

    @property reusePort(bool use) {
        _socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, use);
        version (Posix)
            _socket.setOption(SocketOptionLevel.SOCKET, cast(SocketOption) SO_REUSEPORT,
                use);
        version (windows) {
            if (!use) {
                import core.sys.windows.winsock2;

                accpet.setOption(SocketOptionLevel.SOCKET,
                    cast(SocketOption) SO_EXCLUSIVEADDRUSE, true);
            }
        }
    }

    void bind(Address addr) @trusted {
        static if (IO_MODE.iocp == IOMode) {
            _addreslen = addr.nameLen();
        }
        _socket.bind(forward!addr);
    }

    void listen(int backlog) @trusted {
        _socket.listen(forward!backlog);
    }

    override @property int fd() {
        return cast(int) _socket.handle();
    }

    pragma(inline, true) @property localAddress() {
        return _socket.localAddress();
    }

    override bool start() {
        if (_event.isActive || !_socket.isAlive() || !_callBack) {
            warning("accept start erro!");
            return false;
        }
        _event = AsyncEvent(AsynType.ACCEPT, this, _socket.handle, true, false, false,
            false);
        static if (IOMode == IO_MODE.iocp) {
            trace("start accept : , the fd is ", _socket.handle());
            _loop.addEvent(&_event);
            return doAccept();
        } else {
            return _loop.addEvent(&_event);
        }
    }

    override void close() {
        if (isAlive) {
            onClose();
        } else if (_socket.isAlive()) {
            _socket.close();
        }
    }

    override @property bool isAlive() @trusted nothrow {
        bool alive = false;
        yuCathException!false(_socket.isAlive(), alive);
        return alive;
    }

    mixin TransportSocketOption;

    void setCallBack(AcceptCallBack cback) {
        _callBack = cback;
    }

protected:
    override void onRead() nothrow {
        static if (IO_MODE.iocp == IOMode) {
            yuCathException!false({
                trace("new connect ,the fd is : ", _inSocket.handle());
                SOCKET slisten = cast(SOCKET) _socket.handle;
                SOCKET slink = cast(SOCKET) _inSocket.handle;
                setsockopt(slink, SOL_SOCKET, 0x700B, cast(const char*)&slisten, slisten.sizeof);
                _callBack(_inSocket);
            }());
            _inSocket = null;
            doAccept();
        } else {
            while (true) {
                socket_t fd = cast(socket_t)(.accept(_socket.handle, null, null));
                if (fd == socket_t.init)
                    return;
                yuCathException!false({
                    Socket sock = yNew!Socket(fd, _socket.addressFamily);
                    _callBack(sock);
                }());
            }
        }
    }

    override void onWrite() nothrow {
    }

    override void onClose() nothrow {
        if (!isAlive)
            return;
        eventLoop.delEvent(&_event);
        _socket.close();
    }

    static if (IOMode == IO_MODE.iocp) {
        bool doAccept() nothrow {
            try {
                _iocp.event = &_event;
                _iocp.operationType = IOCP_OP_TYPE.accept;
                if (_inSocket is null) {
                    _inSocket = yNew!Socket(_socket.addressFamily,
                        SocketType.STREAM, ProtocolType.TCP);
                }

                DWORD dwBytesReceived = 0;
                trace("AcceptEx is :  ", AcceptEx);
                int nRet = AcceptEx(cast(SOCKET) _socket.handle,
                    cast(SOCKET) _inSocket.handle, _buffer.ptr, 0,
                    sockaddr_in.sizeof + 16, sockaddr_in.sizeof + 16,
                    &dwBytesReceived, &_iocp.ol);
                trace("do AcceptEx : the return is : ", nRet);
                if (nRet == 0) {
                    DWORD dwLastError = GetLastError();
                    if (ERROR_IO_PENDING != dwLastError) {
                        yuCathException!false(error("AcceptEx failed with error: ", dwLastError));
                        onClose();
                        return false;
                    }
                }
            }
            catch (Exception e) {
                import yu.exception;

                showException(e);
            }
            return true;
        }
    }

private:
    Socket _socket;
    AsyncEvent _event;

    AcceptCallBack _callBack;

    static if (IO_MODE.iocp == IOMode) {
        IOCP_DATA _iocp;
        WSABUF _iocpWBuf;

        Socket _inSocket;

        ubyte[] _buffer;

        uint _addreslen;
    }
}

unittest {
    /*
    import std.datetime;
    import std.stdio;
    import std.functional;

    import yu.asyncsocket;

    EventLoop loop = new EventLoop();

    

    class TCP
    {
        static int[TCP] tcpList;
        this(EventLoop loop, Socket soc)
        {
            _socket = new TCPSocket(loop, soc);
            _socket.setReadCallBack(&readed);
            _socket.setCloseCallBack(&closed);
            _socket.start();
        }

        alias socket this;
        @property socket()
        {
            return _socket;
        }

    protected:
        void readed(ubyte[] buf)
        {
            writeln("read data :  ", cast(string)(buf));
            socket.write(buf.dup, &writed);
        }

        void writed(ubyte[] data, uint size)
        {
            writeln("write data Size :  ", size, "\t data size : ", data.length);
            ++_size;
            if (_size == 5)
                socket.write(data, &writeClose);
            else
            {
                socket.write(data, &writed);
            }

        }

        void writeClose(ubyte[] data, uint size)
        {
            writeln("write data Size :  ", size, "\t data size : ", data.length);
            socket.close();
            loop.stop();
            //	throw new Exception("hahahahhaah ");
        }

        void closed()
        {
            tcpList.remove(this);
            writeln("Socket Closed .");
        }

    private:
        TCPSocket _socket;
        int _size = 0;
    }
      
    void newConnect(Socket soc)
    {
        auto tcp = new TCP(loop, soc);
        TCP.tcpList[tcp] = 0;
    }
    
    

    Acceptor accept = new Acceptor(loop);

    accept.setCallBack(toDelegate(&newConnect));

    accept.reusePort(true);
    accept.bind(new InternetAddress("0.0.0.0", 6553));

    accept.listen(64);

    accept.start();

    loop.run(5000);
*/
}
