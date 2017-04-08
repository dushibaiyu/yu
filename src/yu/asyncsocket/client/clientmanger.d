module yu.asyncsocket.client.clientmanger;

import std.socket;

import yu.memory.allocator;
import yu.eventloop;
import yu.timer.eventlooptimer;
import yu.asyncsocket.tcpclient;
import yu.asyncsocket.tcpsocket;
import yu.asyncsocket.client.linkinfo;
import yu.asyncsocket.client.exception;

import yu.timer.timingwheeltimer;
import yu.task;

@trusted final class TCPClientManger {
    alias ClientCreatorCallBack = void delegate(TCPClient);
    alias ConCallBack = void delegate(ClientConnection);
    alias LinkInfo = TLinkInfo!(ConCallBack, TCPClientManger);
    alias NewConnection = ClientConnection delegate(TCPClient);
    alias STimerWheel = ITimingWheel!IAllocator;

    this(EventLoop loop) {
        _loop = loop;
    }

    ~this() {
        if (_timer)
            yDel(_timer);
        if (_wheel)
            yDel(_wheel);
    }

    void setClientCreatorCallBack(ClientCreatorCallBack cback) {
        _oncreator = cback;
    }

    void setNewConnectionCallBack(NewConnection cback) {
        _cback = cback;
    }

    @property eventLoop() {
        return _loop;
    }

    @property tryCout() {
        return _tryCout;
    }

    @property tryCout(uint count) {
        _tryCout = count;
    }

    @property timeWheel() {
        return _wheel;
    }

    @property timeout() {
        return _timeout;
    }

    void startTimer(uint s) {
        if (_wheel !is null)
            throw new SocketClientException("TimeOut is runing!");
        _timeout = s;
        if (_timeout == 0)
            return;

        uint whileSize;
        uint time;
        if (_timeout <= 40) {
            whileSize = 50;
            time = _timeout * 1000 / 50;
        } else if (_timeout <= 120) {
            whileSize = 60;
            time = _timeout * 1000 / 60;
        } else if (_timeout <= 600) {
            whileSize = 100;
            time = _timeout * 1000 / 100;
        } else if (_timeout < 1000) {
            whileSize = 150;
            time = _timeout * 1000 / 150;
        } else {
            whileSize = 180;
            time = _timeout * 1000 / 180;
        }

        _wheel = yNew!STimerWheel(whileSize, yuAlloctor);
        if (_timer is null)
            _timer = yNew!EventLoopTimer(_loop);
        _timer.setCallBack(&onTimer);
        if (_loop.isInLoopThread())
            _timer.start(time);
        else
            _loop.post(makeTask(yuAlloctor, &_timer.start, time));
    }

    void connect(Address addr, ConCallBack cback = null) {
        if (_cback is null)
            throw new SocketClientException("must set NewConnection callback ");
        LinkInfo* info = yNew!LinkInfo();
        info.addr = addr;
        info.tryCount = 0;
        info.cback = cback;
        if (_loop.isInLoopThread()) {
            _postConmnect(info);
        } else {
            _loop.post(makeTask(yuAlloctor, &_postConmnect, info));
        }
    }

    void stopTimer() {
        if (_wheel) {
            if (_loop.isInLoopThread()) {
                killTimer();
            } else {
                _loop.post(&killTimer);
            }
        }
    }

    void connectCallBack(LinkInfo* info, bool state) {
        import std.exception;

        if (info is null)
            return;
        if (state) {
            scope (exit) {
                _waitConnect.rmInfo(info);
                yDel(info);
            }
            ClientConnection con;
            collectException(_cback(info.client), con);
            if (con is null) {
                _loop.post(makeTask!freeTcpClient(yuAlloctor, info.client));
                return;
            }
            if (info.cback)
                info.cback(con);
            if (_wheel)
                _wheel.addNewTimer(con);
            con.onActive();
        } else {
            yDel(info.client);
            info.client = null;
            if (info.tryCount < _tryCout) {
                info.tryCount++;
                connect(info);
            } else {
                auto cback = info.cback;
                _waitConnect.rmInfo(info);
                yDel(info);
                if (cback)
                    cback(null);
            }
        }
    }

protected:
    void connect(LinkInfo* info) {
        info.client = yNew!TCPClient(_loop);
        if (_oncreator)
            _oncreator(info.client);
        info.manger = this;
        info.client.setCloseCallBack(&tmpCloseCallBack);
        info.client.setConnectCallBack(&info.connectCallBack);
        info.client.setReadCallBack(&tmpReadCallBack);
        info.client.connect(info.addr);
    }

    void tmpReadCallBack(ubyte[]) {
    }

    void tmpCloseCallBack() {
    }

    void onTimer() {
        _wheel.prevWheel();
    }

private:
    final void _postConmnect(LinkInfo* info) {
        _waitConnect.addInfo(info);
        connect(info);
    }

    void killTimer() {
        _timer.stop();
        if (_wheel)
            yDel(_wheel);
        _wheel = null;
    }

private:
    uint _tryCout = 1;
    uint _timeout;

    EventLoop _loop;
    EventLoopTimer _timer;
    STimerWheel _wheel;
    TLinkManger!(ConCallBack, TCPClientManger) _waitConnect;

    NewConnection _cback;
    ClientCreatorCallBack _oncreator;
}

@trusted void freeTcpClient(TCPClient client) {
    client.close();
    yDel(client);
}

@trusted abstract class ClientConnection : IWheelTimer!IAllocator {
    this(TCPClient client) {
        restClient(client);
    }

    ~this() {
        if (_client)
            yDel(_client);
    }

    final bool isAlive() @trusted {
        return _client && _client.isAlive;
    }

    final @property tcpClient() @safe {
        return _client;
    }

    final TCPClient restClient(TCPClient client) @trusted {
        TCPClient tmp = _client;
        if (_client !is null) {
            _client.setCloseCallBack(null);
            _client.setReadCallBack(null);
            _client.setConnectCallBack(null);
            _client = null;
        }
        if (client !is null) {
            _client = client;
            _loop = client.eventLoop;
            _client.setCloseCallBack(&doClose);
            _client.setReadCallBack(&onRead);
            _client.setConnectCallBack(&tmpConnectCallBack);
        }
        return _client;
    }

    final void write(ubyte[] data, TCPWriteCallBack cback = null) @trusted {
        if (_loop.isInLoopThread()) {
            _postWrite(data, cback);
        } else {
            _loop.post(makeTask(yuAlloctor, &_postWrite, data, cback));
        }
    }

    final void restTimeout() @trusted {
        if (_loop.isInLoopThread()) {
            rest();
        } else {
            _loop.post(makeTask(yuAlloctor, &rest, 0));
        }
    }

    pragma(inline) final void close() @trusted {
        _loop.post(&_postClose);
    }

protected:
    void onActive() nothrow;
    void onClose() nothrow;
    void onRead(ubyte[] data) nothrow;
private:
    final void tmpConnectCallBack(bool) {
    }

    final void doClose() @trusted {
        stop();
        onClose();
    }

    final void _postClose() {
        if (_client)
            _client.close();
    }

    final void _postWrite(ubyte[] data, TCPWriteCallBack cback) {
        if (_client) {
            rest();
            _client.write(data, cback);
        } else if (cback)
            cback(data, 0);
    }

private:
    TCPClient _client;
    EventLoop _loop;
}
