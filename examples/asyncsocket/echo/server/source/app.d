/*
 * Collie - An asynchronous event-driven network framework using Dlang development
 *
 * Copyright (C) 2015-2016  Shanghai Putao Technology Co., Ltd 
 *
 * Developer: putao's Dlang team
 *
 * Licensed under the Apache-2.0 License.
 *
 */
module app;

import core.thread;

import std.datetime;
import std.stdio;
import std.functional;
import std.exception;
import std.experimental.logger;

import yu.eventloop;
import yu.asyncsocket.server.tcpserver;
import yu.asyncsocket.server.connection;
import yu.asyncsocket;
import yu.task;
import yu.memory.allocator;
import yu.memory.gc;
import yu.exception;

final class WriteBuffer : TCPWriteBuffer
{
    this(ubyte[] data)
    {
        _data = yNewArray!ubyte(data.length);
        _data[] = data[];
    }

    ~this(){
        if(_data.ptr) {
            yDel(_data);
            _data = null;
        }
    }

    override ubyte[] data() nothrow
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
        yuCathException({yDel(this); }());
    }

private:
    size_t _site = 0;
    ubyte[] _data;
}

@trusted class EchoConnect : ServerConnection {
    this(TCPSocket sock) {
        super(sock);
    }

protected:
    override void onActive() nothrow {
        yuCathException(writeln("new client connected : ", tcpSocket.remoteAddress.toString()));
    }

    override void onClose() nothrow {
        yuCathException(writeln("client disconnect"));
        yuCathException(yDel(this));
    }

    override void onRead(ubyte[] data) nothrow {
        yuCathException({
            writeln("read data : ", cast(string) data);
            this.write(yNew!WriteBuffer(data));
        }());
    }

    override void onTimeOut() nothrow {
        yuCathException({
            writeln("client timeout : ", tcpSocket.remoteAddress.toString());
            close();
        }());
    }
}

void main() {
    import std.experimental.allocator.mallocator;

    //yuAlloctor = allocatorObject(Mallocator.instance);

    @trusted ServerConnection newConnect(EventLoop lop, Socket soc) nothrow {
        ServerConnection con;
        yuCathException(yNew!EchoConnect(yNew!TCPSocket(lop, soc)), con);
        return con;
    }

    EventLoop loop = yNew!EventLoop();
    scope (exit)
        yDel(loop);
    TCPServer server = yNew!TCPServer(loop);
    scope (exit)
        yDel(server);
    server.setNewConntionCallBack(&newConnect);

    server.bind(yNew!InternetAddress("127.0.0.1", cast(ushort) 8094), (Acceptor accept) {
        accept.reusePort(true);
    });
    server.listen(1024);
    server.startTimer(120);
    loop.run();
}
