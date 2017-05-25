module yu.asyncsocket.sslsocket;

version (USE_SSL)  : import core.stdc.errno;
import core.stdc.string;

import core.thread;

import std.string;
import std.socket;
import std.exception;
import std.experimental.logger;

import yu.eventloop;
import yu.asyncsocket.transport;
import yu.asyncsocket.tcpsocket;
import yu.exception;

import deimos.openssl.ssl;
import deimos.openssl.bio;

@trusted class SSLSocket : TCPSocket {
    static if (IOMode == IO_MODE.iocp) {
        this(EventLoop loop, Socket sock, SSL * ssl, BIO * bioRead, BIO * bioWrite) {
            super(loop, sock);
            _ssl = ssl;
            _bioIn = bioRead;
            _bioOut = bioWrite;
            _rBuffer = makeArray!ubyte(yuAlloctor, TCP_READ_BUFFER_SIZE);
            _wBuffer = makeArray!ubyte(yuAlloctor, TCP_READ_BUFFER_SIZE);
        }
    } else {
        this(EventLoop loop, Socket sock, SSL * ssl) {
            super(loop, sock);
            _ssl = ssl;
        }
    }

    ~this() {
        if (_ssl) {
            SSL_shutdown(_ssl);
            SSL_free(_ssl);
            _ssl = null;
            _bioIn = null;
            _bioOut = null;
        }
        static if (IOMode == IO_MODE.iocp) {
            yDel(_rBuffer);
            yDel(_wBuffer);
        }
    }

    override @property bool isAlive() @trusted nothrow {
        return alive() && _isHandshaked;
    }

    pragma(inline) void setHandshakeCallBack(CallBack cback) {
        _handshakeCback = cback;
    }

    protected : override void onClose() {
        if (_ssl) {
            SSL_shutdown(_ssl);
            SSL_free(_ssl);
            _ssl = null;
            _bioIn = null;
            _bioOut = null;
        }
        super.onClose();
    }
    static if (IOMode == IO_MODE.iocp) {

        override void onWrite() {
            if (writeBIOtoSocket() || _writeQueue.empty)
                return;
            try {
                if (_lastWrite > 0) {
                    auto buffer = _writeQueue.front;
                    if (buffer.add(_lastWrite)) {
                        _writeQueue.deQueue().doCallBack();
                    }
                }
                if (!alive || _writeQueue.empty)
                    return;
                auto buffer = _writeQueue.front;
                _lastWrite = SSL_write(_ssl, buffer.data.ptr, cast(int) buffer.length); // data中存放了要发送的数据
                writeBIOtoSocket();
            }
            catch (Exception e) {
                showException(e);
            }
        }
        override void onRead() {
            try {
                if (!alive)
                    return;
                //trace("read data : data.length: ", _event.readLen);
                if (_event.readLen > 0) {
                    BIO_write(_bioIn, _readBuffer.ptr, cast(int) _event.readLen);
                    if (!_isHandshaked) {
                        if (!handlshake()) {
                            _event.readLen = 0;
                            doRead();
                            return;
                        }
                        onWrite();
                    }
                    while (true) {
                        int ret = SSL_read(_ssl, _rBuffer.ptr, cast(int) _rBuffer.length);
                        if (ret > 0) {
                            yuCathException!false(_readCallBack(_rBuffer[0 .. ret]));
                            continue;
                        } else {
                            break;
                        }
                    }
                } else {
                    onClose();
                    return;
                }
            }
            catch (Exception e) {
                showException(e);
            }
            _event.readLen = 0;
            if (alive)
                doRead();
        }
        bool writeBIOtoSocket() nothrow {
            if (!alive)
                return true;
            int hasread = BIO_read(_bioOut, _wBuffer.ptr, cast(int) _wBuffer.length);
            if (hasread > 0) {
                _iocpWBuf.len = hasread;
                _iocpWBuf.buf = cast(char * ) _wBuffer.ptr;
                _event.writeLen = 0;
                doWrite();
                return true;
            }
            return false;
        }
    } else {
        override void onWrite() {
            if (alive && !_isHandshaked) {
                if (!handlshake())
                    return;
            }
            try {
                while (alive && !_writeQueue.empty) {
                    auto buffer = _writeQueue.front;
                    auto len = SSL_write(_ssl, buffer.data.ptr, cast(int) buffer.length); // _socket.send(buffer.data);
                    if (len > 0) {
                        if (buffer.add(len)) {
                            _writeQueue.deQueue().doCallBack();
                        }
                        continue;
                    } else {
                        int sslerron = SSL_get_error(_ssl, len);
                        if (sslerron == SSL_ERROR_WANT_READ || errno == EWOULDBLOCK
                                || errno == EAGAIN)
                            break;
                        else if (errno == 4) // erro 4 :系统中断组织了
                            continue;
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
                import yu.exception;

                showException(e);
                onClose();
                return;
            }
        }

        override void onRead() {
            try {
                while (alive) {
                    if (!_isHandshaked) {
                        if (!handlshake())
                            return;
                    }
                    auto len = SSL_read(_ssl, (_readBuffer.ptr), cast(int)(_readBuffer.length));
                    if (len > 0) {
                        yuCathException!false(_readCallBack(_readBuffer[0 .. len]));
                        continue;
                    } else if (len < 0) {
                        int sslerron = SSL_get_error(_ssl, len);
                        if (sslerron == SSL_ERROR_WANT_READ || errno == EWOULDBLOCK
                                || errno == EAGAIN)
                            break;
                        else if (errno == 4) // erro 4 :系统中断组织了
                            continue;
                        import core.stdc.string;

                        error("Do Close the erro code : ", errno,
                            "  erro is : ", fromStringz(strerror(errno)),
                            " \n\tthe socket fd : ", fd);
                    }
                    onClose();
                    return;
                }
            }
            catch (Exception e) {
                import yu.exception;

                showException(e);
                onClose();
            }
        }
    }
    final bool handlshake() nothrow {
        int r = SSL_do_handshake(_ssl);
        static if (IOMode == IO_MODE.iocp)
            writeBIOtoSocket();
        if (r == 1) {
            _isHandshaked = true;
            if (_handshakeCback) {
                yuCathException!false(_handshakeCback());
            }
            return true;
        }
        int err = SSL_get_error(_ssl, r);
        if (err == SSL_ERROR_WANT_WRITE) {
            static if (IOMode == IO_MODE.iocp)
                writeBIOtoSocket();
            return false;
        } else if (err == SSL_ERROR_WANT_READ) {
            return false;
        } else {
            yuCathException!false(error("SSL_do_handshake return: ", r, "  erro :",
                err, "  errno:", errno, "  erro string:", fromStringz(strerror(errno))));
            onClose();
            return false;
        }
    }

    protected : bool _isHandshaked = false;

    private : SSL * _ssl;
    CallBack _handshakeCback;
    static if (IOMode == IO_MODE.iocp) {
        BIO * _bioIn;
        BIO * _bioOut;
        ubyte[] _rBuffer;
        ubyte[] _wBuffer;
        ptrdiff_t _lastWrite = 0;
    }
}
