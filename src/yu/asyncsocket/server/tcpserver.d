module yu.asyncsocket.server.tcpserver;

import std.socket;

import yu.memory.allocator;
import yu.eventloop;
import yu.asyncsocket.acceptor;
import yu.asyncsocket.tcpsocket;
import yu.asyncsocket.server.connection;
import yu.asyncsocket.server.exception;
import yu.timer.timingwheeltimer;
import yu.timer.eventlooptimer;
import yu.task;

@trusted final class TCPServer
{
	alias NewConnection = ServerConnection delegate(EventLoop,Socket);
	alias OnAceptorCreator = void delegate(Acceptor);
	alias STimerWheel = ITimingWheel!IAllocator;

	this(EventLoop loop)
	{
		_loop = loop;
	}

	~this(){
		if(_acceptor)
			dispose(yuAlloctor,_acceptor);
		if(_timer)
			dispose(yuAlloctor,_timer);
		if(_wheel)
			dispose(yuAlloctor,_wheel);
		if(_bind)
			dispose(yuAlloctor,_bind);
	}

	@property acceptor(){return _acceptor;}
	@property eventLoop(){return _loop;}
	@property bindAddress(){return _bind;}
	@property timeout(){return _timeout;}
	@property timeWheel(){return _wheel;}

	void bind(Address addr, OnAceptorCreator ona = null)
	{
		if(_acceptor !is null)
			throw new SocketBindException("the server is areadly binded!");
		_bind = addr;
		_acceptor = yuAlloctor.make!Acceptor(_loop,addr.addressFamily);
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
		_loop.post(makeTask(yuAlloctor,&startListen,block));
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

		_wheel = yuAlloctor.make!STimerWheel(whileSize,yuAlloctor);
		_timer = yuAlloctor.make!EventLoopTimer(_loop);
		_timer.setCallBack(&prevWheel);
		_loop.post(makeTask(yuAlloctor,&_timer.start,time));
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
	STimerWheel _wheel;
	EventLoopTimer _timer;
	uint _timeout;
}

