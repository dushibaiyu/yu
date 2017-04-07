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

@trusted class EchoConnect : ServerConnection
{
	this(TCPSocket sock){
		super(sock);
	}

protected:
	override void onActive() nothrow
	{
		collectException(writeln("new client connected : ",tcpSocket.remoteAddress.toString()));
	}

	override void onClose() nothrow
	{
		collectException(writeln("client disconnect"));
		collectException(yDel(this));
	}

	override void onRead(ubyte[] data) nothrow
	{
		collectException({
				writeln("read data : ", cast(string)data);
				this.write(data.dup);
			}());
	}

	override void onTimeOut() nothrow
	{
		collectException({
				writeln("client timeout : ",tcpSocket.remoteAddress.toString());
				close();
			}());
	}
}

void main()
{
	import std.experimental.allocator.mallocator;
	yuAlloctor = allocatorObject(Mallocator.instance);

	@trusted ServerConnection newConnect(EventLoop lop,Socket soc)
	{
		return yNew!EchoConnect(yNew!TCPSocket(lop,soc));
	}

	EventLoop loop = yNew!EventLoop();
	scope(exit)yDel(loop);
	TCPServer server = yNew!TCPServer(loop);
	scope(exit)yDel(server);
	server.setNewConntionCallBack(&newConnect);
	server.timeout = 120;
	server.bind(yNew!InternetAddress("127.0.0.1",cast(ushort)8094),(Acceptor accept){
			accept.reusePort(true);
		});
	server.listen(1024);

	loop.run();
}
