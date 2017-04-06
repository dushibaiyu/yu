module yu.asyncsocket.client.client;

import std.socket;

import yu.eventloop;
import yu.timer.eventlooptimer;
import yu.asyncsocket.tcpclient;
import yu.asyncsocket.tcpsocket;
import yu.asyncsocket.client.linkinfo;
import yu.asyncsocket.client.exception;
import yu.task;
import yu.memory.allocator;

@trusted abstract class BaseClient
{
	alias ClientCreatorCallBack = void delegate(TCPClient);
	alias LinkInfo = TLinkInfo!ClientCreatorCallBack;

	this(EventLoop loop) 
	{
		_loop = loop;
	}
	~this(){
		if(_info.client)
			yDel(_info.client);
		if(_timer)
			yDel(_timer);
	}

	final bool isAlive() @trusted
	{
		return _info.client && _info.client.isAlive;
	}

	final void setTimeout(uint s) @safe
	{
		_timeout = s;
	}

	@property tryCount(){return _tryCount;}
	@property tryCount(uint count){_tryCount = count;}

	final void connect(Address addr,ClientCreatorCallBack cback = null) @trusted
	{
		if(isAlive)
			throw new SocketClientException("must set NewConnection callback ");
		_info.tryCount = 0;
		_info.cback = cback;
		_info.addr = addr;
		_loop.post(&_postConnect);
	}


	final void write(ubyte[] data,TCPWriteCallBack cback = null) @trusted
	{
		if(_loop.isInLoopThread()){
			_postWrite(data,cback);
		} else {
			_loop.post(makeTask(yuAlloctor,&_postWrite,data,cback));
		}
	}

	pragma(inline)
	final void close() @trusted
	{
		if(_info.client is null) return;
		_loop.post(&_postClose);
	}

	final @property tcpClient() @trusted {return _info.client;}
	final @property timer() @trusted {return _timer;}
	final @property timeout() @safe {return _timeout;}
	final @property eventLoop() @trusted {return _loop;}
protected:
	void onActive() nothrow;
	void onFailure() nothrow;
	void onClose() nothrow;
	void onRead(ubyte[] data) nothrow;
	void onTimeout() nothrow;

	final startTimer()
	{
		if(_timeout == 0)
			return;
		if(_timer)
			_timer.stop();
		else {
			_timer = yNew!EventLoopTimer(_loop);
			_timer.setCallBack(&onTimeout);
		}
		_timer.start(_timeout * 1000);
	}
private:
	final void connect()
	{
		_info.client = yNew!TCPClient(_loop);
		if(_info.cback)
			_info.cback(_info.client);
		_info.client.setConnectCallBack(&connectCallBack);
		_info.client.setCloseCallBack(&doClose);
		_info.client.setReadCallBack(&onRead);
		_info.client.connect(_info.addr);
	}

	final void connectCallBack(bool state){
		if(state){
			_info.cback = null;
			onActive();
		} else {
			yDel(_info.client);
			_info.client = null;
			if(_info.tryCount < _tryCount){
				_info.tryCount ++;
			} else {
				_info.cback = null;
				if(_timer)
					_timer.stop();
				onFailure();
			}
		}

	}
	final void doClose()
	{
		import yu.task;
		if(_timer)
			_timer.stop();
		auto client = _info.client;
		_loop.post!true(makeTask!freeTcpClient(yuAlloctor,client));
		_info.client = null;
		onClose();
	}

private:
	final void _postClose(){
		if(_info.client)
			_info.client.close();
	}

	pragma(inline)
	final void _postWrite(ubyte[] data,TCPWriteCallBack cback){
		if(_info.client)
			_info.client.write(data, cback);
		else if(cback)
			cback(data,0);
	}

	final void _postConnect(){
		startTimer();
		connect();
	}

private
	EventLoop _loop;
	LinkInfo _info;
	uint _tryCount = 1;
	EventLoopTimer _timer;
	uint _timeout;
}

@trusted void freeTcpClient(TCPClient client)
{
	yDel(client);
}