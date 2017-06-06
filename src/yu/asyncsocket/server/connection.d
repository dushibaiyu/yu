module yu.asyncsocket.server.connection;

import yu.timer.timingwheeltimer;
import yu.asyncsocket.tcpsocket;
import yu.eventloop;
import yu.memory.allocator;
import yu.task;
import yu.exception;

@trusted abstract class ServerConnection : IWheelTimer!IAllocator {
    this(TCPSocket socket) {
        restSocket(socket);
    }

    ~this() {
        if (_socket)
            yDel(_socket);
    }

    final TCPSocket restSocket(TCPSocket socket) {
        TCPSocket tmp = _socket;
        if (_socket !is null) {
            _socket.setCloseCallBack(null);
            _socket.setReadCallBack(null);
            _socket = null;
            _loop = null;
        }
        if (socket !is null) {
            _socket = socket;
            _loop = socket.eventLoop;
            _socket.setCloseCallBack(&doClose);
            _socket.setReadCallBack(&onRead);
        }
        return tmp;
    }

    final bool isAlive() @trusted {
        return _socket && _socket.isAlive;
    }

    final bool active() @trusted nothrow {
        if (_socket is null)
            return false;
        bool active = false;
        yuCathException(_socket.start(), active);
        if (active)
            onActive();
        return active;
    }

    final void write(ubyte[] data, TCPWriteCallBack cback = null) @trusted {
        if (_loop.isInLoopThread()) {
            _postWrite(data, cback);
        } else {
            auto task = makeTask(yuAlloctor, &_postWrite, data, cback);
            task.finishedCall = &_loop.finishDoFreeYuTask;
            _loop.post(task);
        }
    }

    final void write(TCPWriteBuffer buffer) @trusted
    {
        if (_loop.isInLoopThread()) {
            _postWriteBuffer(buffer);
        } else {
            auto task = makeTask(yuAlloctor, &_postWriteBuffer, buffer);
            task.finishedCall = &_loop.finishDoFreeYuTask;
            _loop.post(task);
        }
    }


    final void restTimeout() @trusted {
        if (_loop.isInLoopThread()) {
            rest();
        } else {
            auto task = makeTask(yuAlloctor, &rest, 0);
            task.finishedCall = &_loop.finishDoFreeYuTask;
            _loop.post(task);
        }
    }

    pragma(inline) final void close() @trusted {
        _loop.post(&_postClose);
    }

    final @property tcpSocket() @safe {
        return _socket;
    }

    final @property eventLoop() @safe {
        return _loop;
    }

protected:
    void onActive() nothrow;
    void onClose() nothrow;
    void onRead(ubyte[] data) nothrow;

private:
    final void _postClose() {
        if (_socket)
            _socket.close();
    }

    final void _postWriteBuffer(TCPWriteBuffer buffer)
    {
        if (_socket) {
            rest();
            _socket.write(buffer);
        } else
            buffer.doFinish();
    }

    final void _postWrite(ubyte[] data, TCPWriteCallBack cback) {
        if (_socket) {
            rest();
            _socket.write(data, cback);
        } else if (cback)
            cback(data, 0);
    }

    final void doClose() nothrow {
        stop();
        onClose();
    }

private:
    TCPSocket _socket;
    EventLoop _loop;
}
