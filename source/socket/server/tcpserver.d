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
module collie.socket.server.tcpserver;

import std.socket;

import collie.common;
import collie.socket.eventloop;
import collie.socket.acceptor;
import collie.socket.tcpsocket;
import collie.socket.timer;
import collie.socket.server.connection;
import collie.socket.server.exception;
import collie.utils.timingwheel;
import collie.utils.task;

@trusted final class TCPServer
{
	alias NewConnection = ServerConnection delegate(EventLoop,Socket);
	alias OnAceptorCreator = void delegate(Acceptor);
	alias TimerWheel = ITimingWheel!IAllocator;

	this(EventLoop loop)
	{
		_loop = loop;
	}
	~this(){
		if(_acceptor)
			dispose(collieAllocator,_acceptor);
		if(_timer)
			dispose(collieAllocator,_timer);
		if(_wheel)
			dispose(collieAllocator,_wheel);
		if(_bind)
			dispose(collieAllocator,_bind);
	}

	@property acceptor(){return _acceptor;}
	@property eventLoop(){return _loop;}
	@property bindAddress(){return _bind;}
	@property timeout(){return _timeout;}

	void bind(Address addr, OnAceptorCreator ona = null)
	{
		if(_acceptor !is null)
			throw new SocketBindException("the server is areadly binded!");
		_bind = addr;
		_acceptor = collieAllocator.make!Acceptor(_loop,addr.addressFamily);
		if(ona) ona(_acceptor);
		_acceptor.bind(_bind);
	}

	void listen(int block)
	{
		if(_acceptor is null)
			throw new SocketBindException("the server is not bind!");
		if(_cback is null)
			throw new SocketServerException("Please set CallBack frist!");

		_acceptor.setCallBack(&newConnect);
		_loop.post(allocTask(collieAllocator,&startListen,block));
	}

	void setNewConntionCallBack(NewConnection cback)
	{
		_cback = cback;
	}

	void startTimeout(uint s)
	{
		if(_wheel !is null)
			throw new SocketServerException("TimeOut is runing!");
		_timeout = s;
		if(_timeout == 0)return;

		uint whileSize;uint time; 
		if (_timeout <= 40)
		{
			whileSize = 50;
			time = _timeout * 1000 / 50;
		}
		else if (_timeout <= 120)
		{
			whileSize = 60;
			time = _timeout * 1000 / 60;
		}
		else if (_timeout <= 600)
		{
			whileSize = 100;
			time = _timeout * 1000 / 100;
		}
		else if (_timeout < 1000)
		{
			whileSize = 150;
			time = _timeout * 1000 / 150;
		}
		else
		{
			whileSize = 180;
			time = _timeout * 1000 / 180;
		}

		_wheel = collieAllocator.make!TimerWheel(whileSize,collieAllocator);
		_timer = collieAllocator.make!Timer(_loop);
		_timer.setCallBack(&prevWheel);
		_loop.post(allocTask(collieAllocator,&_timer.start,time));
	}

	void close()
	{
		if(_acceptor)
			_loop.post(&_acceptor.close);
	}
protected:
	void newConnect(Socket socket)
	{
		import std.exception;
		ServerConnection connection;
		collectException(_cback(_loop,socket),connection);
		if(connection is null) return;
		if(connection.active() && _wheel)
			_wheel.addNewTimer(connection);
	}

	void prevWheel(){
		_wheel.prevWheel();
	}

	void startListen(int block){
		_acceptor.listen(block);
		_acceptor.start();
	}
private:
	Acceptor _acceptor;
	EventLoop _loop;
	Address _bind;
private:
	NewConnection _cback;
private:
	TimerWheel _wheel;
	Timer _timer;
	uint _timeout;
}

