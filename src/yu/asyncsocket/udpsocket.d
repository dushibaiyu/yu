module yu.asyncsocket.udpsocket;

import core.stdc.errno;

import std.socket;
import std.functional;
import std.exception;

import yu.eventloop;
import yu.asyncsocket.transport;
import yu.exception : yuCathException, showException;

alias UDPWriteCallBack = void delegate(ubyte[] data, uint writeSzie);
// you should be yDel the Address, and the data if you save shoulde be copy;
alias UDPReadCallBack = void delegate(ubyte[] buffer, Address adr);

@trusted class UDPSocket : AsyncTransport, EventCallInterface {
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
        super(loop, TransportType.UDP);

        _socket = yNew!UdpSocket(family);

        _socket.blocking = true;
        _readBuffer = makeArray!ubyte(yuAlloctor, UDP_READ_BUFFER_SIZE);
        _event = AsyncEvent(AsynType.UDP, this, _socket.handle, true, false, false);
        static if (IO_MODE.iocp == IOMode) {
            _iocpBuffer.len = TCP_READ_BUFFER_SIZE;
            _iocpBuffer.buf = cast(char*) _readBuffer.ptr;
            _iocpread.event = &_event;
            _iocpread.operationType = IOCP_OP_TYPE.read;

            if (family == AddressFamily.INET)
                _bindddr = new InternetAddress(InternetAddress.PORT_ANY);
            else if (family == AddressFamily.INET6)
                _bindddr = new Internet6Address(Internet6Address.PORT_ANY);
            else
                _bindddr = new UnknownAddress();
        }
    }

    ~this() {
        if (_event.isActive)
            eventLoop.delEvent(&_event);
        yDel(_socket);
        yDel(_readBuffer);
        _readBuffer = null;
        static if (IO_MODE.iocp == IOMode) {
            if (_bindddr)
                yDel(_bindddr);
        }
    }

    @property reusePort(bool use) {
        _socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, use);
        version (Posix)
            _socket.setOption(SocketOptionLevel.SOCKET, cast(SocketOption) SO_REUSEPORT,
                use);
    }

    pragma(inline) final void setReadCallBack(UDPReadCallBack cback) {
        _readCallBack = cback;
    }

    void bind(Address addr) @trusted {
        static if (IO_MODE.iocp == IOMode) {
            _isBind = true;
            _bindddr = addr;
            trace("udp bind : ", addr.toAddrString());
        }
        _socket.bind(forward!addr);
    }

    bool connect(Address to) {
        if (!_socket.isAlive())
            return false;
        _connecto = to;
        return true;
    }

    pragma(inline) @safe ptrdiff_t sendTo(const(void)[] buf, Address to) {
        return _socket.sendTo(buf, to);
    }

    pragma(inline) @safe ptrdiff_t sendTo(const(void)[] buf) {
        ptrdiff_t len = -1;
        if (_connecto)
            len = _socket.sendTo(buf, _connecto);
        return len;
    }

    final override @property int fd() {
        return cast(int) _socket.handle();
    }

    pragma(inline, true) final @property localAddress() {
        return _socket.localAddress();
    }

    override bool start() {
        if (_event.isActive || !_socket.isAlive() || !_readCallBack)
            return false;
        _event = AsyncEvent(AsynType.UDP, this, _socket.handle, true, false, false);
        static if (IOMode == IO_MODE.iocp) {
            if (!_isBind) {
                bind(_bindddr);
            }
            _loop.addEvent(&_event);
            return doRead();
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
        bool alive;
        yuCathException!false((_event.isActive && _socket.handle() != socket_t.init), alive);
        return alive;
    }

    mixin TransportSocketOption;

protected:
    override void onRead() nothrow {
        try {
            static if (IO_MODE.iocp == IOMode) {
                if (_event.readLen > 0) {
                    setReadAddr();
                    _readCallBack(_readBuffer[0 .. _event.readLen], _readAddr);
                }
                scope (exit) {
                    _event.readLen = 0;
                    if (_socket.isAlive)
                        doRead();
                }
            } else {
                if (_readAddr is null)
                    _readAddr = createAddress();
                auto len = _socket.receiveFrom(_readBuffer, _readAddr);
                if (len <= 0)
                    return;
                Address tp = _readAddr;
                _readAddr = null;
                _readCallBack(_readBuffer[0 .. len], tp);

            }
        }
        catch (Exception e) {
            showException!false(e);
        }
    }

    override void onWrite() nothrow {
    }

    override void onClose() nothrow {
        if (!isAlive)
            return;
        eventLoop.delEvent(&_event);
        _socket.close();
        static if (IO_MODE.iocp == IOMode)
            _isBind = false;
    }

    static if (IO_MODE.iocp == IOMode) {
    package:
        pragma(inline, true) void setReadAddr() {
            if (remoteAddrLen == 32) {
                sockaddr_in* addr = cast(sockaddr_in*)(&remoteAddr);
                _readAddr = yNew!InternetAddress(*addr);
            } else {
                sockaddr_in6* addr = cast(sockaddr_in6*)(&remoteAddr);
                _readAddr = yNew!Internet6Address(*addr);
            }
        }

        bool doRead() nothrow {

            _iocpBuffer.len = TCP_READ_BUFFER_SIZE;
            _iocpBuffer.buf = cast(char*) _readBuffer.ptr;
            _iocpread.event = &_event;
            _iocpread.operationType = IOCP_OP_TYPE.read;
            remoteAddrLen = cast(int) _bindddr.nameLen();

            DWORD dwReceived = 0;
            DWORD dwFlags = 0;

            int nRet = WSARecvFrom(cast(SOCKET) _socket.handle, &_iocpBuffer,
                cast(uint) 1, &dwReceived, &dwFlags,
                cast(SOCKADDR*)&remoteAddr, &remoteAddrLen, &_iocpread.ol,
                cast(LPWSAOVERLAPPED_COMPLETION_ROUTINE) null);
            if (nRet == SOCKET_ERROR) {
                DWORD dwLastError = GetLastError();
                if (ERROR_IO_PENDING != dwLastError) {
                    yuCathException!false(error("WSARecvFrom failed with error: ", dwLastError));
                    onClose();
                    return false;
                }
            }
            return true;
        }

    private:
        IOCP_DATA _iocpread;
        WSABUF _iocpBuffer;

        sockaddr remoteAddr; //存储数据来源IP地址
        int remoteAddrLen; //存储数据来源IP地址长度

        Address _bindddr;
        bool _isBind = false;
    }

private:
    Address _connecto = null;
    Address _readAddr = null;
    UdpSocket _socket;
    AsyncEvent _event;
    ubyte[] _readBuffer;
    UDPReadCallBack _readCallBack;
}

unittest {
    /*    import std.conv;
    import std.stdio;

    EventLoop loop = new EventLoop();

    UDPSocket server = new UDPSocket(loop);
    UDPSocket client = new UDPSocket(loop);

    server.bind(new InternetAddress("127.0.0.1", 9008));
    Address adr = new InternetAddress("127.0.0.1", 9008);
    client.connect(adr);

    int i = 0;

    void serverHandle(ubyte[] data, Address adr2)
    {
        string tstr = cast(string) data;
        writeln("Server revec data : ", tstr);
        string str = "hello " ~ to!string(i);
        server.sendTo(data, adr2);
        assert(str == tstr);
        if (i > 10)
            loop.stop();
    }

    void clientHandle(ubyte[] data, Address adr23)
    {
        writeln("Client revec data : ", cast(string) data);
        ++i;
        string str = "hello " ~ to!string(i);
        client.sendTo(str);
    }

    client.setReadCallBack(&clientHandle);
    server.setReadCallBack(&serverHandle);

    client.start();
    server.start();

    string str = "hello " ~ to!string(i);
    client.sendTo(cast(ubyte[]) str);
    writeln("Edit source/app.d to start your project.");
    loop.run();
    server.close();
    client.close();
    */
}
