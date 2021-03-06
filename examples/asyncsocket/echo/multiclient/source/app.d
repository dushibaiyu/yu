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

import yu.asyncsocket;
import yu.asyncsocket.client.clientmanger;
import yu.eventloop;
import yu.memory.allocator;
import yu.exception;

@trusted class EchoConnect : ClientConnection {
    this(TCPClient sock, int id) {
        super(sock);
        _id = id;
    }

protected:
    override void onActive() nothrow {
        collectException(writeln(_id, " connected suess!"));
    }

    override void onClose() nothrow {
        collectException(writeln(_id, " client disconnect!"));
        collectException(yDel(this));
    }

    override void onRead(in ubyte[] data) nothrow {
        collectException({ writeln(_id, " . read data : ", cast(string) data); }());
    }

    override void onTimeOut() nothrow {
        collectException({
            if (isAlive) {
                ++size;
                if (size >= 3) {
                    close();
                    return;
                }

                writeln(_id, " time out do beat!");
                string data = Clock.currTime().toSimpleString();
                write(cast(ubyte[]) data, null);

            }
        }());
    }

    int _id;
    int size = 0;
}

__gshared _id = 10000;

void main() {
    import std.experimental.allocator.mallocator;

   // yuAlloctor = allocatorObject(Mallocator.instance);

    ClientConnection newConnect(TCPClient client) @trusted nothrow {
        ClientConnection rv;
        yuCathException(yNew!EchoConnect(client, ++_id), rv);
        return rv;
    }

    void createClient(TCPClient client) @trusted nothrow {
        yuCathException(writeln("new client!"));
    }

    void newConnection(ClientConnection contion) @trusted nothrow{
        yuCathException(writeln("new connection!!"));
    }

    EventLoop loop = yNew!EventLoop();
    scope (exit)
        yDel(loop);

    TCPClientManger manger = yNew!TCPClientManger(loop);
    scope (exit)
        yDel(manger);

    manger.setNewConnectionCallBack(&newConnect);
    manger.setClientCreatorCallBack(&createClient);
    manger.startTimer(5);
    manger.tryCout(3);
    foreach (i; 0 .. 20) {
        manger.connect(new InternetAddress("127.0.0.1", 8094), &newConnection);
    }

    loop.run();
}
